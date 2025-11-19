//
//  Modifier+Extension.swift
//  fileSearchForntend
//
//  Created by Caleb Hamilton on 10/31/25.
//

import SwiftUI
 
/// Add a  ``FloatingPanel`` to a view hierarchy
fileprivate struct FloatingPanelModifier<PanelContent: View>: ViewModifier {
    /// Determines wheter the panel should be presented or not
    @Binding var isPresented: Bool
 
    /// Determines the starting size of the panel
    var contentRect: CGRect = CGRect(x: 0, y: 0, width: 624, height: 512)
 
    /// Holds the panel content's view closure
    @ViewBuilder let view: () -> PanelContent
 
    /// Stores the panel instance with the same generic type as the view closure
    @State var panel: FloatingPanel<PanelContent>?
    
    /// Stores the previously active application to restore focus when panel closes
    @State var previousApp: NSRunningApplication?
 
    func body(content: Content) -> some View {
        content
            .onAppear {
                /// When the view appears, create, center and present the panel if ordered
                panel = FloatingPanel(view: view, contentRect: contentRect, isPresented: $isPresented)
//                panel?.center()
                if isPresented {
                    present()
                }
            }.onDisappear {
                /// When the view disappears, close and kill the panel
                panel?.close()
                panel = nil
            }.onChange(of: isPresented) { value in
                /// On change of the presentation state, make the panel react accordingly
                if value {
                    present()
                } else {
                    dismiss()
                }
            }
    }
 
    /// Present the panel without bringing main window forward
    func present() {
        // Store the currently active app before we activate ours
        previousApp = NSWorkspace.shared.frontmostApplication
        
        panel?.orderFrontRegardless()
        // Activate app without bringing other windows forward, just for panel visibility
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate()
        } else {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        }
        // Make panel key for text input after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            panel?.makeKey()
        }
    }
    
    /// Dismiss the panel and restore focus to previous app
    func dismiss() {
        panel?.close()
        // Restore focus to the previously active app
        if let previous = previousApp, previous != NSRunningApplication.current {
            if #available(macOS 14.0, *) {
                previous.activate()
            } else {
                previous.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }
}

extension View {
    /** Present a ``FloatingPanel`` in SwiftUI fashion
     - Parameter isPresented: A boolean binding that keeps track of the panel's presentation state
     - Parameter contentRect: The initial content frame of the window
     - Parameter content: The displayed content
     **/
    func floatingPanel<Content: View>(isPresented: Binding<Bool>,
                                      contentRect: CGRect = CGRect(x: 0, y: 0, width: 624, height: 512),
                                      @ViewBuilder content: @escaping () -> Content) -> some View {
        self.modifier(FloatingPanelModifier(isPresented: isPresented, contentRect: contentRect, view: content))
    }
}
