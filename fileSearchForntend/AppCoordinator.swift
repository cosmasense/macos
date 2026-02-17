//
//  AppCoordinator.swift
//  fileSearchForntend
//
//  Coordinates app-wide state like overlay visibility and global hotkeys
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppCoordinator {
    var isOverlayVisible: Bool = false
    
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
