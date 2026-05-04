#!/usr/bin/env bash
#
# publish.sh — build, sign, notarize, and publish a Cosma Sense release.
#
# Usage:
#   release/scripts/publish.sh <channel> <version> [build]
#
# Args:
#   channel  stable | dev
#   version  semver, e.g. 1.0.1 (becomes CFBundleShortVersionString)
#   build    optional integer (becomes CFBundleVersion). Defaults to a
#            timestamp so a re-release with the same version still has
#            a unique build number — Sparkle compares CFBundleVersion
#            for "is this newer than what's running".
#
# Environment:
#   GH_REPO         e.g. "ethanpan/cosma-sense" — owner/repo for
#                   GitHub Releases. Required.
#   NOTARY_PROFILE  Keychain profile from `xcrun notarytool
#                   store-credentials`. Defaults to "AC_NOTARY".
#   APPCAST_URL_BASE  Public URL prefix where the appcast lives.
#                   Defaults to https://cosmasense.github.io/appcast
#                   — must match what's in Info.plist (SUFeedURL) and
#                   in UpdateChannel.feedURL.
#   APPCAST_REPO    Local path to the appcast repo's working tree.
#                   Defaults to ../appcast (sibling of the frontend
#                   repo). The appcast lives in its own repo so its
#                   URL is decoupled from frontend repo churn — see
#                   that repo's README for the rationale.
#   DRY_RUN=1       Build and notarize but skip GH Release upload and
#                   appcast commit. Useful for the first run-through.
#
# Prerequisites (one-time):
#   1. xcrun notarytool store-credentials AC_NOTARY \
#        --apple-id <your apple id> \
#        --team-id LYA7Q8JY3U \
#        --password <app-specific password from appleid.apple.com>
#   2. gh auth login (so `gh release` works without a token in env)
#   3. Sparkle EdDSA key in your login keychain (already done — the
#      public key is committed in Info.plist as SUPublicEDKey).
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Args + paths
# ---------------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <stable|dev> <version> [build]" >&2
    exit 64
fi

CHANNEL="$1"
VERSION="$2"
BUILD="${3:-$(date +%s)}"

case "$CHANNEL" in
    stable|dev) ;;
    *) echo "channel must be 'stable' or 'dev', got: $CHANNEL" >&2; exit 64;;
esac

GH_REPO="${GH_REPO:?set GH_REPO=owner/repo}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
APPCAST_URL_BASE="${APPCAST_URL_BASE:-https://cosmasense.github.io/appcast}"
DRY_RUN="${DRY_RUN:-0}"

# Locate ourselves and project. The script lives at
# release/scripts/publish.sh, so the project root is two levels up.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$PROJECT_ROOT/release"

# Appcast lives in its own repo (cosmasense/appcast on GitHub) so its
# public URL is decoupled from the frontend repo. We keep the working
# tree as a sibling of the frontend project at $PROJECT_ROOT/../appcast
# so the script can append + push without the user juggling cwd.
APPCAST_REPO="${APPCAST_REPO:-$PROJECT_ROOT/../appcast}"
APPCAST_FILE="$APPCAST_REPO/${CHANNEL}.xml"
if [[ ! -f "$APPCAST_FILE" ]]; then
    echo "appcast file not found: $APPCAST_FILE" >&2
    echo "either set APPCAST_REPO=/path/to/appcast or clone the" >&2
    echo "cosmasense/appcast repo to $APPCAST_REPO first." >&2
    exit 1
fi
BUILD_DIR="$RELEASE_DIR/build/${VERSION}"
PROJECT="$PROJECT_ROOT/fileSearchForntend.xcodeproj"
SCHEME="fileSearchForntend"
APP_NAME="Cosma Sense"

# Tag convention: dev releases get a -dev.N suffix so GitHub treats
# them as prereleases (and our channel filter is unambiguous).
if [[ "$CHANNEL" == "dev" ]]; then
    TAG="v${VERSION}-dev"
    PRERELEASE_FLAG="--prerelease"
else
    TAG="v${VERSION}"
    PRERELEASE_FLAG=""
fi

ZIP_NAME="CosmaSense-${VERSION}.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${TAG}/${ZIP_NAME}"

mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Sparkle helper-tool paths (under DerivedData via SPM artifacts)
# ---------------------------------------------------------------------------

SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update' \
    2>/dev/null | head -n1)"
if [[ -z "$SPARKLE_BIN" ]]; then
    echo "sign_update not found — open the project in Xcode once to" >&2
    echo "let SPM resolve Sparkle, then re-run." >&2
    exit 1
fi
SPARKLE_BIN_DIR="$(dirname "$SPARKLE_BIN")"

# ---------------------------------------------------------------------------
# 1. Build + archive
# ---------------------------------------------------------------------------

echo "[1/6] Building $APP_NAME v${VERSION} (build ${BUILD}, channel ${CHANNEL})…"

ARCHIVE_PATH="$BUILD_DIR/CosmaSense.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    archive | tail -3

# ExportOptions.plist for Developer ID distribution. Generated inline
# so the script is self-contained — no sidecar plist to keep in sync.
EXPORT_OPTS="$BUILD_DIR/ExportOptions.plist"
cat >"$EXPORT_OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>LYA7Q8JY3U</string>
</dict>
</plist>
EOF

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTS" | tail -3

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "expected $APP_PATH but it doesn't exist" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Zip (ditto preserves bundle structure + extended attrs)
# ---------------------------------------------------------------------------

