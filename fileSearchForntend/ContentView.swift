//
//  ContentView.swift
//  fileSearchForntend
//
//  Main app layout with NavigationSplitView (Sidebar + Detail)
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            // Sidebar with navigation items
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            // Detail area switches based on sidebar selection
            Group {
                switch model.selection {
                case .home, .none:
                    HomeView()
                case .jobs:
                    JobsView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(.ultraThinMaterial)
        
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
        .environment(AppModel())
        .frame(width: 1000, height: 600)
}
