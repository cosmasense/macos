//
//  OverlayEnvironment.swift
//  fileSearchForntend
//
//  Environment helpers for presenting the quick search overlay.
//

import SwiftUI

private struct PresentQuickSearchOverlayKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct UpdateQuickSearchLayoutKey: EnvironmentKey {
    static let defaultValue: (Bool, Bool) -> Void = { _, _ in }
}

private struct ControlHotkeyMonitoringKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

private struct QuickSearchDragStateKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

private struct ZoomToPopupKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct ZoomToMainKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var presentQuickSearchOverlay: () -> Void {
        get { self[PresentQuickSearchOverlayKey.self] }
        set { self[PresentQuickSearchOverlayKey.self] = newValue }
    }

    /// Closure signature: `(isExpanded, hasChrome) -> Void`. `hasChrome` toggles
    /// the title-bar area above the search bar — the panel grows UPWARD to fit
    /// it so the search bar's screen position stays anchored.
    var updateQuickSearchLayout: (Bool, Bool) -> Void {
        get { self[UpdateQuickSearchLayoutKey.self] }
        set { self[UpdateQuickSearchLayoutKey.self] = newValue }
    }

    var controlHotkeyMonitoring: (Bool) -> Void {
        get { self[ControlHotkeyMonitoringKey.self] }
        set { self[ControlHotkeyMonitoringKey.self] = newValue }
    }

    var quickSearchDragState: (Bool) -> Void {
        get { self[QuickSearchDragStateKey.self] }
        set { self[QuickSearchDragStateKey.self] = newValue }
    }

    var zoomToPopup: () -> Void {
        get { self[ZoomToPopupKey.self] }
        set { self[ZoomToPopupKey.self] = newValue }
    }

    var zoomToMain: () -> Void {
        get { self[ZoomToMainKey.self] }
        set { self[ZoomToMainKey.self] = newValue }
    }
}
