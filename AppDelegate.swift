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
    /// The shutdown progress window shown during backend teardown.
    private var shutdownWindow: NSWindow?
    /// The quit confirmation window (non-modal so Cmd+Q still works).
    private var quitConfirmationWindow: NSWindow?

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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.title = ""
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        shutdownWindow = window
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Always try to surface the main search window on dock/icon reopen,
        // even if Settings happens to be visible. Previously, if the user
        // had Settings open when they quit (or closed the main window and
        // left Settings as the front window), clicking the dock icon would
        // restore only Settings and leave the user with no way to reach the
        // search UI. Finding and surfacing the existing main window here
        // covers that case without creating a duplicate.
        if surfaceHiddenMainWindow() { return false }

        // Genuinely no main window exists — let SwiftUI build one. Returning
        // true is still safe when Settings is open because SwiftUI only
        // recreates the main WindowGroup window, not the Settings scene.
        return true
    }

    /// Bring an existing (possibly hidden) main window back to front.
    /// Returns true only if a window actually became visible — otherwise
    /// the caller lets SwiftUI create a fresh one. Previously we returned
    /// true whenever a candidate NSWindow was found in NSApp.windows, even
    /// if the window had already been released/destroyed by SwiftUI; in
    /// that case ``makeKeyAndOrderFront`` silently failed and the dock
    /// icon clicked to nothing.
    @discardableResult
    private func surfaceHiddenMainWindow() -> Bool {
        let candidates = NSApp.windows.filter {
            $0.contentView != nil && $0.level != .floating && $0.title != "Settings"
        }
        guard !candidates.isEmpty else { return false }
        NSApp.activate(ignoringOtherApps: true)
        // Prefer an already-visible candidate if there is one — avoids
        // raising a stale hidden window over a live one.
        let window = candidates.first(where: \.isVisible) ?? candidates[0]
        window.makeKeyAndOrderFront(nil)
        // Match showMainWindow: surface the window without stealing focus
        // into the search field.
        window.makeFirstResponder(nil)
        // Verify the window is actually on screen. If SwiftUI destroyed the
        // backing window (Cmd+W on a single-window WindowGroup can leave a
        // zombie entry in NSApp.windows that can't be re-shown), report
        // failure so the caller lets SwiftUI build a fresh window.
        return window.isVisible
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
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: {
            $0.contentView != nil && $0.level != .floating && $0.title != "Settings"
        }) {
            window.makeKeyAndOrderFront(nil)
            // Don't auto-focus the search field when the window surfaces.
            // Users should click the field to start typing — SwiftUI's
            // TextField otherwise grabs first responder as the only
            // focusable control.
            window.makeFirstResponder(nil)
            // If Settings is also visible, push it behind the main window.
            // Without this, the overlay's enlarge button (and dock reopen)
            // could surface main but leave Settings on top — the user sees
            // the settings page and loses access to search.
            if let settings = NSApp.windows.first(where: {
                $0.isVisible && $0.title == "Settings"
            }) {
                settings.order(.below, relativeTo: window.windowNumber)
            }
        }
    }

    // MARK: - CosmaManager Sync

    func syncStatusBarWithCosmaManager() {
        guard let cm = cosmaManager, let sbc = statusBarController else { return }
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
            let mode = AppVisibilityMode(rawValue: rawValue) ?? .dockOnly
            print("🔍 Getting visibility mode: \(mode.rawValue)")
            return mode
        }
        set {
            print("⚙️ Setting visibility mode to: \(newValue.rawValue)")
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.visibilityModeKey)
            applyVisibilityMode(newValue)
        }
    }

    func applyVisibilityMode(_ mode: AppVisibilityMode) {
        print("🔄 applyVisibilityMode() called with: \(mode.rawValue)")
        print("   showInMenuBar: \(mode.showInMenuBar), showInDock: \(mode.showInDock)")

        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyVisibilityMode(mode)
            }
            return
        }

        // IMPORTANT: Set up status bar FIRST before changing dock visibility
        // This ensures the menu bar icon exists before we potentially hide from dock
        if mode.showInMenuBar || !mode.showInDock {
            // Need status bar if: explicitly requested OR hiding from dock (fallback)
            print("📍 Setting up status bar (showInMenuBar=\(mode.showInMenuBar), showInDock=\(mode.showInDock))")
            setupStatusBar()
        } else {
            print("📍 Removing status bar (not needed)")
            removeStatusBar()
        }

        // Handle dock visibility AFTER status bar is set up
        if mode.showInDock {
            print("📍 Setting activation policy to .regular (show in dock)")
            NSApp.setActivationPolicy(.regular)
        } else {
            print("📍 Setting activation policy to .accessory (hide from dock)")
            NSApp.setActivationPolicy(.accessory)
        }

        print("✅ Applied visibility mode: \(mode.rawValue)")
    }
}
