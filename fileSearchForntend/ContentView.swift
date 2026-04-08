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
                .padding(.top, 14)
                .padding(.leading, 78)
        }
        .background(.windowBackground)
        .animation(.easeInOut(duration: 0.2), value: model.currentPage)
    }
}

// MARK: - Floating Navigation Button

private struct NavigationButton: View {
    @Binding var currentPage: AppPage

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentPage = currentPage == .home ? .folders : .home
            }
        } label: {
            Image(systemName: currentPage == .home ? "folder.fill" : "chevron.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .background {
            if #available(macOS 14.0, *) {
                Color.clear.glassEffect(in: Circle())
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .help(currentPage == .home ? "Folders" : "Back to Search")
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
        .environment(AppModel())
        .frame(width: 900, height: 600)
}
