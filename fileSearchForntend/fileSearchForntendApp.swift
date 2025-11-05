//
//  fileSearchFrontendApp.swift
//  fileSearchFrontend
//
//  Created by Ethan Pan on 10/19/25.
//

import SwiftUI

@main
struct fileSearchForntendApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 600)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
        .commands {
            // Enable standard window commands including fullscreen
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
    }
}
