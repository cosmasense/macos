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
    private var panel: NonActivatingPanel?
    private var hostingController: ( NSViewController)?
    private var dismissalCallback: (() -> Void)?

    func present(appModel: AppModel, onDismiss: @escaping () -> Void) {
        dismissalCallback = onDismiss

        if panel == nil {
            let contentView = QuickSearchOverlayView(onClose: { [weak self] in
                self?.dismiss()
            })
            .environment(appModel)

            let host = NSHostingController(rootView: contentView)
            let panel = NonActivatingPanel(contentRect: defaultFrame())
            panel.contentViewController = host
            panel.delegate = self
            panel.isMovable = false

            hostingController = host
            self.panel = panel
        }

        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func dismiss() {
        guard panel != nil else { return }
        panel?.close()
        cleanupAfterClose()
    }

    func toggle(appModel: AppModel, visible: Bool, onDismiss: @escaping () -> Void) {
        if visible {
            present(appModel: appModel, onDismiss: onDismiss)
        } else {
            dismiss()
        }
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
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        let frame = primaryScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let width: CGFloat = 940
        let height: CGFloat = 260

        let x = frame.midX - (width / 2)
        // Anchor near the bottom of the visible area
        let y = frame.minY + 100

        return NSRect(x: x, y: y, width: width, height: height)
    }
}
