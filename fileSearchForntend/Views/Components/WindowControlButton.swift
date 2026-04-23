//
//  WindowControlButton.swift
//  fileSearchForntend
//
//  Small circular glass button used for window-level controls
//  (zoom between main <-> popup, close popup, etc).
//

import SwiftUI

struct WindowControlButton: View {
    let systemImage: String
    var iconSize: CGFloat = 11
    var diameter: CGFloat = 28
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: diameter, height: diameter)
                .background {
                    if #available(macOS 14.0, *) {
                        Color.clear.glassEffect(in: Circle())
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isHovering ? 0.45 : 0.25), lineWidth: 0.6)
                )
                .scaleEffect(isHovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

/// Classic macOS traffic-light window controls. Close (red) dismisses the
/// overlay outright; minimize (yellow) collapses the overlay back to its
/// empty pill state. Symbols surface on group hover, matching native windows.
struct TrafficLightControls: View {
    let onClose: () -> Void
    let onMinimize: () -> Void

    @State private var isGroupHovering = false

    var body: some View {
        HStack(spacing: 8) {
            TrafficLightButton(
                color: Color(red: 1.0, green: 0.373, blue: 0.341),
                symbol: "xmark",
                showSymbol: isGroupHovering,
                action: onClose
            )
            .help("Close")

            TrafficLightButton(
                color: Color(red: 1.0, green: 0.741, blue: 0.176),
                symbol: "minus",
                showSymbol: isGroupHovering,
                action: onMinimize
            )
            .help("Collapse")
        }
        .onHover { isGroupHovering = $0 }
    }
}

private struct TrafficLightButton: View {
    let color: Color
    let symbol: String
    let showSymbol: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                Circle()
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                if showSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
            }
            .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
    }
}
