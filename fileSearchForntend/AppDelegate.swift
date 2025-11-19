//
//  AppDelegate.swift
//  fileSearchForntend
//
//  App delegate to manage floating panel independently of main window
//

import SwiftUI
import Combine
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var floatingPanel: NSPanel?
    @Published var showingPanel = false
    var hotKey: HotKey?
    
    // Store state for the floating panel
    @Published var searchText = ""
    @Published var floatingPanelResults: [SearchResultItem] = []
    @Published var isSearching = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup keyboard shortcut
        hotKey = HotKey(key: .z, modifiers: [.control, .command])
        hotKey?.keyDownHandler = { [weak self] in
            self?.togglePanel()
        }
    }
    
    // Prevent main window from being shown when app is activated via panel
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If the panel is showing, don't reopen windows
        if showingPanel {
            return false
        }
        return true
    }
    
    func togglePanel() {
        showingPanel.toggle()
        
        if showingPanel {
            if floatingPanel == nil {
                createPanel()
            }
            presentPanel()
        } else {
            dismissPanel()
        }
    }
    
    private var previousApp: NSRunningApplication?
    
    func presentPanel() {
        guard let panel = floatingPanel else { return }
        
        // CRITICAL: Store the currently active app BEFORE we do anything that might change it
        let frontmost = NSWorkspace.shared.frontmostApplication
        print("📱 Frontmost app when showing panel: \(frontmost?.localizedName ?? "Unknown") (\(frontmost?.bundleIdentifier ?? "no bundle ID"))")
        if frontmost?.bundleIdentifier != NSRunningApplication.current.bundleIdentifier {
            previousApp = frontmost
            print("✅ Stored previous app: \(previousApp?.localizedName ?? "Unknown")")
        } else {
            print("⚠️ Not storing - frontmost is our own app")
        }
        
        panel.orderFrontRegardless()
        // Activate app without bringing other windows forward, just for panel visibility
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate()
        } else {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        }
        // Make panel key for text input after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            panel.makeKey()
        }
    }
    
    func dismissPanel() {
        guard showingPanel else { return } // Prevent re-entry
        showingPanel = false
        
        // Hide panel immediately
        floatingPanel?.orderOut(nil)
        
        // Restore focus to previous app
        if let previous = self.previousApp, 
           previous.bundleIdentifier != NSRunningApplication.current.bundleIdentifier,
           !previous.isTerminated {
            print("🔄 Restoring focus to: \(previous.localizedName ?? "Unknown")")
            
            // Activate the previous app
            if #available(macOS 14.0, *) {
                previous.activate()
            } else {
                previous.activate(options: [.activateIgnoringOtherApps])
            }
            
            // Check if main window is visible - if not, hide our app entirely
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let hasVisibleWindows = NSApp.windows.contains { window in
                    window.isVisible && window != self.floatingPanel && window.className != "NSStatusBarWindow"
                }
                
                if !hasVisibleWindows {
                    // No other windows visible, hide the app to prevent main window from showing
                    NSApp.hide(nil)
                    print("✅ App hidden, no visible windows")
                } else {
                    print("✅ Focus restored, main window is visible")
                }
            }
        } else {
            print("⚠️ No valid previous app to restore focus to")
        }
    }
    
    private func createPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? CGRect.zero
        let panelWidth: CGFloat = 900
        let panelHeight: CGFloat = 60
        
        let contentRect = CGRect(
            x: screen.midX - (panelWidth / 2),
            y: screen.minY + 10,
            width: panelWidth,
            height: panelHeight
        )
        
        let panel = FloatingPanel(
            view: {
                FloatingPanelContentWrapper(appDelegate: self)
            },
            contentRect: contentRect,
            isPresented: Binding(
                get: { [weak self] in self?.showingPanel ?? false },
                set: { [weak self] newValue in
                    if !newValue {
                        self?.dismissPanel()
                    }
                }
            )
        )
        
        self.floatingPanel = panel
    }
}

// Wrapper view that connects to AppDelegate state
struct FloatingPanelContentWrapper: View {
    @ObservedObject var appDelegate: AppDelegate
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        FloatingPanelContentView(
            searchText: $appDelegate.searchText,
            results: $appDelegate.floatingPanelResults,
            isSearching: $appDelegate.isSearching,
            isSearchFieldFocused: $isSearchFieldFocused,
            onSearch: performFloatingSearch,
            onClear: clearFloatingSearch
        )
        .onAppear {
            // Focus search field when panel opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
    }
    
    private func performFloatingSearch() {
        guard !appDelegate.searchText.isEmpty else {
            clearFloatingSearch()
            return
        }
        
        appDelegate.isSearching = true
        
        Task {
            do {
                let response = try await APIClient.shared.search(query: appDelegate.searchText, limit: 3)
                await MainActor.run {
                    appDelegate.floatingPanelResults = Array(response.results.prefix(3))
                    appDelegate.isSearching = false
                }
            } catch {
                await MainActor.run {
                    appDelegate.floatingPanelResults = []
                    appDelegate.isSearching = false
                }
            }
        }
    }
    
    private func clearFloatingSearch() {
        appDelegate.searchText = ""
        appDelegate.floatingPanelResults = []
        appDelegate.isSearching = false
    }
}
