//
//  SparkleUpdaterController.swift
//  fileSearchForntend
//
//  Frontend auto-update via Sparkle 2.x. The Python backend has its
//  own update path (uv tool upgrade cosma against PyPI, gated by
//  BackendCompatibility.shouldAutoUpgrade). This controller handles
//  the Swift app shell only — the two channels are independent and
//  the api_version handshake remains the cross-cutting safety net
//  if a Sparkle-installed binary lands on top of an out-of-range
//  backend.
//
//  Why a wrapper instead of dropping SPUStandardUpdaterController
//  straight into SwiftUI: we need to (a) swap the appcast feed URL
//  by user-selected channel (Stable/Dev), (b) tear down CosmaManager's
//  child Python process before Sparkle relaunches the .app — without
//  that, the backend gets orphaned during the swap and the new build
//  comes up unable to bind localhost:60534 — and (c) expose status
//  to the Settings UI in the same shape as the existing backend
//  update row.
//

import Foundation
import AppKit
import Sparkle
import Observation

/// Where the user wants to receive frontend updates from. Stable is
/// the default; Dev opts into prerelease builds (any tag matching
/// `v*-dev*` or `v*-beta*` published from the same repo). The two
/// channels are served from separate appcast feeds on GitHub Pages.
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case dev

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable: return "Stable"
        case .dev: return "Dev (prerelease)"
        }
    }

    var description: String {
        switch self {
        case .stable: return "Recommended. Public releases only."
        case .dev: return "Early builds for testing. May be unstable."
        }
    }

    /// Public appcast feed for this channel. Hosted off the
    /// `cosmasense/cosmasense-appcast` GitHub Pages site so the
    /// release script can update one channel without touching the
    /// other. URLs are stable contracts — renaming a feed file
    /// orphans every installed app on that channel.
    var feedURL: URL {
        switch self {
        case .stable:
            return URL(string: "https://cosmasense.github.io/appcast/stable.xml")!
        case .dev:
            return URL(string: "https://cosmasense.github.io/appcast/dev.xml")!
        }
    }
}

/// Bridges SwiftUI ↔ Sparkle. Owns the SPUStandardUpdaterController
/// and exposes the bits the Settings UI needs to render. Lifecycle:
/// instantiated once in fileSearchForntendApp and injected into the
/// SwiftUI environment.
@MainActor
@Observable
final class SparkleUpdaterController: NSObject {
    // MARK: - Stored prefs (UserDefaults-backed)

    private static let kAutoCheckKey = "sparkleAutoCheck"
    private static let kChannelKey = "sparkleUpdateChannel"

