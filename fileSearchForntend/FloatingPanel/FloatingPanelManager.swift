import SwiftUI
import AppKit
import Combine

class FloatingPanelManager: ObservableObject {
    private var panel: NSPanel?
    @Published var isShowing = false
    
    func toggle() {
        if isShowing {
            hide()
        } else {
            show()
        }
    }
    
    func show() {
        if panel == nil {
            createPanel()
        }
        
        panel?.orderFrontRegardless()
        isShowing = true
    }
    
    func hide() {
        panel?.orderOut(nil)
        isShowing = false
    }
    
    private func createPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
        let panelWidth: CGFloat = 750
        let panelHeight: CGFloat = 60
        
        let contentRect = CGRect(
            x: screen.midX - (panelWidth / 2),
            y: screen.maxY - panelHeight - 10,
            width: panelWidth,
            height: panelHeight
        )
        
        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        panel?.level = .floating
        panel?.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel?.isFloatingPanel = true
        panel?.backgroundColor = .clear
        panel?.isOpaque = false
        panel?.hasShadow = true
        
        let hostingView = NSHostingView(rootView: FloatingSearchView(manager: self))
        panel?.contentView = hostingView
    }
}

struct FloatingSearchView: View {
    @ObservedObject var manager: FloatingPanelManager
    @State private var searchText = ""
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))
                
                TextField("Search files", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                
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
        .onExitCommand {
            manager.hide()
        }
    }
}