echo "[2/6] Zipping…"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
SIZE_BYTES=$(stat -f%z "$ZIP_PATH")
echo "  $ZIP_NAME: ${SIZE_BYTES} bytes"

# ---------------------------------------------------------------------------
# 3. Notarize
# ---------------------------------------------------------------------------

echo "[3/6] Submitting to Apple for notarization (this usually takes 2-5 min)…"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# Apple wants the ticket stapled INTO the .app bundle, not the zip.
# Unzip, staple, re-zip.
echo "[3/6] Stapling ticket into bundle…"
STAPLE_DIR="$BUILD_DIR/staple"
rm -rf "$STAPLE_DIR" && mkdir -p "$STAPLE_DIR"
ditto -x -k "$ZIP_PATH" "$STAPLE_DIR"
xcrun stapler staple "$STAPLE_DIR/$APP_NAME.app"
rm "$ZIP_PATH"
ditto -c -k --keepParent "$STAPLE_DIR/$APP_NAME.app" "$ZIP_PATH"
SIZE_BYTES=$(stat -f%z "$ZIP_PATH")
echo "  re-zipped with stapled ticket: ${SIZE_BYTES} bytes"

# Belt + suspenders: verify the staple actually sticks.
xcrun stapler validate "$STAPLE_DIR/$APP_NAME.app"

# ---------------------------------------------------------------------------
# 4. Sparkle EdDSA signature
# ---------------------------------------------------------------------------

echo "[4/6] Signing for Sparkle…"
SIG_OUTPUT="$("$SPARKLE_BIN_DIR/sign_update" "$ZIP_PATH")"
# sign_update prints e.g. `sparkle:edSignature="abc..." length="12345"`
# — parse the signature out of that.
ED_SIG="$(echo "$SIG_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
if [[ -z "$ED_SIG" ]]; then
    echo "could not parse EdDSA signature from sign_update output:" >&2
    echo "  $SIG_OUTPUT" >&2
    exit 1
fi
echo "  signature: ${ED_SIG:0:24}…"

# ---------------------------------------------------------------------------
# 5. Publish to GitHub Releases
# ---------------------------------------------------------------------------

if [[ "$DRY_RUN" == "1" ]]; then
    echo "[5/6] DRY_RUN=1 — skipping GH Release upload."
    echo "       Would upload $ZIP_NAME to ${GH_REPO}@${TAG}"
else
    echo "[5/6] Publishing to GitHub Release ${TAG}…"
    NOTES_FILE="$BUILD_DIR/notes.md"
    if [[ ! -f "$NOTES_FILE" ]]; then
        printf 'Cosma Sense %s (%s channel)\n' "$VERSION" "$CHANNEL" >"$NOTES_FILE"
    fi
    gh release create "$TAG" "$ZIP_PATH" \
        --repo "$GH_REPO" \
        --title "Cosma Sense $VERSION" \
        --notes-file "$NOTES_FILE" \
        $PRERELEASE_FLAG
fi

# ---------------------------------------------------------------------------
# 6. Append to appcast
# ---------------------------------------------------------------------------

echo "[6/6] Appending to ${CHANNEL}.xml…"

# pubDate in RFC 822 — what RSS expects. macOS `date` lives in BSD
# land so we can't use GNU --rfc-email; the explicit format string is
# RFC 822 compliant.
PUBDATE="$(LC_TIME=C date "+%a, %d %b %Y %H:%M:%S %z")"

# Stage the new <item> in a temp file. sed's `r` command (next line)
# is the robust way to insert multi-line content after a matching
# line — passing multi-line strings to awk via -v breaks on the
# embedded newlines, which is how the first cut of this script blew
# up. The file goes away as soon as we mv the result back.
NEW_ITEM_FILE="$(mktemp)"
trap 'rm -f "$NEW_ITEM_FILE"' EXIT
cat >"$NEW_ITEM_FILE" <<EOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${SIZE_BYTES}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIG}"/>
        </item>
EOF

# Insert the new item right after <language>en</language>. macOS sed
# wants the `r filename` form on its own line (no trailing semicolon
# or args) — the `$'\n'` literal newline in the script lets us do
# that inside an -e block.
sed -i.bak -e $'/<language>en<\\/language>/r '"$NEW_ITEM_FILE" "$APPCAST_FILE"
rm -f "${APPCAST_FILE}.bak"

echo
echo "Appcast updated: $APPCAST_FILE"

if [[ "$DRY_RUN" == "1" ]]; then
    echo
    echo "DRY_RUN=1 — appcast change is in $APPCAST_REPO working tree"
    echo "but not committed. Inspect with:"
    echo "  git -C $APPCAST_REPO diff"
    echo "Then revert it (since this was a dry run):"
    echo "  git -C $APPCAST_REPO checkout -- ${CHANNEL}.xml"
else
    echo
    echo "Committing + pushing the appcast change…"
    git -C "$APPCAST_REPO" add "${CHANNEL}.xml"
    git -C "$APPCAST_REPO" commit -m "Release ${TAG}"
    git -C "$APPCAST_REPO" push
    echo
    echo "Done. New version is live in 1-2 min once GH Pages rebuilds:"
    echo "  ${APPCAST_URL_BASE}/${CHANNEL}.xml"
fi
