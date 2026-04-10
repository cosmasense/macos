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

            // Embedder loading indicator (top-right)
            if !model.isEmbedderReady {
                EmbedderLoadingBadge(progress: model.embedderLoadProgress)
                    .padding(.top, 46)
                    .padding(.trailing, 18)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Model availability warning banner (top-right, below embedder badge)
            if let warning = model.modelAvailabilityWarning {
                ModelWarningBanner(warning: warning) {
                    model.dismissModelAvailabilityWarning()
                } onRetry: {
                    Task { await model.checkModelAvailability() }
                }
                .padding(.top, model.isEmbedderReady ? 46 : 110)
                .padding(.trailing, 18)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: model.currentPage)
        .animation(.easeInOut(duration: 0.3), value: model.isEmbedderReady)
        .animation(.easeInOut(duration: 0.3), value: model.modelAvailabilityWarning)
    }
}

// MARK: - Model Warning Banner

struct ModelWarningBanner: View {
    let warning: AppModel.ModelAvailabilityWarning
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Summarizer model unavailable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(warning.provider): \(warning.model)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(warning.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 280, alignment: .leading)

            VStack(spacing: 4) {
                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Retry model check")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Embedder Loading Badge

struct EmbedderLoadingBadge: View {
    var progress: Double

    private var percentage: Int {
        min(Int(progress * 100), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Loading embedding models...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.yellow.opacity(0.7), .orange.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(CGFloat(progress), 0.02), height: 4)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Floating Folder Button (Home page only)

struct FolderNavButton: View {
    let action: () -> Void

    var body: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
            .glassEffect(.regular, in: .circle)
            .onTapGesture(perform: action)
            .help("Folders")
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
        .environment(AppModel())
        .frame(width: 900, height: 600)
}
