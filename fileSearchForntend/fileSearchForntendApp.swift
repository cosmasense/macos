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
    @State private var hotkeyMonitoringEnabled = true
    @State private var isBackendConnected = false
    @AppStorage("overlayHotkey") private var overlayHotkey = ""

    var body: some Scene {
        WindowGroup {
            Group {
                if isBackendConnected {
                    ContentView()
                        .environment(appModel)
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
                            overlayController.toggle(
                                appModel: appModel,
                                visible: newValue,
                                onDismiss: {
                                    coordinator.hideOverlay()
                                }
                            )
                        }
                        .onChange(of: overlayHotkey) { _, newValue in
                            if hotkeyMonitoringEnabled {
                                registerHotkey(newValue)
                            }
                        }
                        .onAppear {
                            // Register hotkey when main view appears
                            registerHotkey(overlayHotkey)
                        }
                } else {
                    BackendConnectionView(onConnected: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isBackendConnected = true
                        }
                    })
                    .environment(appModel)
                    .frame(minWidth: 500, minHeight: 400)
                }
            }
            .onAppear {
                // Store references in app delegate so they stay alive
                // Do this early so menu bar actions work even before backend connects
                appDelegate.coordinator = coordinator
                appDelegate.overlayController = overlayController
                appDelegate.appModel = appModel
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: isBackendConnected ? 900 : 500, height: isBackendConnected ? 600 : 400)
        .commands {
            CommandMenu("Quick Search") {
                if let shortcut = parsedShortcut {
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

    private func registerHotkey(_ raw: String) {
        guard !raw.isEmpty else {
            appDelegate.stopHotkey()
            return
        }
        
        print("Registering hotkey: \(raw)")
        
        // Register through app delegate so it stays alive
        appDelegate.registerHotkey(raw) {
            // This executes on main thread
            print("🔥 Hotkey triggered!")

            // Access coordinator from app delegate (guaranteed to be alive)
            Task { @MainActor in
                if let coordinator = self.appDelegate.coordinator {
                    coordinator.toggleOverlay()
                }
            }
        }
    }

    private func setHotkeyMonitoring(enabled: Bool) {
        hotkeyMonitoringEnabled = enabled
        if enabled {
            registerHotkey(overlayHotkey)
        } else {
            appDelegate.stopHotkey()
        }
    }
}
