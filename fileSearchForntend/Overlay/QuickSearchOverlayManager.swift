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
        // Drag handling is opt-in per-area via `WindowDragRegion` views in
        // the SwiftUI content (title bar + search pill). We deliberately
        // DO NOT set `isMovableByWindowBackground` — that flag hijacks
        // mouseDown for every non-control area, including file tiles,
        // which breaks SwiftUI `.onDrag` file drag-out.
        isMovable = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // AppKit-managed shadow: the window manager draws a soft drop
        // shadow that follows the visible non-transparent pixels of
        // the panel content. This is the only way to get a shadow that
        // actually extends *outside* the panel's bounds — SwiftUI's
        // .shadow inside the view is clipped by the host layer's
        // `masksToBounds = true` (needed for the rounded corners), so
        // the panel previously read as flat against bright wallpapers.
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

@MainActor
final class QuickSearchOverlayController: NSObject, NSWindowDelegate {
    // Panel hugs the pill — no transparent padding around the glass,
    // otherwise the empty panel area reads as a dark rectangle behind
    // the pill on dim wallpapers. Must match the view's own heights.
    //
    // `baseHeight` = pill + (optional) results. `chromeHeight` is added ABOVE
    // the search bar when window-mode is active (traffic lights + expand).
    // The panel is anchored on the SEARCH BAR's top: when chrome appears we
    // grow upward so the bar's screen position stays put; results grow
    // downward as usual.
    private let collapsedHeight: CGFloat = 46
    private let expandedHeight: CGFloat = 522
    private let chromeHeight: CGFloat = 42
    // Two widths: idle pill matches the inner search bar exactly; the
    // expanded panel adds 20pt of margin on each side for results. Must
    // mirror the constants in QuickSearchOverlayView.
    private let collapsedWidth: CGFloat = 500
    private let expandedWidth: CGFloat = 540
    // Distance from the top of the main window (or screen, if main isn't
    // present yet) down to the TOP of the search bar. Remains constant
    // across layout modes — panel grows up (chrome) and down (results)
    // around that anchor.
    private let topOffset: CGFloat = 160
    // Must match QuickSearchOverlayView.transitionDuration and the
    // SwiftUI timing curve (0.22, 1, 0.36, 1). AppKit's frame tween and
    // SwiftUI's content tween share the same cubic bezier so there's no
    // perceptible drift between the window edge and the content inside.
    private let expansionDuration: CGFloat = 0.42

    // Persisted so the overlay returns to wherever the user last dragged
    // it. We track the panel's CENTER X (not left edge) because the panel
    // grows wider on expand — center-anchoring keeps the search bar visually
    // pinned in place across the width change. `searchBarTop` is the TOP
    // of the search bar in global AppKit coordinates — the stable vertical
    // anchor that expand/collapse pivots around.
    private let centerXDefaultsKey = "quickSearchOverlayCenterX"
    private let searchBarTopDefaultsKey = "quickSearchOverlaySearchBarTop"

    private var panel: NonActivatingPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var dismissalCallback: (() -> Void)?
    private var zoomToMainCallback: (() -> Void)?
    private weak var appModel: AppModel?
    private var dragEndTimer: Timer?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    // Current layout state so `windowDidMove` can back out the search-bar
    // anchor from the panel's total frame (panel height = base + chrome).
    private var currentIsExpanded: Bool = false
    private var currentHasChrome: Bool = false

    // User's dragged position. `nil` means "use default (main app window,
    // or screen fallback)". Hydrated from UserDefaults on present.
    // `userCenterX` is the panel's CENTER X (see notes on the defaults key).
    private var userCenterX: CGFloat?
    private var userSearchBarTop: CGFloat?

    // Set while we reposition the panel programmatically so the resulting
    // `windowDidMove` doesn't round-trip the computed position back into
    // the user-preference slot. NSWindow fires `windowDidMove` for every
    // frame of the expand/collapse animation too, so this stays true
    // until the animation's completion handler runs.
    private var suppressMoveTracking: Bool = false

