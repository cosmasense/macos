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
    @AppStorage("overlayHotkey") private var overlayHotkey = ""

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 600)
                .containerBackground(.ultraThinMaterial, for: .window)
                .floatingPanel(
                    isPresented: $isOverlayVisible,
                    contentRect: panelRect,
                    content: {
                        SearchOverlayPanel(onDismiss: { isOverlayVisible = false })
                    }
                )
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandMenu("Quick Search") {
                if let shortcut = validShortcut {
                    Button(isOverlayVisible ? "Hide Quick Search" : "Show Quick Search") {
                        toggleOverlay()
                    }
                    .keyboardShortcut(shortcut, modifiers: [])
                } else {
                    Button("Set a shortcut in Settings") {}
                        .disabled(true)
                }
            }
        }
    }

    private var panelRect: CGRect {
        let screen = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
        let panelWidth: CGFloat = 720
        let panelHeight: CGFloat = 110
        return CGRect(
            x: screen.midX - (panelWidth / 2),
            y: screen.minY + 100,
            width: panelWidth,
            height: panelHeight
        )
    }

    private var validShortcut: KeyEquivalent? {
        guard let first = overlayHotkey.lowercased().first else { return nil }
        return KeyEquivalent(first)
    }

    private func toggleOverlay() {
        if isOverlayVisible {
            isOverlayVisible = false
        } else {
            isOverlayVisible = true
        }
    }
}
