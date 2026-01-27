//
//  AppDelegate.swift
//  fileSearchForntend
//
//  App delegate to keep global hotkey monitor alive
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    // Strong reference - stays alive for app lifetime
    var hotkeyMonitor: GlobalHotkeyMonitor?
    var overlayController: QuickSearchOverlayController?
    var coordinator: AppCoordinator?
    var appModel: AppModel?
    var statusBarController: StatusBarController?

    private static let visibilityModeKey = "appVisibilityMode"

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 App delegate initialized - hotkey monitor will stay alive")

        // Apply saved visibility mode
        applyVisibilityMode(currentVisibilityMode)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When clicking dock icon, show main window if no windows visible
        if !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - Hotkey

    func registerHotkey(_ hotkey: String, action: @escaping () -> Void) {
        if hotkeyMonitor == nil {
            hotkeyMonitor = GlobalHotkeyMonitor()
            print("✨ Created new GlobalHotkeyMonitor in AppDelegate")
        }

        hotkeyMonitor?.update(hotkey: hotkey, action: action)
    }

    func stopHotkey() {
        hotkeyMonitor?.stop()
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
        statusBarController?.setup()
        print("✅ Status bar controller initialized and setup called")
    }

    func removeStatusBar() {
        print("🔧 removeStatusBar() called")
        statusBarController?.remove()
        statusBarController = nil
        print("🛑 Status bar removed")
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Find and show main window
        if let window = NSApp.windows.first(where: { $0.title == "Search Files" || $0.contentView != nil }) {
            window.makeKeyAndOrderFront(nil)
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
        overlayController.present(appModel: appModel, onDismiss: { [weak coordinator] in
            // Keep state in sync when dismissed via X button or clicking outside
            coordinator?.isOverlayVisible = false
        })
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
