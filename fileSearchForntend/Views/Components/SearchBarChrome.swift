//
//  SearchBarChrome.swift
//  fileSearchForntend
//
//  Shared chrome for every search bar in the app so the main-window bar,
//  the popup's collapsed pill, and the popup's window-mode inner bar are
//  all visually identical. Anything that wraps a search-bar HStack and
//  should read as "a search bar" goes through this modifier.
//

import SwiftUI

struct SearchBarChrome: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if #available(macOS 14.0, *) {
                    Color.clear.glassEffect(in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay {
                shape
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

extension View {
    /// Applies the shared search-bar chrome (glass background, neutral
    /// border, soft shadow) used by every search bar in the app.
    func searchBarChrome(cornerRadius: CGFloat = 22) -> some View {
        modifier(SearchBarChrome(cornerRadius: cornerRadius))
    }
}
