//
//  ContentView.swift
//  fileSearchForntend
//
//  Main app layout with NavigationSplitView (Sidebar + Detail)
//

import SwiftUI
import HotKey

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
        .background(.windowBackground)
        
        let screen = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? CGRect.zero
        let panelWidth: CGFloat = 900
        let panelHeight: CGFloat = (!results.isEmpty || isSearching) ? 280 : 60
        
        let newFrame = CGRect(
            x: screen.midX - (panelWidth / 2),
            y: screen.minY + 10,
            width: panelWidth,
            height: panelHeight
        )
        
        print("📐 Resizing panel to height: \(panelHeight), has results: \(results.count), isSearching: \(isSearching)")
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true, animate: true)
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
        .environment(AppModel())
        .frame(width: 1000, height: 600)
}
