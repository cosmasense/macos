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
        .background(.ultraThinMaterial)
    }
}

// MARK: - Floating Panel Content View

struct FloatingPanelContentView: View {
    @Binding var searchText: String
    @Binding var results: [SearchResultItem]
    @Binding var isSearching: Bool
    @FocusState.Binding var isSearchFieldFocused: Bool
    let onSearch: () -> Void
    let onClear: () -> Void
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.floatingPanel) private var floatingPanel
    
    var body: some View {
        VStack(spacing: 0) {
            // Results area (above search bar)
            if isSearching {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            } else if !results.isEmpty {
                HStack(spacing: 12) {
                    ForEach(results) { result in
                        CompactSearchResultCard(result: result)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            }
            
            // Search bar (at bottom)
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
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            onSearch()
                        }
                        .onKeyPress(.escape) {
                            // Close panel when ESC is pressed
                            // Use Task to avoid "Publishing changes from within view updates" error
                            Task { @MainActor in
                                if let panel = floatingPanel as? FloatingPanel<FloatingPanelContentWrapper> {
                                    panel.isPresented = false
                                }
                            }
                            return .handled
                        }
                        .onChange(of: searchText) { oldValue, newValue in
                            print("⌨️ TextField onChange: '\(oldValue)' -> '\(newValue)'")
                            // Cancel previous search task
                            searchTask?.cancel()
                            
                            // Debounce search - wait 0.5 seconds after user stops typing
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                if !Task.isCancelled {
                                    print("⏰ Debounce timer fired, calling onSearch")
                                    await MainActor.run {
                                        onSearch()
                                    }
                                }
                            }
                        }
                    
                    // Clear button (only shown when there's text)
                    if !searchText.isEmpty {
                        Button(action: onClear) {
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
            .frame(height: 60)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: results) { oldValue, newValue in
            print("📊 Results changed from \(oldValue.count) to \(newValue.count)")
            resizePanel()
        }
        .onChange(of: isSearching) { oldValue, newValue in
            print("🔄 isSearching changed from \(oldValue) to \(newValue)")
            resizePanel()
        }
    }
    
    private func resizePanel() {
        guard let panel = floatingPanel else {
            print("⚠️ No panel reference available")
            return
        }
        
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
