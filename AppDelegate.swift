//
//  AppDelegate.swift
//  fileSearchForntend
//
//  App delegate to keep global hotkey monitor alive
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // Strong reference - stays alive for app lifetime
    var hotkeyMonitor: GlobalHotkeyMonitor?
    var dualCmdMonitor: DualCommandKeyMonitor?
    var overlayController: QuickSearchOverlayController?
    var coordinator: AppCoordinator?
    var appModel: AppModel?
    var statusBarController: StatusBarController?
    var cosmaManager: CosmaManager?

    private static let visibilityModeKey = "appVisibilityMode"
    static let suppressQuitConfirmationKey = "suppressQuitConfirmation"

    /// Timestamp of last quit attempt — used for double-Cmd+Q detection.
    private var lastQuitAttemptTime: Date = .distantPast
    /// Whether a graceful shutdown is in progress (skip confirmation).
    private var isShuttingDown = false
    /// Set after teardown completes — tells applicationShouldTerminate to
    /// return .terminateNow instead of re-entering the quit dialog.
    private var readyToTerminate = false
    /// One-shot bypass for the quit confirmation dialog. Set by
    /// `CosmaManager.relaunchApp` (auto-update flow) so the user
    /// doesn't get prompted "are you sure?" when the app is already
    /// in the middle of programmatically restarting itself for an
    /// update. Cleared inside `applicationShouldTerminate` after we
    /// honor it once, so a follow-up manual Cmd+Q still gets the
    /// usual confirmation.
    static var bypassQuitConfirmationOnce: Bool = false
    /// The shutdown progress window shown during backend teardown.
    private var shutdownWindow: NSWindow?
    /// The quit confirmation window (non-modal so Cmd+Q still works).
    private var quitConfirmationWindow: NSWindow?
    /// Floating "update ready, restart now?" prompt. Surfaced once per
    /// downloaded version so the user finds out about the pending
    /// restart even if they never open Settings to see the banner.
    private var restartPromptWindow: NSWindow?
    /// The downloaded version we last asked about, so a refresh that
    /// re-fires the same status (no version change) doesn't pop the
    /// dialog twice.
    private var promptedRestartVersion: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 App delegate initialized - hotkey monitor will stay alive")

        // Force Light Mode app-wide. This pins NSApp.appearance so every
        // NSWindow (main, overlay, settings, status bar menus) renders in
        // Light regardless of the system appearance.
        NSApp.appearance = NSAppearance(named: .aqua)

        // Start the main-thread watchdog so any UI freeze gets logged
        // with timing data, instead of relying on the user noticing
        // "the app feels stuck" without anything in the log to explain
        // it. Logs land in OSLog under com.filesearch / watchdog —
        // filterable in Console.app.
        MainThreadWatchdog.shared.start()

        // Log uncaught exceptions before AppKit converts them into a silent
        // force-terminate. Without this, a view-init crash shows up as
        // "Unexpected call to terminate" with no explanation.
        NSSetUncaughtExceptionHandler { exception in
            print("💥 Uncaught exception: \(exception.name.rawValue): \(exception.reason ?? "<no reason>")")
            print("Stack:\n\(exception.callStackSymbols.joined(separator: "\n"))")
        }

        // Apply saved visibility mode
        applyVisibilityMode(currentVisibilityMode)

        // Listen for visibility mode changes from settings UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisibilityModeChanged(_:)),
            name: .visibilityModeChanged,
            object: nil
        )

        // Install signal handlers so the backend is killed even on
        // unexpected termination (SIGTERM from Activity Monitor, Cmd+Q, etc).
        installSignalHandlers()

        // Watch for any NSWindow closing — this is a belt-and-suspenders
        // backup for the binder's onDisappear policy hook. If the SwiftUI
        // path doesn't fire syncActivationPolicy (we hit one repro of
        // exactly this), the willClose observer will pick it up and drop
        // the dock dot anyway.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    /// Kill the backend on any normal termination signal.
    /// SIGKILL (-9) cannot be caught — but we handle SIGTERM / SIGINT / SIGHUP
    /// which cover Cmd+Q, Activity Monitor Quit, and parent-process death.
    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { signum in
            // Synchronous teardown — safe only for async-signal-safe operations.
            // We'll post a CFRunLoop source to do the actual cleanup on the main loop.
            AppDelegate.shouldTerminateFromSignal = signum
            // Wake the run loop so willTerminate fires
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
        signal(SIGHUP, handler)
    }

    nonisolated(unsafe) static var shouldTerminateFromSignal: Int32 = 0

    @objc private func handleVisibilityModeChanged(_ notification: Notification) {
        guard let rawValue = notification.object as? String,
              let mode = AppVisibilityMode(rawValue: rawValue) else { return }
        print("📬 Received visibility mode change notification: \(mode.rawValue)")
        applyVisibilityMode(mode)
    }

    /// Keep the app alive when the user closes the main window with the
    /// red traffic-light button. SwiftUI's default for a single
    /// `WindowGroup` is to terminate after the last window closes, but
    /// our design relies on the process surviving — the backend keeps
    /// indexing, the global hotkey stays armed, and `applicationShould-
    /// HandleReopen` / `showMainWindow()` rebuild the window on dock or
    /// menu-bar click.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] applicationWillTerminate")
        hotkeyMonitor?.stop()
        dualCmdMonitor?.stop()
        removeStatusBar()
        // Final safety net — teardown() is idempotent so calling it again
        // after performGracefulShutdown is harmless.
        cosmaManager?.teardown()
    }

    /// Central quit gate.  Decides whether to quit immediately, show a
    /// confirmation dialog, or skip because a shutdown is already in progress.
    ///
    /// Double-pressing Cmd+Q within 0.8 s always quits immediately,
    /// including while the confirmation dialog is showing.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Teardown finished — let the app exit for real.
        if readyToTerminate { return .terminateNow }

        // Teardown in progress — ignore further quit requests.
        if isShuttingDown { return .terminateCancel }

        // Signal-triggered quit (Activity Monitor, kill, etc.) — skip dialog.
        if Self.shouldTerminateFromSignal != 0 {
            dismissQuitConfirmation()
            beginGracefulShutdown()
            return .terminateCancel
        }

        // macOS log-out / restart / shutdown — never interrupt the system
        // sequence with our own confirmation dialog. AppKit wraps those
        // quits in a reason field on the current Apple event; bypass the
        // dialog and go straight to graceful shutdown so loginwindow
        // doesn't have to force-kill us.
        if isSystemShutdownOrLogout() {
            dismissQuitConfirmation()
            beginGracefulShutdown()
            return .terminateCancel
        }

        // Double Cmd+Q (< 0.8 s apart) — skip confirmation, even if
        // the confirmation window is already showing.
        let now = Date()
        let interval = now.timeIntervalSince(lastQuitAttemptTime)
        lastQuitAttemptTime = now

        // One-shot bypass set by relaunchApp — restart-for-update
        // initiates a quit programmatically and shouldn't surprise the
        // user with an "are you sure?" dialog mid-flow. Consume the
        // flag so the next manual Cmd+Q still confirms.
        if Self.bypassQuitConfirmationOnce {
            Self.bypassQuitConfirmationOnce = false
            dismissQuitConfirmation()
            beginGracefulShutdown()
            return .terminateCancel
        }

        let suppressed = UserDefaults.standard.bool(forKey: Self.suppressQuitConfirmationKey)
        if suppressed || interval < 0.8 {
            dismissQuitConfirmation()
            beginGracefulShutdown()
            return .terminateCancel
        }

        // If the confirmation window is already showing, treat this
        // second Cmd+Q as the "double press" — quit immediately.
        if quitConfirmationWindow != nil {
            dismissQuitConfirmation()
            beginGracefulShutdown()
            return .terminateCancel
        }

        // Show non-modal confirmation dialog.
        showQuitConfirmation()
        return .terminateCancel
    }

    // MARK: - Quit Confirmation (Non-Modal Window)

    private func showQuitConfirmation() {
        let width: CGFloat = 370
        let height: CGFloat = 190

        let view = QuitConfirmationView(
            onQuit: { [weak self] suppress in
                if suppress {
                    UserDefaults.standard.set(true, forKey: Self.suppressQuitConfirmationKey)
                }
                self?.dismissQuitConfirmation()
                self?.beginGracefulShutdown()
            },
            onCancel: { [weak self] in
                self?.dismissQuitConfirmation()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        // Borderless + transparent background so only the SwiftUI glass
        // panel inside QuitConfirmationView is visible. Using .titled here
        // drew a second NSWindow frame behind our glass, producing a
        // double-card look (an outer rounded rectangle plus the inner
        // dialog). We still want a drop shadow so the dialog reads as
        // floating above the main window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        quitConfirmationWindow = window
    }

    private func dismissQuitConfirmation() {
        quitConfirmationWindow?.close()
        quitConfirmationWindow = nil
    }

    /// Returns true when the current quit was initiated by loginwindow as
    /// part of a logout / restart / shutdown. We detect this by inspecting
    /// the 'why?' reason on the active AppleEvent — AppKit forwards one
    /// of the kAE* reason codes on system-driven quits but not on user
    /// Cmd-Q. When true, we skip our confirmation dialog: blocking a
    /// system shutdown with a non-modal window is a bad citizen move
    /// (and loginwindow will force-kill us after its timeout anyway).
    private func isSystemShutdownOrLogout() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        // Reason code lives in either a parameter or attribute with key
        // 'why?'. Carbon constants are imported as Int but the descriptor
        // API takes AEKeyword (UInt32), so convert with fourCharCode.
        let whyKeyword = fourCharCode("why?")
        let descriptor = event.paramDescriptor(forKeyword: whyKeyword)
            ?? event.attributeDescriptor(forKeyword: whyKeyword)
        guard let descriptor else { return false }
        let reasonCode = descriptor.typeCodeValue
        // 'logo' = logout, 'rlgo' = really log out (no Cancel),
        // 'rrst' / 'rsdn' = pre-dialog restart/shutdown broadcast,
        // 'rest' / 'shut' = the actual restart/shutdown.
        switch reasonCode {
        case fourCharCode("logo"), fourCharCode("rlgo"),
             fourCharCode("rrst"), fourCharCode("rsdn"),
             fourCharCode("rest"), fourCharCode("shut"):
            return true
        default:
            return false
        }
    }

    private func fourCharCode(_ s: String) -> FourCharCode {
        precondition(s.utf8.count == 4, "fourCharCode expects a 4-byte string")
        var result: FourCharCode = 0
        for byte in s.utf8 {
            result = (result << 8) | FourCharCode(byte)
        }
        return result
    }

    // MARK: - Graceful Shutdown

    /// Close the main window, show a small shutdown window, tear down the
    /// backend, then terminate for real once the process is confirmed dead.
    private func beginGracefulShutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        // Close all app windows (main window, settings, quit dialog, etc.)
        for window in NSApp.windows where window !== shutdownWindow {
            window.close()
        }
        quitConfirmationWindow = nil

        // If backend wasn't started by us, terminate immediately.
        guard let cm = cosmaManager, cm.ownsProcess else {
            cosmaManager?.teardown()
            readyToTerminate = true
            NSApp.terminate(nil)
            return
        }

        // Show shutdown progress window
        showShutdownWindow()

        // Run teardown off the main actor so the shutdown spinner animates.
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                cm.teardown()
            }
            await MainActor.run { [weak self] in
                self?.shutdownWindow?.close()
                self?.shutdownWindow = nil
                self?.readyToTerminate = true
                NSApp.terminate(nil)
            }
        }
    }

    private func showShutdownWindow() {
        let width: CGFloat = 300
        let height: CGFloat = 120

        let hostingView = NSHostingView(rootView: ShutdownView())
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        // Borderless rather than [.titled, .fullSizeContentView]: a
        // titled-but-transparent window composites the rounded glass
        // through a 1pt rectangular GPU layer at the window edge,
        // which on Retina displays leaves a thin black stroke around
        // the corners (the "GPU rendering issue" the user noticed).
        // Borderless skips that frame entirely — same approach the
        // quit confirmation panel uses, which has no such artifact.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        shutdownWindow = window
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    // MARK: - Hotkey

    func registerHotkey(_ hotkey: String, action: @escaping () -> Void) {
        if hotkeyMonitor == nil {
            hotkeyMonitor = GlobalHotkeyMonitor()
            print("✨ Created new GlobalHotkeyMonitor in AppDelegate")
        }

        hotkeyMonitor?.update(hotkey: hotkey, action: action)
    }

    func registerDualCommandKey(action: @escaping () -> Void) {
        stopHotkey()
        if dualCmdMonitor == nil {
            dualCmdMonitor = DualCommandKeyMonitor()
            print("Created new DualCommandKeyMonitor in AppDelegate")
        }
        dualCmdMonitor?.start(action: action)
    }

    func stopHotkey() {
        hotkeyMonitor?.stop()
        dualCmdMonitor?.stop()
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        print("🔧 setupStatusBar() called, current controller: \(statusBarController != nil ? "exists" : "nil")")

        // Always ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setupStatusBar()
            }
            return
        }

        guard statusBarController == nil else {
            print("⚠️ Status bar controller already exists, skipping setup")
            return
        }

        statusBarController = StatusBarController()
        statusBarController?.onShowMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        statusBarController?.onShowQuickSearch = { [weak self] in
            // Use direct overlay presentation (works even when main window is closed)
            self?.toggleOverlay()
        }
        statusBarController?.onShowSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        statusBarController?.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        statusBarController?.onStartBackend = { [weak self] in
            guard let cm = self?.cosmaManager else { return }
            Task { @MainActor in
                await cm.startManagedBackend()
            }
        }
        statusBarController?.onStopBackend = { [weak self] in
            self?.cosmaManager?.stopServer()
        }
        statusBarController?.onRestartBackend = { [weak self] in
            guard let cm = self?.cosmaManager else { return }
            Task { @MainActor in
                await cm.restartServer()
            }
        }
        statusBarController?.onCheckForUpdates = { [weak self] in
            guard let cm = self?.cosmaManager else { return }
            Task { @MainActor in
                await cm.checkForUpdates()
            }
        }
        statusBarController?.setup()
        syncStatusBarWithCosmaManager()
        print("✅ Status bar controller initialized and setup called")
    }

    func removeStatusBar() {
        print("🔧 removeStatusBar() called")
        statusBarController?.remove()
        statusBarController = nil
        print("🛑 Status bar removed")
    }

    /// Surface the main SwiftUI window. Safe to call when already visible.
    /// Used by the dock-icon reopen handler, the status-bar "Show Cosma
    /// Sense" item, and the overlay "expand to main" button — all three
    /// have to work regardless of which state the main window is in
    /// (hidden, miniaturized, Cmd+W zombie, behind Settings, never opened
    /// yet). Steps:
    ///   1. Unhide + activate the app so AppKit can actually show a window.
    ///   2. Surface any existing main NSWindow we can find.
    ///   3. If no surfaceable window exists (or `makeKeyAndOrderFront`
    ///      didn't actually flip `isVisible` — happens with Cmd+W zombies),
    ///      ask SwiftUI to (re)open the WindowGroup via its captured
    ///      `openWindow(id: "main")` action. SwiftUI focuses an existing
    ///      window for that id or creates a new one, so this is safe to
    ///      call unconditionally as a fallback.
    func showMainWindow() {
        let mounted = coordinator?.isMainWindowMounted ?? false
        // Pre-upgrade away from .accessory before invoking openWindow.
        // .accessory apps don't show new SwiftUI windows reliably and
        // have no dock dot / app menu entries. Switching to .regular
        // first lets openWindow present a usable window and gives the
        // user the Settings/Quit menu while a window is on screen.
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate(ignoringOtherApps: true)

        // Path A: SwiftUI view tree is mounted → a real main NSWindow
        // exists; surface it.
        if mounted, surfaceMainWindow() { return }

        // Path B: torn down (Cmd+W) or surface failed → ask SwiftUI
        // to (re)create the window. onAppear flips mounted true again.
        coordinator?.openMainWindowAction?()
    }

    /// Locate and raise the real main NSWindow. Caller must verify
    /// `coordinator.isMainWindowMounted == true` before calling — when
    /// the SwiftUI view tree is torn down everything in NSApp.windows
    /// is some flavor of empty placeholder shell, so this routine has
    /// no way to tell them apart and shouldn't be trusted in that
    /// state.
    @discardableResult
    private func surfaceMainWindow() -> Bool {
        let candidates = NSApp.windows.filter { window in
            // level=normal skips overlay panel / status-bar host /
            // SwiftUI level=25 ghosts. Subviews-non-empty rejects
            // empty shells (post-Cmd+W). Toolbar==nil rejects the
            // SwiftUI Settings scene (hiddenTitleBar main window
            // has no toolbar).
            guard window.level == .normal else { return false }
            guard let cv = window.contentView, !cv.subviews.isEmpty else { return false }
            if window.toolbar != nil { return false }
            return true
        }
        guard !candidates.isEmpty else { return false }
        let window = candidates.first(where: \.isVisible)
            ?? candidates.first(where: \.isMiniaturized)
            ?? candidates[0]
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        return window.isVisible
    }

    // MARK: - CosmaManager Sync

    func syncStatusBarWithCosmaManager() {
        guard let cm = cosmaManager else { return }

        // Surface a "Update Ready" popup the first time we land on
        // .downloadedPendingRestart for a given downloaded version.
        // The Settings banner alone wasn't catching users who never
        // opened Settings.
        if case .downloadedPendingRestart(let running, let downloaded) = cm.updateStatus {
            if promptedRestartVersion != downloaded {
                promptedRestartVersion = downloaded
                showRestartPrompt(running: running, downloaded: downloaded)
            }
        } else if case .upToDate = cm.updateStatus {
            // After dismissUpdate the running/downloaded versions match
            // and we should be ready to surface the next pending one
            // (whenever it lands) without comparing to the stale value.
            promptedRestartVersion = nil
        }

        guard let sbc = statusBarController else { return }
        sbc.isManagedMode = cm.isManaged
        sbc.backendIsRunning = cm.isRunning
        sbc.ownsProcess = cm.ownsProcess
        sbc.backendStatusText = cm.stageDescription

        switch cm.updateStatus {
        case .downloadedPendingRestart(_, let downloaded):
            sbc.updateAvailableText = "Restart to apply v\(downloaded)"
        case .downloading(_, let target):
            sbc.updateAvailableText = "Downloading v\(target)…"
        default:
            sbc.updateAvailableText = nil
        }
    }

    // MARK: - Restart-for-update Prompt

    private func showRestartPrompt(running: String, downloaded: String) {
        // If a prompt is already on screen for this version, leave it
        // be — the status sync handler can fire repeatedly.
        if restartPromptWindow != nil { return }

        let width: CGFloat = 380
        let height: CGFloat = 220

        let view = RestartForUpdatePromptView(
            runningVersion: running,
            downloadedVersion: downloaded,
            onRestart: { [weak self] in
                self?.dismissRestartPrompt()
                self?.cosmaManager?.relaunchApp()
            },
            onLater: { [weak self] in
                self?.dismissRestartPrompt()
                // User said "Later" — keep the Settings banner around
                // (don't call dismissUpdate, that suppresses *all*
                // future surfacing for this version). The popup just
                // doesn't reappear until a newer version lands.
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        restartPromptWindow = window
    }

    private func dismissRestartPrompt() {
        restartPromptWindow?.close()
        restartPromptWindow = nil
    }

    // MARK: - Overlay Management (Direct Control)

    /// Toggle the quick search overlay - called directly from hotkey
    /// This bypasses SwiftUI's onChange which doesn't work when main window is closed
    func toggleOverlay() {
        guard let coordinator = coordinator else {
            print("⚠️ toggleOverlay: coordinator is nil")
            return
        }

        // Toggle the state
        let willShow = !coordinator.isOverlayVisible
        coordinator.isOverlayVisible = willShow

        // Directly present or dismiss the overlay
        if willShow {
            presentOverlay()
        } else {
            dismissOverlay()
        }
    }

    /// Present the overlay directly (called when hotkey shows overlay)
    func presentOverlay() {
        guard let overlayController = overlayController,
              let appModel = appModel,
              let coordinator = coordinator else {
            print("⚠️ presentOverlay: missing required references")
            return
        }

        print("🎯 presentOverlay called directly from AppDelegate")
        hideMainWindow()
        overlayController.present(
            appModel: appModel,
            onDismiss: { [weak coordinator] in
                // Dismiss paths (Esc / outside-click / Cmd+W / hotkey
                // re-toggle) never surface main. Only onZoomToMain does.
                coordinator?.isOverlayVisible = false
            },
            onZoomToMain: { [weak self, weak coordinator] in
                coordinator?.isOverlayVisible = false
                self?.showMainWindow()
            }
        )
    }

    /// Hide the main SwiftUI window (preserving state) so the overlay takes over.
    /// Overlay dismiss paths never re-surface main — only the explicit expand
    /// button (onZoomToMain) brings it back via `showMainWindow()`.
    func hideMainWindow() {
        for window in NSApp.windows where window.isVisible && window.contentView != nil {
            if window.level == .floating { continue }
            if window.title == "Settings" { continue }
            window.orderOut(nil)
        }
    }

    /// Dismiss the overlay directly
    func dismissOverlay() {
        overlayController?.dismiss()
    }

    // MARK: - Visibility Mode

    var currentVisibilityMode: AppVisibilityMode {
        get {
            let rawValue = UserDefaults.standard.string(forKey: Self.visibilityModeKey) ?? AppVisibilityMode.dockOnly.rawValue
            return AppVisibilityMode(rawValue: rawValue) ?? .dockOnly
        }
        set {
            FELog.emit(FELog.lifecycle, "⚙️ visibility mode → \(newValue.rawValue)")
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.visibilityModeKey)
            applyVisibilityMode(newValue)
        }
    }

    func applyVisibilityMode(_ mode: AppVisibilityMode) {
        FELog.emit(FELog.lifecycle, "🔄 applyVisibilityMode → \(mode.rawValue) (dock=\(mode.showInDock) menuBar=\(mode.showInMenuBar))")

        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyVisibilityMode(mode)
            }
            return
        }

        // Set up status bar BEFORE changing dock visibility so the
        // menu bar icon exists before we potentially hide from dock.
        if mode.showInMenuBar || !mode.showInDock {
            setupStatusBar()
        } else {
            removeStatusBar()
        }

        // Activation policy is resolved by syncActivationPolicy so
        // .menuBarOnly / .dockOnly can toggle .regular ↔ .accessory
        // based on window visibility (see contract docs there).
        syncActivationPolicy()
    }

    // MARK: - Settings (programmatic open)

    /// Open the SwiftUI Settings scene from AppKit. Used by the status
    /// bar menu, which is the only Settings entry-point while the app
    /// is in pure .accessory state (no app menu, so Cmd+, is gone).
    ///
    /// Pre-upgrades activation policy off .accessory so the Settings
    /// window can actually present (same teardown trap as the main
    /// window). Then sends the modern `showSettingsWindow:` action
    /// (macOS 13+) — there's no public API; the selector is delivered
    /// through the responder chain and the SwiftUI Settings scene
    /// installs a handler for it.
    func openSettingsWindow() {
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        // macOS 13+: showSettingsWindow:. macOS 12 and earlier used
        // showPreferencesWindow: — we try both so the user isn't left
        // with a no-op if they're on an older system.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Activation Policy

    /// Choose the right activation policy for the current visibility
    /// mode and window state, and apply it iff it changed.
    ///
    /// Contract per mode:
    /// * `.both`: always `.regular`. Status bar always present, dock
    ///   dot always present. The "loud" mode for users who want both
    ///   entry-points visible at all times.
    /// * `.dockOnly`: dynamic. Dock dot follows window visibility — on
    ///   when a window is open, off when the last one closes. No
    ///   status-bar fallback by design (the user picked "Dock Only").
    ///   To re-open when no window is visible: relaunch from Spotlight
    ///   / Finder (which fires applicationShouldHandleReopen).
    /// * `.menuBarOnly`: dynamic. Dock dot follows window visibility,
    ///   like `.dockOnly`. Status bar item always present so the user
    ///   can re-open the window without leaving the app.
    ///
    /// Side-effect: as `.accessory`, SwiftUI's openWindow(id:) silently
    /// fails (the WindowGroup mounts the window and immediately tears
    /// it down on the same runloop turn). showMainWindow pre-upgrades
    /// before calling openWindow so the new window actually sticks.
    func syncActivationPolicy() {
        let mode = currentVisibilityMode
        let target: NSApplication.ActivationPolicy
        switch mode {
        case .both:
            target = .regular
        case .dockOnly, .menuBarOnly:
            target = hasVisibleUserFacingWindow() ? .regular : .accessory
        }
        let current = NSApp.activationPolicy()
        if current != target {
            FELog.emit(FELog.policy, "activation policy \(current.rawValue) → \(target.rawValue) (mode=\(mode.rawValue))")
            NSApp.setActivationPolicy(target)
        }
    }

    /// True if the main WindowGroup's view tree is currently mounted.
    /// Strictly uses the binder's `isMainWindowMounted` flag — we don't
    /// fall back to walking `NSApp.windows`, because:
    ///   * at the moment the user clicks the close button, the closing
    ///     NSWindow's `isVisible` is still true on this runloop turn,
    ///     so a fallback scan would falsely report a window present
    ///     and we'd never drop to .accessory; the dock dot would stay.
    ///   * SwiftUI also leaves leftover shell NSWindows around that
    ///     pass the level=normal + has-subviews tests but aren't real
    ///     user-facing surfaces.
    /// Settings is intentionally NOT counted here. If the user has
    /// Settings open with the main window closed, dropping to
    /// .accessory is fine — Settings stays visible, and the user can
    /// still interact with it; only the app menu and dock dot go away
    /// (which is the contract of "no main window open").
    ///
    /// Coordinator can be nil before its first wire-up; when nil we
    /// optimistically assume the main window is mounted, because
    /// SwiftUI shows the main WindowGroup window on launch by default.
    /// This avoids dropping to .accessory in the brief window before
    /// the binder has run its onAppear.
    private func hasVisibleUserFacingWindow() -> Bool {
        return coordinator?.isMainWindowMounted ?? true
    }

    /// Called from OpenMainWindowBinder when the main window's view
    /// tree mounts or unmounts. Now that hasVisibleUserFacingWindow
    /// strictly trusts the binder's `isMainWindowMounted` flag (no
    /// NSApp.windows scan), we don't need to defer a runloop tick to
    /// wait for window state to settle — call sync so the policy
    /// flip happens before the user can perceive a delay.
    @MainActor
    func notifyMainWindowMountChange(reason: String) {
        syncActivationPolicy()
    }

    /// NSWindow.willCloseNotification observer — installed in
    /// applicationDidFinishLaunching as a belt-and-suspenders backup
    /// in case the SwiftUI binder's onDisappear path is unreliable
    /// (we saw at least one log where it fired but the AppDelegate
    /// hop never ran). Schedules a sync 200ms later so the closing
    /// window has fully orderedOut before we re-check policy.
    @objc func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Ignore the floating overlay panel and the level=25 ghost
        // placeholder — neither closing affects activation policy.
        guard window.level == .normal else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.syncActivationPolicy()
        }
    }
}
