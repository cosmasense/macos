//
//  BackendCompatibility.swift
//  fileSearchForntend
//
//  Frontend↔backend version handshake.
//
//  The frontend bundles a pinned backend API version it knows how to
//  speak. On launch (after the backend health-poll succeeds) we hit
//  GET /api/status/version and compare. A mismatch is a hard stop —
//  we refuse to operate the search/index UI rather than send requests
//  the backend will misinterpret or vice versa.
//
//  Why this exists: until 2026-05-01 the auto-upgrade path
//  (`uv tool upgrade cosma --no-cache` on every launch) could pull
//  the backend forward to a version that introduced new wire-level
//  enums (e.g. ProcessingStatus.PARSED / SUMMARIZED) that the running
//  Swift binary couldn't decode. The user reported it as "API issue
//  after auto-update." The contract pin below + the upgrade clamp in
//  CosmaManager.upgradeCosmaIfNeeded together prevent that drift.
//
//  Bump procedure (matches cosma_backend/__init__.py):
//    1. Backend bumps __api_version__ when the wire format changes.
//    2. Update `kRequiredBackendApiVersion` here in lockstep.
//    3. Cut a coordinated frontend+backend release.
//

import Foundation

enum BackendCompatibility {
    /// The exact backend api_version this frontend build is paired with.
    /// MUST match `cosma_backend.__api_version__` at the time we cut a
    /// coordinated release. Increment in lockstep with the backend bump.
    static let kRequiredBackendApiVersion: Int = 1

    /// Optional ceiling for the auto-upgrader. We will not pull the
    /// backend forward to a version whose api_version exceeds this.
    /// Defaults to the required version — i.e., no auto-upgrade past
    /// what we can talk to. If you want to allow forward-compatible
    /// patch-level upgrades inside the same api_version, leave this
    /// equal to kRequiredBackendApiVersion (auto-upgrades that don't
    /// bump api_version are fine; ones that do are blocked).
    static let kMaxAcceptableBackendApiVersion: Int = kRequiredBackendApiVersion

    /// The package version this frontend build was paired with. The
    /// auto-upgrader treats this as a "minimum acceptable" floor: any
    /// running version below it gets unconditionally upgraded forward
    /// to the latest PyPI release that's at least this version. This
    /// is the lever that lets a major bump (e.g. 0.8.x → 1.0.0) reach
    /// existing users — the older "must match major.minor" rule would
    /// have stranded them on 0.8.x forever. Bump this in lockstep with
    /// every coordinated frontend release.
    static let kPairedBackendVersion: String = "1.0.7"

    enum CompatibilityResult {
        case compatible(BackendVersionResponse)
        /// Backend speaks a newer API than we know how to. User must
        /// upgrade the frontend (or downgrade the backend).
        case backendTooNew(have: Int, frontendSupports: Int, backendVersion: String)
        /// Backend is older than the floor it advertises that it
        /// requires. User must upgrade the backend (we won't auto-upgrade
        /// past our pinned version, so they have to do it manually).
        case backendTooOld(have: Int, backendRequires: Int, backendVersion: String)
        /// We couldn't reach /api/status/version (404, network error,
        /// malformed JSON). Treated as a hard fail — we don't know what
        /// we're talking to.
        case probeFailed(String)

        var isCompatible: Bool {
            if case .compatible = self { return true }
            return false
        }

        var userFacingMessage: String {
            switch self {
            case .compatible:
                return ""
            case let .backendTooNew(have, frontendSupports, backendVersion):
                return """
                Backend (\(backendVersion), API v\(have)) is newer than \
                this app supports (API v\(frontendSupports)). \
                Update the app to continue. The backend was not \
                downgraded to protect your indexed data.
                """
            case let .backendTooOld(have, backendRequires, backendVersion):
                return """
                Backend (\(backendVersion), API v\(have)) is older \
                than required (API v\(backendRequires)). Upgrade the \
                backend with `uv tool upgrade cosma`, or update this \
                app to a version that pairs with it.
                """
            case let .probeFailed(reason):
                return """
                Could not verify the backend version: \(reason). \
                Refusing to operate until the handshake succeeds.
                """
            }
        }
    }

