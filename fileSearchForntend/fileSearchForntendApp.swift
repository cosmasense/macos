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
    @AppStorage("overlayHotkey") private var overlayHotkey = ""
    @AppStorage("overlayTriggerMode") private var overlayTriggerMode = "hotkey"

    var body: some Scene {
        WindowGroup {
            Group {
                if isBackendConnected {
                    ContentView()
                        .environment(appModel)
                        .environment(cosmaManager)
                        .frame(minWidth: 900, minHeight: 600)
                        .containerBackground(.ultraThinMaterial, for: .window)
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
                        }
                } else {
                    BackendConnectionView(onConnected: {
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

                // Auto-start managed backend or detect existing one
                Task {
                    // On first launch, if a backend is already running, disable managed mode
                    if cosmaManager.isManaged && !UserDefaults.standard.bool(forKey: "cosmaManagerEnabledHasBeenSet") {
                        do {
                            let _ = try await APIClient.shared.fetchStatus()
                            // Backend already running — user manages it themselves
                            cosmaManager.isManaged = false
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isBackendConnected = true
                            }
                            return
                        } catch {
                            // No backend running — keep managed mode on, proceed with install
                        }
                    }

                    guard cosmaManager.isManaged else { return }

                    await cosmaManager.startManagedBackend()
                    // Poll for backend readiness
                    for _ in 0..<30 {
                        try? await Task.sleep(for: .milliseconds(500))
                        do {
                            let _ = try await APIClient.shared.fetchStatus()
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isBackendConnected = true
                                }
                            }
                            return
                        } catch {}
                    }
                }
            }
            .onChange(of: cosmaManager.setupStage) {
                appDelegate.syncStatusBarWithCosmaManager()
            }
            .onChange(of: cosmaManager.updateStatus) {
                appDelegate.syncStatusBarWithCosmaManager()
            }
        }
        .windowStyle(.automatic)
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
}
