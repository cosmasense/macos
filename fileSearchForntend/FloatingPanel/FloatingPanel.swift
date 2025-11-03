//
//  FloatingPanel.swift
//  fileSearchForntend
//
//  Created by Caleb Hamilton on 10/31/25.
//


import SwiftUI
 
/// An NSPanel subclass that implements floating panel traits.
class FloatingPanel<Content: View>: NSPanel {
    @Binding var isPresented: Bool
    
    init(view: () -> Content,
             contentRect: NSRect,
             backing: NSWindow.BackingStoreType = .buffered,
             defer flag: Bool = false,
             isPresented: Binding<Bool>) {
        /// Initialize the binding variable by assigning the whole value via an underscore
        self._isPresented = isPresented
     
        /// Init the window as usual
        super.init(contentRect: contentRect,
                    styleMask: [.nonactivatingPanel, .titled, .resizable, .closable, .fullSizeContentView],
                    backing: backing,
                    defer: flag)
     
        /// Allow the panel to be on top of other windows and appear across all spaces
        isFloatingPanel = true
        level = .statusBar  // Status bar level to ensure visibility across all spaces
     
        /// Allow the panel to appear in all spaces and be overlaid in fullscreen
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
     
        /// Don't show a window title, even if it's set
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
     
        /// Since there is no title bar make the window moveable by dragging on the background
        // isMovableByWindowBackground = true
     
        /// Hide when unfocused
        hidesOnDeactivate = true
     
        /// Hide all traffic light buttons
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
     
        /// Sets animations accordingly
        animationBehavior = .utilityWindow
     
        /// Set the content view.
        /// The safe area is ignored because the title bar still interferes with the geometry
        contentView = NSHostingView(rootView: view()
            .ignoresSafeArea()
            .environment(\.floatingPanel, self))
    }
    
    /// Close automatically when out of focus, e.g. outside click
    override func resignMain() {
        // Don't call super.resignMain() as it might trigger main window activation
        // Set binding to false which will trigger dismissal through AppDelegate
        isPresented = false
    }
     
    /// Override close to prevent direct closing - use orderOut instead
    override func close() {
        // Don't call super.close() to avoid window restoration issues
        // Instead just hide the panel
        orderOut(nil)
        isPresented = false
    }
     
    /// `canBecomeKey` is required so that text inputs inside the panel can receive focus
    /// `canBecomeMain` is set to false to prevent the panel from becoming the main window
    override var canBecomeKey: Bool {
        return true
    }
     
    override var canBecomeMain: Bool {
        return false
    }
}

private struct FloatingPanelKey: EnvironmentKey {
    static let defaultValue: NSPanel? = nil
}
 
extension EnvironmentValues {
  var floatingPanel: NSPanel? {
    get { self[FloatingPanelKey.self] }
    set { self[FloatingPanelKey.self] = newValue }
  }
}
