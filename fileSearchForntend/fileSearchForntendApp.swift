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

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasFullDiskAccess {
                    FullDiskAccessGateView {
                        hasFullDiskAccess = true
                    }
                    .frame(minWidth: 500, minHeight: 400)
                } else if isBackendConnected {
                    ContentView()
                        .environment(appModel)
                        .environment(cosmaManager)
                        .frame(minWidth: 900, minHeight: 600)
                        .containerBackground(.clear, for: .window)
                        .environment(\.presentQuickSearchOverlay, {
                            coordinator.showOverlay()
                        })
                        .environment(\.updateQuickSearchLayout, { isExpanded in
                            overlayController.updateLayout(isExpanded: isExpanded)
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
                                    coordinator.hideOverlay()
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
                            recenterMainWindowToSize(NSSize(width: 900, height: 600))
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
                    .frame(minWidth: 500, minHeight: 400)
                }
            }
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
                }

                // Kick off backend startup if not already running.
                if !cosmaManager.isRunning {
                    Task {
                        await cosmaManager.startManagedBackend()
                    }
                }
            }
            .onChange(of: hasFullDiskAccess) { _, granted in
                guard granted else { return }
                // Full Disk Access was just granted — start backend if needed.
                if !cosmaManager.isRunning {
                    Task {
                        await cosmaManager.startManagedBackend()
                    }
                }
            }
            .onChange(of: cosmaManager.setupStage) { _, newStage in
                appDelegate.syncStatusBarWithCosmaManager()

                // Backend came up → transition to main UI.
                if case .running = newStage, !isBackendConnected {
                    appModel.connectToBackend()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isBackendConnected = true
                    }
                    Task { await appModel.checkModelAvailability() }
                }

                // Backend went down → go back to setup view.
                if isBackendConnected {
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
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: isBackendConnected ? 900 : 500, height: isBackendConnected ? 600 : 400)
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
                .frame(minWidth: 550, minHeight: 500)
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
