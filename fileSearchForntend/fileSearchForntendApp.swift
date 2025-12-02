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
    @State private var isOverlayVisible = false
    @State private var overlayController = QuickSearchOverlayController()
    @State private var hotkeyMonitor = GlobalHotkeyMonitor()
    @AppStorage("overlayHotkey") private var overlayHotkey = ""

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 600)
                .containerBackground(.ultraThinMaterial, for: .window)
                .environment(\.presentQuickSearchOverlay, { showOverlay() })
                .onChange(of: isOverlayVisible) { _, newValue in
                    overlayController.toggle(
                        appModel: appModel,
                        visible: newValue,
                        onDismiss: { isOverlayVisible = false }
                    )
                }
                .onChange(of: overlayHotkey) { _, newValue in
                    registerHotkey(newValue)
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
                    Button(isOverlayVisible ? "Hide Quick Search" : "Show Quick Search") {
                        toggleOverlay()
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

    private func toggleOverlay() {
        isOverlayVisible.toggle()
    }

    private func showOverlay() {
        if !isOverlayVisible {
            isOverlayVisible = true
        }
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
        hotkeyMonitor.update(hotkey: raw) {
            toggleOverlay()
        }
    }
}
