//
//  FloatingPanel.swift
//  fileSearchForntend
//
//  Floating panel implementation for macOS
//

import SwiftUI
import AppKit

// MARK: - Floating Panel Window

class FloatingPanel: NSPanel {
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType = .buffered, defer flag: Bool = false) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: backing,
            defer: flag
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - View Modifier

struct FloatingPanelModifier<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let contentRect: CGRect
    let content: () -> PanelContent

    @State private var panel: FloatingPanel?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { oldValue, newValue in
                if newValue {
                    presentPanel()
                } else {
                    dismissPanel()
                }
            }
    }

    private func presentPanel() {
        if panel == nil {
            let newPanel = FloatingPanel(contentRect: contentRect)

            let hostingView = NSHostingView(rootView: self.content())
            newPanel.contentView = hostingView

            panel = newPanel
        }

        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    private func dismissPanel() {
        panel?.close()
        panel = nil
    }
}

extension View {
    func floatingPanel<Content: View>(
        isPresented: Binding<Bool>,
        contentRect: CGRect,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(FloatingPanelModifier(
            isPresented: isPresented,
            contentRect: contentRect,
            content: content
        ))
    }
}
