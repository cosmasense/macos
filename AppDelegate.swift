//
//  AppDelegate.swift
//  fileSearchForntend
//
//  App delegate to keep global hotkey monitor alive
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    // Strong reference - stays alive for app lifetime
    var hotkeyMonitor: GlobalHotkeyMonitor?
    var overlayController: QuickSearchOverlayController?
    var coordinator: AppCoordinator?
    var appModel: AppModel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 App delegate initialized - hotkey monitor will stay alive")
    }
    
    func registerHotkey(_ hotkey: String, action: @escaping () -> Void) {
        if hotkeyMonitor == nil {
            hotkeyMonitor = GlobalHotkeyMonitor()
            print("✨ Created new GlobalHotkeyMonitor in AppDelegate")
        }
        
        hotkeyMonitor?.update(hotkey: hotkey, action: action)
    }
    
    func stopHotkey() {
        hotkeyMonitor?.stop()
    }
}