    /// Mirror of SUEnableAutomaticChecks but exposed in our UI so the
    /// user can flip it without rebuilding. Sparkle's underlying flag
    /// is the source of truth — we proxy through it on every set.
    var automaticallyChecksForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: Self.kAutoCheckKey)
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Currently selected channel. Changing this rewrites the feed
    /// URL Sparkle reads on its next check; we also kick off a check
    /// immediately so the user sees the consequence of the toggle
    /// instead of having to wait for the next scheduled probe.
    var channel: UpdateChannel {
        didSet {
            guard channel != oldValue else { return }
            UserDefaults.standard.set(channel.rawValue, forKey: Self.kChannelKey)
            // Tell Sparkle to forget any cached "skipped version" /
            // pending decisions tied to the old feed — switching
            // channels is a fresh decision context.
            updaterController.updater.resetUpdateCycle()
            checkForUpdates(userInitiated: false)
        }
    }

    // MARK: - Status surfaced to the UI

    enum CheckState: Equatable {
        case idle
        case checking
        case upToDate
        case updateFound(version: String)
        case downloading(version: String)
        case readyToInstall(version: String)
        case failed(String)
    }

    private(set) var checkState: CheckState = .idle
    private(set) var lastCheckedAt: Date?
    private(set) var latestSeenVersion: String?

    /// Bundle short-version of the running app. Pulled from Info.plist
    /// at init so the UI can show "current vN" without each call site
    /// re-reading the bundle.
    let currentVersion: String

    /// Bundle build number — shown in the verbose status row when we
    /// need to disambiguate two builds with the same MARKETING_VERSION.
    let currentBuild: String

    // MARK: - Sparkle plumbing

    private let updaterController: SPUStandardUpdaterController

    /// Reference to the backend manager so we can stop the child
    /// Python process before Sparkle relaunches us. Set from the
    /// app entry point right after both objects are constructed.
    weak var cosmaManager: CosmaManager?

    override init() {
        // Read persisted prefs *before* constructing Sparkle so the
        // initial state we hand to the updater matches what the user
        // last picked. Defaults: auto-check on, stable channel.
        let defaults = UserDefaults.standard
        let autoCheck: Bool = {
            // .object(forKey:) lets us distinguish "user disabled it"
            // (false) from "never set, use default" (nil → true).
            if defaults.object(forKey: Self.kAutoCheckKey) == nil { return true }
            return defaults.bool(forKey: Self.kAutoCheckKey)
        }()
        let storedChannel = UpdateChannel(
            rawValue: defaults.string(forKey: Self.kChannelKey) ?? UpdateChannel.stable.rawValue
        ) ?? .stable

        self.automaticallyChecksForUpdates = autoCheck
        self.channel = storedChannel

        let info = Bundle.main.infoDictionary ?? [:]
        self.currentVersion = (info["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        self.currentBuild = (info["CFBundleVersion"] as? String) ?? "0"

        // startingUpdater: false → don't kick the first scheduled
        // check during init. We start it explicitly from the app
        // entry point once CosmaManager has a chance to spin up;
        // that avoids racing the very first launch's permission +
        // backend-bootstrap UI with a Sparkle dialog.
        let placeholderDelegate = _SparkleDelegateProxy()
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: placeholderDelegate,
            userDriverDelegate: nil
        )

        super.init()

        // Now that `self` exists, swap the proxy's target. We do this
        // dance because SPUStandardUpdaterController takes a non-nil
        // delegate at init and `self` isn't available until after
        // super.init. The proxy forwards every call to whatever it's
        // pointed at.
        placeholderDelegate.target = self

        // Apply the persisted auto-check value to Sparkle's own flag
        // (the Info.plist default is overridden by what the user last
        // toggled in Settings).
        updaterController.updater.automaticallyChecksForUpdates = autoCheck
    }

    // MARK: - Lifecycle

    /// Called once from the app entry point after the main window is
    /// up. Kicks Sparkle into its scheduled-check loop. Calling this
    /// twice is harmless — Sparkle no-ops on the second start.
    func startUpdater() {
        updaterController.startUpdater()
    }

    // MARK: - Actions invoked from the UI

    func checkForUpdates(userInitiated: Bool) {
        if userInitiated {
            // Surfaces the standard "Checking for updates…" → "You're
            // up to date" / "Update available" dialog flow.
            updaterController.checkForUpdates(nil)
        } else {
            // Background probe — no UI unless an update is found.
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    /// Whether the "Check for Updates" button should be disabled
    /// (already in flight). Mirrors `isCheckInFlight` in the backend
    /// update row for visual consistency.
    var isCheckInFlight: Bool {
        switch checkState {
        case .checking, .downloading:
            return true
        default:
            return false
        }
    }

    // MARK: - Delegate hooks (called by _SparkleDelegateProxy)

    /// Tell Sparkle which appcast to fetch. This overrides the
    /// SUFeedURL Info.plist value, so the channel switch works even
    /// without rebuilding the app.
    func feedURLString() -> String? {
        return channel.feedURL.absoluteString
    }

    /// Stop the backend child process before Sparkle replaces the
    /// .app bundle and relaunches. CosmaManager.stopServer() does the
    /// SIGTERM → 5s wait → SIGKILL dance; we let it run synchronously
    /// because Sparkle's relaunch handler is itself synchronous on
    /// the main thread. The inline 5s budget matches the existing
    /// backend-shutdown contract documented in backend_shutdown.md.
    func updaterWillRelaunch() {
        cosmaManager?.stopServer()
    }

    // MARK: - State updates

    func setState(_ state: CheckState) {
        self.checkState = state
        self.lastCheckedAt = Date()
        // Pin the seen version so the UI can show "v1.2.3 available"
        // even after the user dismisses the prompt and the state
        // moves on. Cleared back to nil only when we move to .upToDate.
        switch state {
        case let .updateFound(v),
             let .downloading(v),
             let .readyToInstall(v):
            self.latestSeenVersion = v
        case .upToDate:
            self.latestSeenVersion = nil
        case .idle, .checking, .failed:
            break
        }
    }
}

/// Sparkle's delegate API is @objc-style and most of its callbacks
/// are documented as being delivered on the main thread, but
/// `feedURLString(for:)` can be called from a background thread
/// during the initial appcast fetch. So we keep the proxy itself
/// nonisolated and hop via DispatchQueue.main for any work that
/// touches the @MainActor-isolated controller.
///
/// Why a separate proxy at all: SPUStandardUpdaterController requires
/// a delegate at init time, but `self` isn't usable as the delegate
/// until super.init has returned. The proxy holds a weak target that
/// gets pointed at the controller after super.init.
private final class _SparkleDelegateProxy: NSObject, SPUUpdaterDelegate {
    weak var target: SparkleUpdaterController?

    func feedURLString(for updater: SPUUpdater) -> String? {
        // Synchronous return — must not hop. Read UserDefaults
        // directly (thread-safe per Apple docs) so we don't risk
        // a deadlock waiting for the main actor when called from
        // Sparkle's background queue.
        let raw = UserDefaults.standard.string(forKey: "sparkleUpdateChannel")
            ?? UpdateChannel.stable.rawValue
        let channel = UpdateChannel(rawValue: raw) ?? .stable
        return channel.feedURL.absoluteString
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // Last beat before the .app gets swapped. Sparkle delivers
        // this on the main thread, but we use DispatchQueue.main.sync
        // (with a same-thread guard) so the backend shutdown actually
        // completes before this delegate returns and Sparkle proceeds
        // with the relaunch.
        runOnMainSync { [weak target] in
            target?.updaterWillRelaunch()
        }
    }

    // MARK: - Status reporting (for the Settings UI)

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let v = item.displayVersionString
        DispatchQueue.main.async { [weak target] in
            target?.setState(.updateFound(version: v))
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async { [weak target] in
            target?.setState(.upToDate)
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let msg = error.localizedDescription
        DispatchQueue.main.async { [weak target] in
            target?.setState(.failed(msg))
        }
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        let v = item.displayVersionString
        DispatchQueue.main.async { [weak target] in
            target?.setState(.downloading(version: v))
        }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let v = item.displayVersionString
        DispatchQueue.main.async { [weak target] in
            target?.setState(.readyToInstall(version: v))
        }
    }

    /// Run `work` on the main thread, synchronously. If we're already
    /// on main, call inline (DispatchQueue.main.sync from main thread
    /// deadlocks). Used only for the relaunch hook where we need to
    /// guarantee work completes before returning to Sparkle.
    private func runOnMainSync(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}
