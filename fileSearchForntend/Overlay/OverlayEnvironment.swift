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
    static let defaultValue: (Bool) -> Void = { _ in }
}

private struct ControlHotkeyMonitoringKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var presentQuickSearchOverlay: () -> Void {
        get { self[PresentQuickSearchOverlayKey.self] }
        set { self[PresentQuickSearchOverlayKey.self] = newValue }
    }

    var updateQuickSearchLayout: (Bool) -> Void {
        get { self[UpdateQuickSearchLayoutKey.self] }
        set { self[UpdateQuickSearchLayoutKey.self] = newValue }
    }

    var controlHotkeyMonitoring: (Bool) -> Void {
        get { self[ControlHotkeyMonitoringKey.self] }
        set { self[ControlHotkeyMonitoringKey.self] = newValue }
    }
}
