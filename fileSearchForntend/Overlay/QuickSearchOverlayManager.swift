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
    private weak var appModel: AppModel?

    func present(appModel: AppModel, onDismiss: @escaping () -> Void) {
        dismissalCallback = onDismiss
        self.appModel = appModel

        // Clear previous search state so the overlay starts collapsed
        appModel.searchText = ""
        appModel.searchResults = []
        appModel.searchTokens = []

        if panel == nil {
            let contentView = QuickSearchOverlayView(onClose: { [weak self] in
                self?.dismiss()
            })
            .environment(appModel)
            .environment(\.updateQuickSearchLayout, { [weak self] isExpanded in
                self?.updateLayout(isExpanded: isExpanded)
            })

            let host = NSHostingController(rootView: AnyView(contentView))
            host.view.wantsLayer = true
            host.view.layer?.cornerRadius = 30
            host.view.layer?.cornerCurve = .continuous
            host.view.layer?.masksToBounds = true

            let panel = NonActivatingPanel(contentRect: defaultFrame())
            panel.contentViewController = host
            panel.delegate = self
            panel.isMovable = false

            hostingController = host
            self.panel = panel
        }

        // Reset to collapsed size and re-center on current screen
        panel?.setFrame(defaultFrame(), display: false)
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func dismiss() {
        guard let panel else { return }
        panel.orderOut(nil)
        let callback = dismissalCallback
        dismissalCallback = nil
        callback?()
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
        // Panel was closed externally (e.g., Escape key) — notify coordinator
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
