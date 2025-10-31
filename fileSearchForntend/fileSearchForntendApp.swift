//
//  fileSearchForntendApp.swift
//  fileSearchForntend
//
//  Created by Ethan Pan on 10/19/25.
//

import SwiftUI
import HotKey

@main
struct fileSearchForntendApp: App {
    @State private var appModel = AppModel()
    @State private var showingPanel = false
    
    private var hotKey: HotKey
    
    init() {
        // Create a binding wrapper to capture the state
        let binding = Binding<Bool>(
            get: { false },
            set: { _ in }
        )
        
        hotKey = HotKey(key: .z, modifiers: [.control, .command])
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showingPanel: $showingPanel, hotKey: hotKey)
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 600)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
    }
}
