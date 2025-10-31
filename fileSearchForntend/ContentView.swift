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
    @Binding var showingPanel: Bool
    let hotKey: HotKey
    @State private var searchText = ""
    
    init(showingPanel: Binding<Bool>, hotKey: HotKey) {
            self._showingPanel = showingPanel
            self.hotKey = hotKey
        }

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
        .onAppear {
            hotKey.keyDownHandler = {
                NSApp.activate(ignoringOtherApps: true)
                showingPanel.toggle()
            }
        }
        .floatingPanel(
            isPresented: $showingPanel,
            contentRect: {
                let screen = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? CGRect.zero
                let panelWidth: CGFloat = 750
                let panelHeight: CGFloat = 60
                
                return CGRect(
                    x: screen.midX - (panelWidth / 2),  // Center horizontally
                    y: screen.minY + 10,                 // 10 points above the dock
                    width: panelWidth,
                    height: panelHeight
                )
            }(),
            content: {
                ZStack {
                    VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    
                    HStack(spacing: 12) {
                        // Search icon
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16, weight: .medium))
                        
                        // Search text field
                        TextField("Search files", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .frame(maxWidth: .infinity)
                        
                        // Clear button (only shown when there's text)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .help("Clear")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        )
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView(
        showingPanel: .constant(false),
        hotKey: HotKey(key: .z, modifiers: [.control, .command])
    )
    .environment(AppModel())
    .frame(width: 1000, height: 600)
}
