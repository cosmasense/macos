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
    @State private var appModel = AppModel()
    @State private var coordinator = AppCoordinator()
    @State private var overlayController = QuickSearchOverlayController()
    @State private var hotkeyMonitor = GlobalHotkeyMonitor()
    @State private var hotkeyMonitoringEnabled = true
    @AppStorage("overlayHotkey") private var overlayHotkey = ""

    var body: some Scene {
        WindowGroup {
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
                    registerHotkey(overlayHotkey)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
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
            hotkeyMonitor.stop()
            return
        }
        
        // Register with a weak reference to the coordinator
        hotkeyMonitor.update(hotkey: raw) { [weak coordinator] in
            guard let coordinator = coordinator else { return }
            // This closure is already executed on main thread by GlobalHotkeyMonitor
            // Toggle the overlay - bring app to front when triggered globally
            NSApp.activate(ignoringOtherApps: true)
            coordinator.toggleOverlay()
        }
    }

    private func setHotkeyMonitoring(enabled: Bool) {
        hotkeyMonitoringEnabled = enabled
        if enabled {
            registerHotkey(overlayHotkey)
        } else {
            hotkeyMonitor.stop()
        }
    }
}
