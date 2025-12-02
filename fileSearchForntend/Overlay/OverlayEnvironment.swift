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

extension EnvironmentValues {
    var presentQuickSearchOverlay: () -> Void {
        get { self[PresentQuickSearchOverlayKey.self] }
        set { self[PresentQuickSearchOverlayKey.self] = newValue }
    }
}
