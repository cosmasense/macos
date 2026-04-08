//
//  ContentView.swift
//  fileSearchForntend
//
//  Main app layout: flat ZStack with page switching and floating nav button.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ZStack(alignment: .topLeading) {
            // Page content
            Group {
                switch model.currentPage {
                case .home:
                    HomeView()
                        .transition(.opacity)
                case .folders:
                    FoldersView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating folder button — only on home page
            if model.currentPage == .home {
                FolderNavButton {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.currentPage = .folders
                    }
                }
                .padding(.top, 46)
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: model.currentPage)
    }
}

// MARK: - Floating Folder Button (Home page only)

struct FolderNavButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .semibold))

                if isHovered {
                    Text("Folders")
                        .font(.system(size: 12, weight: .medium))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, isHovered ? 14 : 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help("Folders")
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
        .environment(AppModel())
        .frame(width: 900, height: 600)
}
