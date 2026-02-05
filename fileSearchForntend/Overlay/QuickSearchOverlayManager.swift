//
//  QuickSearchOverlayManager.swift
//  fileSearchForntend
//
//  Manages the lifecycle of the floating quick-search panel.
//

import SwiftUI
import AppKit

// MARK: - Panel Wrapper

private final class NonActivatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
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
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

@MainActor
final class QuickSearchOverlayController: NSObject, NSWindowDelegate {
    private let collapsedHeight: CGFloat = 140
    private let expandedHeight: CGFloat = 380
    private let panelWidth: CGFloat = 940
    private let bottomOffset: CGFloat = 120

    private var panel: NonActivatingPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var dismissalCallback: (() -> Void)?

    func present(appModel: AppModel, onDismiss: @escaping () -> Void) {
        dismissalCallback = onDismiss

        if panel == nil {
            let contentView = QuickSearchOverlayView(onClose: { [weak self] in
                self?.dismiss()
            })
            .environment(appModel)
            .environment(\.updateQuickSearchLayout, { [weak self] isExpanded in
                self?.updateLayout(isExpanded: isExpanded)
            })

            let host = NSHostingController(rootView: AnyView(contentView))
            let newPanel = NonActivatingPanel(contentRect: defaultFrame())
            newPanel.contentViewController = host
            newPanel.delegate = self
            newPanel.isMovable = false

            hostingController = host
            self.panel = newPanel
        }

        guard let panel = panel else {
            return
        }

        // Ensure the app is brought to the foreground
        // This is critical when the app is running in background with no main window

        // Force the app to activate even if it's in accessory mode
        NSApp.activate(ignoringOtherApps: true)

        // Use a small delay to ensure activation takes effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self = self, let panel = self.panel else { return }

            // Bring panel to front regardless of app state
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)

            // Force first responder after a brief delay to ensure window is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                panel.makeFirstResponder(panel.contentView)
            }
        }
    }

    func dismiss() {
        guard panel != nil else {
            return
        }
        panel?.close()
        // Note: cleanupAfterClose will be called via windowWillClose delegate
    }

    func toggle(appModel: AppModel, visible: Bool, onDismiss: @escaping () -> Void) {
        if visible {
            present(appModel: appModel, onDismiss: onDismiss)
        } else {
            dismiss()
        }
    }

    func updateLayout(isExpanded: Bool) {
        guard let panel else { return }
        let height = isExpanded ? expandedHeight : collapsedHeight

        // Calculate new frame keeping the bottom anchored
        let currentFrame = panel.frame
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y, // Keep bottom at same position
            width: currentFrame.width,
            height: height
        )

        panel.setFrame(newFrame, display: true, animate: true)
    }

    func windowWillClose(_ notification: Notification) {
        cleanupAfterClose()
    }

    // MARK: - Helpers

    private func cleanupAfterClose() {
        panel = nil
        hostingController = nil
        let callback = dismissalCallback
        dismissalCallback = nil
        callback?()
    }

    private func defaultFrame() -> NSRect {
        frame(for: collapsedHeight)
    }

    private func frame(for height: CGFloat) -> NSRect {
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        let frame = primaryScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = frame.midX - (panelWidth / 2)

        // Keep the BOTTOM of the panel fixed at bottomOffset from screen bottom
        // Only expand upward by adjusting Y based on height
        let y = frame.minY + bottomOffset

        return NSRect(x: x, y: y, width: panelWidth, height: height)
    }
}
