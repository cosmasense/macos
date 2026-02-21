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
    private let collapsedHeight: CGFloat = 96
    private let expandedHeight: CGFloat = 286
    private let panelWidth: CGFloat = 626
    private let bottomOffset: CGFloat = 30

    private var panel: NonActivatingPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var dismissalCallback: (() -> Void)?
    private weak var appModel: AppModel?
    private var clickOutsideMonitor: Any?
    private var dragEndTimer: Timer?

    func present(appModel: AppModel, onDismiss: @escaping () -> Void) {
        dismissalCallback = onDismiss
        self.appModel = appModel

        // Clear previous popup search state so the overlay starts fresh & collapsed
        appModel.popupSearchText = ""
        appModel.popupSearchResults = []
        appModel.popupSearchTokens = []
        appModel.popupSearchError = nil
        appModel.popupOpenCount += 1

        if panel == nil {
            let contentView = QuickSearchOverlayView(onClose: { [weak self] in
                self?.dismiss()
            })
            .environment(appModel)
            .environment(\.updateQuickSearchLayout, { [weak self] isExpanded in
                self?.updateLayout(isExpanded: isExpanded)
            })
            .environment(\.quickSearchDragState, { [weak self] isDragging in
                self?.setDragThrough(isDragging)
            })

            let host = NSHostingController(rootView: AnyView(contentView))
            host.view.wantsLayer = true
            host.view.layer?.cornerRadius = 30
            host.view.layer?.cornerCurve = .continuous
            host.view.layer?.masksToBounds = true

            let newPanel = NonActivatingPanel(contentRect: defaultFrame())
            newPanel.contentViewController = host
            newPanel.delegate = self
            newPanel.isMovable = false

            hostingController = host
            self.panel = newPanel
        }

        // Reset to collapsed size and re-center on current screen
        panel?.setFrame(defaultFrame(), display: false)
        panel?.orderFrontRegardless()
        panel?.makeKey()
        installClickOutsideMonitor()
    }

    func dismiss() {
        guard let panel else { return }
        removeClickOutsideMonitor()
        dragEndTimer?.invalidate()
        dragEndTimer = nil
        panel.alphaValue = 1.0
        panel.ignoresMouseEvents = false
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

    func setDragThrough(_ enabled: Bool) {
        guard let panel else { return }
        if enabled {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0.35
            }
            panel.ignoresMouseEvents = true
            // Poll mouse button state to detect drag end
            // (global leftMouseUp monitors don't fire during drag sessions)
            // Grace period lets the drag session fully register before we start checking
            let dragStart = Date()
            dragEndTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard Date().timeIntervalSince(dragStart) > 0.4 else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    timer.invalidate()
                    Task { @MainActor in
                        self?.setDragThrough(false)
                    }
                }
            }
        } else {
            dragEndTimer?.invalidate()
            dragEndTimer = nil
            panel.ignoresMouseEvents = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1.0
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Panel was closed externally (e.g., Escape key) — notify coordinator
        let callback = dismissalCallback
        dismissalCallback = nil
        callback?()
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let screenPoint = NSEvent.mouseLocation
            if !panel.frame.contains(screenPoint) {
                Task { @MainActor in
                    self.dismiss()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
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