    func present(appModel: AppModel, onDismiss: @escaping () -> Void, onZoomToMain: @escaping () -> Void = {}) {
        dismissalCallback = onDismiss
        zoomToMainCallback = onZoomToMain
        self.appModel = appModel

        // NOTE: We deliberately do NOT clear popupSearchText / results here.
        // Users expect the hotkey to act like a spotlight toggle — hide on
        // one press, reveal the same query + results on the next. State is
        // only wiped when the user hits Esc inside the overlay (see
        // QuickSearchOverlayView's Esc handler).
        appModel.popupOpenCount += 1

        if panel == nil {
            let contentView = QuickSearchOverlayView(
                onClose: { [weak self] in
                    self?.dismiss()
                },
                onZoomToMain: { [weak self] in
                    let callback = self?.zoomToMainCallback
                    self?.dismiss()
                    callback?()
                }
            )
            .environment(appModel)
            .environment(\.updateQuickSearchLayout, { [weak self] isExpanded, hasChrome in
                self?.updateLayout(isExpanded: isExpanded, hasChrome: hasChrome)
            })
            .environment(\.quickSearchDragState, { [weak self] isDragging in
                self?.setDragThrough(isDragging)
            })

            let host = NSHostingController(rootView: AnyView(contentView))
            // The overlay now renders as a single unified rounded panel, so
            // clip the host view's layer to match SwiftUI's outer
            // `clipShape(RoundedRectangle(cornerRadius: 22))`. Without this,
            // the rectangular AppKit layer behind the SwiftUI content leaks
            // past the rounded corners of the glass.
            host.view.wantsLayer = true
            host.view.layer?.backgroundColor = NSColor.clear.cgColor
            host.view.layer?.isOpaque = false
            host.view.layer?.cornerRadius = 22
            host.view.layer?.cornerCurve = .continuous
            host.view.layer?.masksToBounds = true

            let newPanel = NonActivatingPanel(contentRect: defaultFrame())
            newPanel.contentViewController = host
            newPanel.delegate = self
            // Drag regions are carried by SwiftUI `WindowDragRegion` views
            // in the title bar and search pill — NOT by window-background
            // dragging, which would steal mouseDown from file tiles and
            // break their `.onDrag` file drag-out.
            newPanel.isMovable = true

            hostingController = host
            self.panel = newPanel
        }

        // Reset layout to collapsed state and position the panel at the
        // user's remembered spot, or — failing that — at the main app
        // window's position. The suppress flag keeps the initial setFrame
        // from being recorded as a user drag.
        currentIsExpanded = false
        currentHasChrome = false
        restoreSavedPosition()
        suppressMoveTracking = true
        panel?.setFrame(defaultFrame(), display: false)
        suppressMoveTracking = false
        panel?.orderFrontRegardless()
        panel?.makeKey()
        // Click-outside dismissal is gated on search state: an empty pill
        // closes on any outside click (the user is done and hasn't typed
        // anything), but once there's text, tokens, or results we keep the
        // panel up so users can bounce to another app without losing work.
        installOutsideClickMonitors()
    }