    /// Run the handshake against the live backend. Safe to call from
    /// any actor — does its own dispatch.
    static func check(using client: APIClient = .shared) async -> CompatibilityResult {
        do {
            let v = try await client.fetchBackendVersion()
            // Backend tells us the floor it requires (some Swift builds
            // are older than this).
            if kRequiredBackendApiVersion < v.minFrontendApiVersion {
                return .backendTooOld(
                    have: v.apiVersion,
                    backendRequires: v.minFrontendApiVersion,
                    backendVersion: v.backendVersion,
                )
            }
            // Backend speaks newer than we know.
            if v.apiVersion > kMaxAcceptableBackendApiVersion {
                return .backendTooNew(
                    have: v.apiVersion,
                    frontendSupports: kMaxAcceptableBackendApiVersion,
                    backendVersion: v.backendVersion,
                )
            }
            return .compatible(v)
        } catch {
            return .probeFailed(error.localizedDescription)
        }
    }

    /// Should the auto-upgrader pull a `latestPyPI` release? PyPI only
    /// exposes string versions, so we can't read api_version directly —
    /// instead we layer two rules:
    ///
    /// 1. **Paired-baseline catch-up**: if the running backend is older
    ///    than `kPairedBackendVersion`, allow any upgrade that lands at
    ///    or above that baseline. This is the path that gets users on
    ///    a previous major series (e.g. 0.8.x) onto the current one
    ///    (1.0.0) — the post-launch api_version handshake remains the
    ///    safety net if a wire-format change actually slipped in.
    ///
    /// 2. **Same-major.minor patch**: once running ≥ baseline, only
    ///    accept patch-level moves within the same MAJOR.MINOR range.
    ///    Future api_version bumps must come with a coordinated
    ///    frontend release that updates `kPairedBackendVersion` to
    ///    re-open the upgrade gate.
    ///
    /// Returns true iff the upgrade is safe to attempt automatically.
    static func shouldAutoUpgrade(
        runningVersion: String?,
        latestVersion: String,
    ) -> Bool {
        guard let running = runningVersion else {
            // No baseline → don't auto-upgrade. Forces a clean install
            // path with explicit user action.
            return false
        }
        // Catch-up path: running is below the version we ship paired
        // with, and the candidate isn't worse than that floor → take it.
        if compareSemver(running, kPairedBackendVersion) < 0,
           compareSemver(latestVersion, kPairedBackendVersion) >= 0 {
            return true
        }
        return semverMajorMinorMatches(running, latestVersion)
    }

    /// "0.8.7" and "0.8.12" → true. "0.8.x" and "0.9.0" → false. "1.0.x"
    /// vs "0.8.x" → false. Strict major.minor match.
    static func semverMajorMinorMatches(_ a: String, _ b: String) -> Bool {
        func parts(_ s: String) -> (Int, Int)? {
            let comps = s.split(separator: ".").prefix(2).compactMap { Int($0) }
            guard comps.count == 2 else { return nil }
            return (comps[0], comps[1])
        }
        guard let pa = parts(a), let pb = parts(b) else { return false }
        return pa == pb
    }

    /// Element-wise semver comparison up to three numeric components.
    /// Returns -1 / 0 / 1 like strcmp. Missing components are treated
    /// as 0 ("1.0" == "1.0.0"). Non-numeric tails (e.g. "1.0.0a1") are
    /// stripped — we don't ship pre-release suffixes from CI.
    static func compareSemver(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".")
                .prefix(3)
                .map { component -> Int in
                    let digits = component.prefix { $0.isNumber }
                    return Int(digits) ?? 0
                }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<3 {
            let av = i < pa.count ? pa[i] : 0
            let bv = i < pb.count ? pb[i] : 0
            if av < bv { return -1 }
            if av > bv { return 1 }
        }
        return 0
    }
}
