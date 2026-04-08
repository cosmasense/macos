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

            // Floating navigation button (top-left)
            NavigationButton(currentPage: $model.currentPage)
                .padding(.top, 12)
                .padding(.leading, 16)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: model.currentPage)
    }
}

// MARK: - Floating Navigation Button

private struct NavigationButton: View {
    @Binding var currentPage: AppPage
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentPage = currentPage == .home ? .folders : .home
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: currentPage == .home ? "folder.fill" : "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))

                if currentPage == .folders || isHovered {
                    Text(currentPage == .home ? "Folders" : "Search")
                        .font(.system(size: 12, weight: .medium))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, currentPage == .folders || isHovered ? 14 : 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background {
            let shape = Capsule()
            if #available(macOS 14.0, *) {
                Color.clear.glassEffect(in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help(currentPage == .home ? "Folders" : "Back to Search")
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
        .environment(AppModel())
        .frame(width: 900, height: 600)
}
