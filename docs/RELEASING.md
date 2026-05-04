# Releasing

Two independent release flows. Pick whichever the change touches:

- **Backend-only change** (Python in `cosma/`): bump PyPI, end users
  pick it up on next launch via `uv tool upgrade cosma`. See
  [Backend release flow](#backend-release-flow-pypi).
- **Frontend change** (`.swift`, entitlements, Info.plist, anything
  in `fileSearchForntend/`): cut a Sparkle update; users get a
  prompt-on-detect dialog the next time the app phones home. See
  [Frontend release flow](#frontend-release-flow-sparkle--github-releases).

A change touching both should publish backend first (PyPI release),
then frontend (so the new app shell pairs with the new backend).
The `kPairedBackendVersion` constant in
`Services/BackendCompatibility.swift` plus the `__api_version__`
handshake gate prevent mismatched pairs from running.

---

## Backend release flow (PyPI)

The Python backend ships to PyPI from the separate `cosma` repo; the
macOS app auto-upgrades to the latest release on every launch. You
don't need to rebuild or re-ship the Swift app for a backend-only change.

### How clients pick up new backends

`CosmaManager.upgradeCosmaIfNeeded()` runs before the server starts in
the "installed cosma" launch strategy:

- Reads `cosma --version` (installed) and fetches the latest PyPI
  version with a 3 s timeout.
- If they differ, runs `uv tool upgrade cosma --no-cache` (bounded by
  120 s). Non-fatal: on timeout or error, launch continues with the
  existing version.

So to roll out a backend fix, just publish a new PyPI release — users
get it on their next app launch with no intervention.

### Publishing a new backend release

Run in the `cosma` repo:

1. Bump `version` in the root `pyproject.toml` and in every changed
   `packages/*/pyproject.toml`. Keep versions in lockstep.
2. `git commit -m "v0.8.0"`.
3. `git tag v0.8.0`.
4. `git push && git push --tags`.
5. `.github/workflows/release.yml` (cosma repo) builds wheels and
   publishes to PyPI via trusted publishing.

See `cosma/docs/RELEASING.md` for backend-side details.

---

## Frontend release flow (Sparkle + GitHub Releases)

The Swift app ships via Sparkle, which polls a public appcast XML
feed on every launch (and on a daily timer). When a newer version
appears, the user gets a "v1.2.0 is available" dialog → Sparkle
downloads the .zip → verifies EdDSA signature + Apple notarization
ticket → swaps the .app bundle on disk → relaunches.

Two channels:

| Channel | Tag pattern | GitHub Release flag | Appcast |
|---------|-------------|---------------------|---------|
| Stable  | `v1.2.3`        | (latest)            | `stable.xml` |
| Dev     | `v1.2.3-dev`    | `--prerelease`      | `dev.xml`    |

End users default to **Stable**; they can opt into Dev in
Settings → General → App Updates → Release Channel.

### One-time setup

These steps are required **once**, before the first frontend release:

#### 1. Apple notarization credentials

Notarization is mandatory — Gatekeeper blocks any auto-replaced .app
that doesn't have an Apple-stamped approval ticket. Set up your
credentials in your login keychain:

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
    --apple-id <your apple id> \
    --team-id LYA7Q8JY3U \
    --password <app-specific password>
```

The app-specific password comes from
[appleid.apple.com](https://appleid.apple.com) → "App-Specific
Passwords". The credential is named `AC_NOTARY` in the keychain;
the release script references it by that name. No secret ends up
in code, in git, or in env vars.

#### 2. Sparkle EdDSA private key

Already done — there's a private key in your login keychain (created
via `Sparkle.framework/.../bin/generate_keys`), and the matching
public key is committed in `fileSearchForntend/Info.plist` under
`SUPublicEDKey`. The release script's `sign_update` call reads the
private key from the keychain automatically.

If you ever need to **re-key** (lost machine, suspected compromise),
run `generate_keys` again and update `SUPublicEDKey` in `Info.plist`
to match. Every previously installed app then needs a manual reinstall
because their bundled public key no longer matches your signatures.

#### 3. GitHub Pages for the appcast

The appcast XML files (`stable.xml`, `dev.xml`) need a public,
stable URL that matches what's in `Info.plist` and
`UpdateChannel.feedURL`:

- `https://cosmasense.github.io/appcast/stable.xml`
- `https://cosmasense.github.io/appcast/dev.xml`

Set up by creating a `cosmasense/appcast` repo (or whichever
owner/name pair you prefer — change the URLs in both
`Info.plist` and `Services/SparkleUpdaterController.swift` to
match), enabling GitHub Pages on the default branch root, and
copying `release/appcast/*.xml` into it.

If you change the URL after shipping, every installed app on the
old URL is stranded — they'll keep polling the dead feed silently.
Pick the URL once.

#### 4. `gh` CLI

`gh auth login` so the release script can create GitHub Releases
without a PAT in env.

### Per-release flow

Run from the project root (`fileSearchForntend/`):

```bash
GH_REPO=cosmasense/macos release/scripts/publish.sh stable 1.0.1
```

Or for a dev build:

```bash
GH_REPO=cosmasense/macos release/scripts/publish.sh dev 1.1.0
```

The script does, in order:

1. **Build + archive**, passing `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` so you don't have to bump them by hand
   in `project.pbxproj` for every release.
2. **Export** as a Developer ID-signed `.app`.
3. **Zip** with `ditto -c -k --keepParent` (preserves the bundle).
4. **Notarize** via `xcrun notarytool submit --wait`. Apple takes
   2-5 min.
5. **Staple** the approval ticket into the bundle, then re-zip so
   the staple ships in the .zip Sparkle downloads.
6. **EdDSA-sign** the zip with `sign_update`.
7. **Publish** as a GitHub Release. Dev channel uses `--prerelease`.
8. **Append** a new `<item>` to `release/appcast/<channel>.xml`.

After the script returns, commit + push the appcast change. If your
appcast lives in a separate `gh-pages`-style repo, copy
`release/appcast/<channel>.xml` over there instead.

### Dry run

```bash
DRY_RUN=1 GH_REPO=cosmasense/macos release/scripts/publish.sh stable 1.0.1
```

Builds, notarizes, signs — but skips the GH Release upload and leaves
the appcast change in your working tree. Useful for the first run-through
to make sure all the credentials work without committing to a real
version number.

### Environment knobs

| Var | Default | Purpose |
|-----|---------|---------|
| `GH_REPO` | (required) | `owner/repo` for `gh release create`. |
| `NOTARY_PROFILE` | `AC_NOTARY` | Keychain profile name from `xcrun notarytool store-credentials`. |
| `APPCAST_URL_BASE` | `https://cosmasense.github.io/appcast` | URL prefix; the .zip download URL is derived from this + tag + filename. |
| `DRY_RUN` | `0` | Skip GH upload + appcast commit when set to `1`. |

### Coordinating with a backend api_version bump

If a frontend release also requires a new backend api_version (e.g.
breaking JSON wire change), the order is:

1. Backend: bump `__api_version__` in `cosma_backend/__init__.py`,
   bump `pyproject.toml` MAJOR or MINOR, publish to PyPI.
2. Frontend: bump `kRequiredBackendApiVersion` and
   `kPairedBackendVersion` in `Services/BackendCompatibility.swift`
   to match. Then run the release script.

The handshake at `/api/status/version` is the safety net: if a
Sparkle-installed frontend lands on top of an out-of-range backend
(or vice versa), the user sees a clear "Update the app" /
"Update the backend" message instead of silent wire-format breakage.
