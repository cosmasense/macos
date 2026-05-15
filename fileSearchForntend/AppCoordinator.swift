//
//  AppCoordinator.swift
//  fileSearchForntend
//
//  Coordinates app-wide state like overlay visibility and global hotkeys
//

import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class AppCoordinator {
    var isOverlayVisible: Bool = false

    /// True while the main WindowGroup's view tree is mounted. Set by
    /// the binder helper view's onAppear/onDisappear. AppDelegate uses
    /// this to choose between two reopen strategies:
    ///   - mounted=true: surface the tracked `mainWindow` directly.
    ///   - mounted=false: call `openMainWindowAction` so SwiftUI
    ///     remounts the view tree.
    /// Without this flag we couldn't tell "main window is just hidden,
    /// raise it" apart from "main window's view tree was torn down,
    /// raising it shows an empty shell" — which is the .accessory-mode
    /// menu-bar-icon-click bug we hit even after filtering the level=25
    /// SwiftUI placeholder ghosts out.
    var isMainWindowMounted: Bool = false

    /// Asks SwiftUI to recreate the main WindowGroup window. Wired by a
    /// helper view that captures `@Environment(\.openWindow)` — see
    /// `OpenMainWindowBinder` in fileSearchForntendApp.swift. Used by
    /// AppDelegate when the SwiftUI view tree is torn down (Cmd+W on
    /// the main window) and we need SwiftUI itself to remount it.
    @ObservationIgnored var openMainWindowAction: (() -> Void)?

    func toggleOverlay() {
        isOverlayVisible.toggle()
    }
    
    func showOverlay() {
        if !isOverlayVisible {
            isOverlayVisible = true
        }
    }
    
    func hideOverlay() {
        if isOverlayVisible {
            isOverlayVisible = false
        }
    }
}
