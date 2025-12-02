//
//  DragHandle.swift
//  fileSearchForntend
//
//  A small draggable area to move the floating overlay window.
//

import SwiftUI
import AppKit

struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

final class DragHandleView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        window.performDrag(with: event)
    }
}