    func dismiss() {
        guard let panel else { return }
        dragEndTimer?.invalidate()
        dragEndTimer = nil
        removeOutsideClickMonitors()
        panel.ignoresMouseEvents = false
        panel.orderOut(nil)
        let callback = dismissalCallback
        dismissalCallback = nil
        callback?()
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.handleOutsideClick() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel {
                Task { @MainActor in self.handleOutsideClick() }
            }
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    private func handleOutsideClick() {
        guard let appModel else { return }
        let hasActiveSearch = !appModel.popupSearchText.isEmpty
            || !appModel.popupSearchTokens.isEmpty
            || !appModel.popupSearchResults.isEmpty
        guard !hasActiveSearch else { return }
        dismiss()
    }

    func toggle(appModel: AppModel, visible: Bool, onDismiss: @escaping () -> Void, onZoomToMain: @escaping () -> Void = {}) {
        if visible {
            present(appModel: appModel, onDismiss: onDismiss, onZoomToMain: onZoomToMain)
        } else {
            dismiss()
        }
    }

    func updateLayout(isExpanded: Bool, hasChrome: Bool = false) {
        guard let panel else { return }
        currentIsExpanded = isExpanded
        currentHasChrome = hasChrome
        let newFrame = frame(isExpanded: isExpanded, hasChrome: hasChrome)
        suppressMoveTracking = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = expansionDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(newFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.suppressMoveTracking = false
            }
        })
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
        // Panel was closed externally (e.g., Escape key routed through
        // NSPanel's cancelOperation, or a programmatic close). The
        // dismissal callback no longer surfaces main, so just fire it.
        let callback = dismissalCallback
        dismissalCallback = nil
        callback?()
    }

    func windowDidMove(_ notification: Notification) {
        guard !suppressMoveTracking, let panel = panel else { return }
        guard (notification.object as AnyObject?) === panel else { return }

        // Back out the search-bar anchor from the current frame.
        // Panel top = searchBarTop + chrome → searchBarTop = maxY - chrome.
        // We store the CENTER X so the next expand/collapse keeps the
        // pill visually anchored even though the panel changes width.
        let chrome: CGFloat = currentHasChrome ? chromeHeight : 0
        userCenterX = panel.frame.midX
        userSearchBarTop = panel.frame.maxY - chrome
        persistPosition()
    }

    private func defaultFrame() -> NSRect {
        frame(isExpanded: currentIsExpanded, hasChrome: currentHasChrome)
    }

    /// Panel frame anchored on the SEARCH BAR's top (vertically) and the
    /// pill's CENTER X (horizontally). Chrome (if any) extends UP from the
    /// search bar; the base content (pill + results) extends DOWN. Width
    /// switches between collapsed/expanded but the center stays put, so
    /// expand/collapse only grows the panel around the user's anchor.
    private func frame(isExpanded: Bool, hasChrome: Bool) -> NSRect {
        let baseHeight = isExpanded ? expandedHeight : collapsedHeight
        let chrome: CGFloat = hasChrome ? chromeHeight : 0
        let totalHeight = baseHeight + chrome
        let width = isExpanded ? expandedWidth : collapsedWidth

        let centerX = userCenterX ?? defaultCenterX()
        let x = centerX - (width / 2)
        let searchBarTop = userSearchBarTop ?? defaultSearchBarTop()

        // AppKit Y is bottom-up. origin.y anchors the BOTTOM of the panel.
        // Panel top = searchBarTop + chrome.
        // Panel bottom = panel top - totalHeight = searchBarTop - baseHeight.
        let y = searchBarTop - baseHeight

        return NSRect(x: x, y: y, width: width, height: totalHeight)
    }

    /// Horizontal center for the first-ever open: center on the main app
    /// window so the popup "replaces" the app visually. Falls back to
    /// screen-center if the main window isn't up yet.
    private func defaultCenterX() -> CGFloat {
        if let mainFrame = mainAppWindowFrame() {
            return mainFrame.midX
        }
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return screenFrame.midX
    }

    /// Search-bar Y for the first-ever open: matches where the main
    /// window's search bar sits (`topOffset` below the main window's top
    /// edge). Falls back to `topOffset` below the screen top otherwise.
    private func defaultSearchBarTop() -> CGFloat {
        if let mainFrame = mainAppWindowFrame() {
            return mainFrame.maxY - topOffset
        }
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return screenFrame.maxY - topOffset
    }

    /// Matches AppDelegate.showMainWindow's criteria: the normal-level
    /// main WindowGroup window, excluding the floating popup panel and
    /// the Settings scene. Frame is valid even when the window is hidden
    /// (zoomToPopup hides it before presenting the overlay).
    private func mainAppWindowFrame() -> NSRect? {
        NSApp.windows.first(where: { window in
            window !== panel
                && window.contentView != nil
                && window.level != .floating
                && window.title != "Settings"
        })?.frame
    }

    private func persistPosition() {
        let defaults = UserDefaults.standard
        if let cx = userCenterX {
            defaults.set(Double(cx), forKey: centerXDefaultsKey)
        }
        if let y = userSearchBarTop {
            defaults.set(Double(y), forKey: searchBarTopDefaultsKey)
        }
    }

    /// Hydrate `userCenterX` / `userSearchBarTop` from UserDefaults.
    /// Discards values that would place the search bar outside every
    /// connected screen — protects against saved positions that become
    /// unreachable after a display is disconnected.
    private func restoreSavedPosition() {
        let defaults = UserDefaults.standard
        guard let cxObj = defaults.object(forKey: centerXDefaultsKey) as? Double,
              let yObj = defaults.object(forKey: searchBarTopDefaultsKey) as? Double
        else { return }

        let cx = CGFloat(cxObj)
        let y = CGFloat(yObj)
        // Probe is the panel's center point in collapsed state — if it
        // lands on any screen's visible area, the saved position is
        // usable. Otherwise ignore it and fall back to the default.
        let probe = NSPoint(x: cx, y: y - collapsedHeight / 2)
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.contains(probe) }
        guard onScreen else { return }

        userCenterX = cx
        userSearchBarTop = y
    }
}
