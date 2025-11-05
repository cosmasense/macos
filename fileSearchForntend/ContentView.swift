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
        @Bindable var model = model

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
        .alert("Error", isPresented: $model.showError, presenting: model.lastError) { _ in
            Button("OK") {
                model.showError = false
                model.lastError = nil
            }
        } message: { error in
            Text(error.errorDescription ?? "An unknown error occurred")
        }

    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
        .environment(AppModel())
        .frame(width: 1000, height: 600)
}
