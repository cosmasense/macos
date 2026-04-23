//
//  WindowDragRegion.swift
//  fileSearchForntend
//
//  Invisible NSView wrapper that initiates a native window drag on
//  mouseDown. Used as a `.background { ... }` layer under the Quick
//  Search overlay's title bar and search pill so those areas move the
//  panel, while file tiles (which need `.onDrag` to work for file
//  drag-out) deliberately don't have this layer behind them.
//
//  We can't just set `isMovableByWindowBackground = true` on the panel
//  because that flag treats every non-control area as a drag surface —
//  including file tile cells — which steals mouseDown from SwiftUI's
//  drag-source machinery before the gesture recognizer sees it.
//

import SwiftUI
import AppKit

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
