//
//  fileSearchFrontendApp.swift
//  fileSearchFrontend
//
//  Created by Ethan Pan on 10/19/25.
//

import SwiftUI
import AppKit

@main
struct fileSearchForntendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appModel = AppModel()
    @State private var coordinator = AppCoordinator()
    @State private var overlayController = QuickSearchOverlayController()
    @State private var cosmaManager = CosmaManager()
    @State private var hotkeyMonitoringEnabled = true
    @State private var isBackendConnected = false
    @State private var hasFullDiskAccess = true // optimistic, checked on appear
    @AppStorage("overlayHotkey") private var overlayHotkey = ""
    @AppStorage("overlayTriggerMode") private var overlayTriggerMode = "hotkey"
    @AppStorage("setupCompleted") private var setupCompleted = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !setupCompleted || !hasFullDiskAccess {
                    SetupWizardView {
                        setupCompleted = true
                        hasFullDiskAccess = true
                    }
                    .environment(cosmaManager)
                    // Flex-fill so the wizard's VisualEffectView background
                    // always covers the entire NSWindow contentView. A fixed
                    // .frame(width:height:) bounds the backing glass to the
                    // child's size, which lets the window's transparent edges
                    // show through as dark/blurry strips whenever the window
                    // ends up wider than the child (defaultSize is 720 but
                    // the wizard used to cap at 620).
                    .frame(minWidth: 620, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
                } else if isBackendConnected {
                    ContentView()
                        .environment(appModel)
                        .environment(cosmaManager)
                        // Same flex-fill rule: keep the previous 700x520 as
                        // a minimum but let the content grow to whatever the
                        // NSWindow is currently sized to, so we never leave
                        // transparent strips around the content.
                        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
                        .environment(\.presentQuickSearchOverlay, {
                            coordinator.showOverlay()
                        })
                        .environment(\.zoomToPopup, {
                            // Carry in-progress search state across so the
                            // overlay continues where the main window left
                            // off — text, tokens, and results. Results are
                            // copied too so the overlay opens expanded with
                            // the same hits instead of flashing a re-search.
                            appModel.popupSearchText = appModel.searchText
                            appModel.popupSearchTokens = appModel.searchTokens
                            appModel.popupSearchResults = appModel.searchResults
                            appDelegate.hideMainWindow()
                            coordinator.showOverlay()
                        })
                        .environment(\.updateQuickSearchLayout, { isExpanded, hasChrome in
                            overlayController.updateLayout(isExpanded: isExpanded, hasChrome: hasChrome)
                        })
                        .environment(\.controlHotkeyMonitoring, { enabled in
                            setHotkeyMonitoring(enabled: enabled)
                        })
                        .onChange(of: coordinator.isOverlayVisible) { _, newValue in
                            // Note: This handler is for UI-driven state changes (e.g., menu commands)
                            // The hotkey uses AppDelegate.toggleOverlay() which bypasses this
                            // to work even when the main window is closed
                            overlayController.toggle(
                                appModel: appModel,
                                visible: newValue,
                                onDismiss: {
                                    // Overlay dismiss (Esc / outside-click /
                                    // Cmd+W / hotkey re-toggle) never surfaces
                                    // main. Only the explicit expand button
                                    // (onZoomToMain) brings main back.
                                    coordinator.hideOverlay()
                                },
                                onZoomToMain: {
                                    // Symmetric to zoomToPopup: carry the
                                    // popup's in-progress search (text,
                                    // tokens, results) back to the main
                                    // window so expanding feels like moving
                                    // the same query into a bigger surface,
                                    // not a reset.
                                    appModel.searchText = appModel.popupSearchText
                                    appModel.searchTokens = appModel.popupSearchTokens
                                    appModel.searchResults = appModel.popupSearchResults
                                    coordinator.hideOverlay()
                                    appDelegate.showMainWindow()
                                }
                            )
                        }
                        .onChange(of: overlayHotkey) { _, newValue in
                            if hotkeyMonitoringEnabled && overlayTriggerMode == "hotkey" {
                                registerHotkey(newValue)
                            }
                        }
                        .onChange(of: overlayTriggerMode) { _, _ in
                            if hotkeyMonitoringEnabled {
                                registerActiveTrigger()
                            }
                        }
                        .onAppear {
                            registerActiveTrigger()
                            // Animate the window to its larger size while keeping its center point
                            recenterMainWindowToSize(NSSize(width: 700, height: 520))
                        }
                } else {
                    BackendConnectionView(onConnected: {
                        appModel.connectToBackend()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isBackendConnected = true
                        }
                    })
                    .environment(appModel)
                    .environment(cosmaManager)
                    .frame(minWidth: 720, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
                }
            }
            .preferredColorScheme(.light)
            .onAppear {
                // Store references in app delegate so they stay alive
                // Do this early so menu bar actions work even before backend connects
                appDelegate.coordinator = coordinator
                appDelegate.overlayController = overlayController
                appDelegate.appModel = appModel
                appDelegate.cosmaManager = cosmaManager

                // Check Full Disk Access before proceeding
                hasFullDiskAccess = checkFullDiskAccessPermission()
                guard hasFullDiskAccess else { return }

                // If we think we're connected but the backend isn't running
                // (e.g., window reopened after backend died), reset to setup view.
                if isBackendConnected && !cosmaManager.isRunning {
                    isBackendConnected = false
                }

                // Handle case where setupStage is already .running before
                // onChange gets registered (fast quick-attach path).
                if case .running = cosmaManager.setupStage, !isBackendConnected {
                    appModel.connectToBackend()
                    isBackendConnected = true
                    Task { await appModel.checkModelAvailability() }
                    // Safety net also fires on this branch — the fast-attach
                    // path previously skipped the bootstrap probe, which meant
                    // a user whose models got deleted stayed stuck on the
                    // main UI with search failing silently.
                    Task { await verifyBootstrapOrReopenWizard() }
                }

                // Kick off backend startup if not already running.
                // During first-run setup the wizard will trigger this itself
                // at step 3, so skip here to let the user click through.
                if setupCompleted && !cosmaManager.isRunning {
                    Task {
                        await cosmaManager.startManagedBackend()
                        await verifyBootstrapOrReopenWizard()
                    }
                }
            }
            .onChange(of: hasFullDiskAccess) { _, granted in
                guard granted else { return }
                // Full Disk Access was just granted — start backend if needed.
                if !cosmaManager.isRunning {
                    Task {
                        await cosmaManager.startManagedBackend()
                        await verifyBootstrapOrReopenWizard()
                    }
                }
            }
            .onChange(of: cosmaManager.setupStage) { _, newStage in
                appDelegate.syncStatusBarWithCosmaManager()

                // Backend came up → transition to main UI, but only if
                // bootstrap (model downloads) is actually finished. Otherwise
                // the main UI flashes up while Qwen3-VL is still downloading
                // and any search/index immediately fails. The wizard will
                // flip us into the main UI itself once bootstrapReady goes
                // true (see the bootstrapReady onChange below).
                if case .running = newStage, !isBackendConnected, cosmaManager.bootstrapReady {
                    appModel.connectToBackend()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isBackendConnected = true
                    }
                    Task { await appModel.checkModelAvailability() }
                }

                // Backend went down → go back to setup view.
                // EXCEPT during an in-process backend restart (e.g. the
                // catch-up upgrade restart): we know a relaunch is in
                // flight, so keep ContentView visible. The friendly
                // "Update downloaded — restarting backend automatically…"
                // banner already explains what's happening; tearing
                // ContentView down to BackendConnectionView for ~5s
                // would feel like a crash for no reason.
                if isBackendConnected, !cosmaManager.isInternalRestartInFlight {
                    switch newStage {
                    case .stopped, .failed:
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isBackendConnected = false
                        }
                    default:
                        break
                    }
                }
            }
            .onChange(of: cosmaManager.updateStatus) {
                appDelegate.syncStatusBarWithCosmaManager()
            }
            // Mirror bootstrap + embedder readiness onto AppModel so
            // non-View code (search/index) can gate without pulling
            // CosmaManager in. Both signals must be true: bootstrap
            // means model files are on disk; embedderReady means the
            // SentenceTransformer has actually been loaded into memory
            // and warmed. Without the embedder gate, queries submitted
            // in the cold-start window blocked the asyncio event loop
            // for 5-15s and timed out.
            .onChange(of: cosmaManager.bootstrapReady) { _, ready in
                appModel.aiReadyForSearch = ready && appModel.embedderReady
                if ready, case .running = cosmaManager.setupStage, !isBackendConnected {
                    appModel.connectToBackend()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isBackendConnected = true
                    }
                    Task { await appModel.checkModelAvailability() }
                }
            }
            .onChange(of: appModel.embedderReady) { _, ready in
                appModel.aiReadyForSearch = cosmaManager.bootstrapReady && ready
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 560)
        .commands {
            CommandMenu("Quick Search") {
                if overlayTriggerMode == "dualCommand" {
                    Button(coordinator.isOverlayVisible ? "Hide Quick Search" : "Show Quick Search (Both \u{2318} Keys)") {
                        coordinator.toggleOverlay()
                    }
                } else if let shortcut = parsedShortcut {
                    Button(coordinator.isOverlayVisible ? "Hide Quick Search" : "Show Quick Search") {
                        coordinator.toggleOverlay()
                    }
                    .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                } else {
                    Button("Set a shortcut in Settings") {}
                        .disabled(true)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appModel)
                .environment(cosmaManager)
                .environment(\.controlHotkeyMonitoring, { enabled in
                    setHotkeyMonitoring(enabled: enabled)
                })
                .preferredColorScheme(.light)
        }
    }

    /// If the backend reports any required AI component missing, flip
    /// setupCompleted back to false so the wizard reappears. Runs on every
    /// launch path (fresh start, fast attach, FDA-just-granted) because a
    /// user can delete model files out-of-band and we need to catch that
    /// *before* they try to index and hit silent parser failures.
    private func verifyBootstrapOrReopenWizard() async {
        await cosmaManager.refreshBootstrapStatus()
        if !cosmaManager.bootstrapReady {
            setupCompleted = false
        }
    }

    private var parsedShortcut: (key: KeyEquivalent, modifiers: EventModifiers)? {
        guard let key = shortcutKey(from: overlayHotkey) else { return nil }
        let modifiers = shortcutModifiers(from: overlayHotkey)
        return (key, modifiers)
    }

    private func shortcutKey(from raw: String) -> KeyEquivalent? {
        let parts = raw.split(separator: "+")
        guard let last = parts.last else { return nil }
        if last == "space" {
            return KeyEquivalent(" ")
        }
        guard let character = last.first else { return nil }
        return KeyEquivalent(character.lowercased().first ?? character)
    }

    private func shortcutModifiers(from raw: String) -> EventModifiers {
        let parts = raw.split(separator: "+").dropLast()
        var modifiers: EventModifiers = []
        for part in parts {
            switch part {
            case "command":
                modifiers.insert(.command)
            case "option":
                modifiers.insert(.option)
            case "control":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            default:
                break
            }
        }
        return modifiers
    }

    private func registerActiveTrigger() {
        appDelegate.stopHotkey()

        if overlayTriggerMode == "dualCommand" {
            appDelegate.registerDualCommandKey { [weak appDelegate] in
                Task { @MainActor in
                    appDelegate?.toggleOverlay()
                }
            }
        } else {
            registerHotkey(overlayHotkey)
        }
    }

    private func registerHotkey(_ raw: String) {
        guard !raw.isEmpty else {
            appDelegate.stopHotkey()
            return
        }

        // Register through app delegate so it stays alive
        appDelegate.registerHotkey(raw) { [weak appDelegate] in
            // Use AppDelegate's direct overlay toggle (bypasses SwiftUI onChange)
            // This ensures the overlay works even when main window is closed
            Task { @MainActor in
                appDelegate?.toggleOverlay()
            }
        }
    }

    private func setHotkeyMonitoring(enabled: Bool) {
        hotkeyMonitoringEnabled = enabled
        if enabled {
            registerActiveTrigger()
        } else {
            appDelegate.stopHotkey()
        }
    }

    /// Animates the main window to a new size while keeping the center point
    /// constant (so it grows outward instead of jumping anchored to the top-left).
    private func recenterMainWindowToSize(_ newSize: NSSize) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                return
            }
            let oldFrame = window.frame
            let oldCenter = NSPoint(x: oldFrame.midX, y: oldFrame.midY)
            let newOrigin = NSPoint(
                x: oldCenter.x - newSize.width / 2,
                y: oldCenter.y - newSize.height / 2
            )
            let newFrame = NSRect(origin: newOrigin, size: newSize)
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

}
