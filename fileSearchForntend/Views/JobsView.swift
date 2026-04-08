//
//  JobsView.swift
//  fileSearchForntend
//
//  Manages watched folders and displays indexing progress.
//  Processing queue accessible via sheet.
//

import SwiftUI
import UniformTypeIdentifiers

struct FoldersView: View {
    @Environment(AppModel.self) private var model
    @State private var showFolderPicker = false
    @State private var showProcessing = false
    @AppStorage("backgroundStyle") private var backgroundStyle: String = BackgroundStyle.glass.rawValue

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            // Back button row
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.currentPage = .home
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Search")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Capsule())

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 46)
            .padding(.bottom, 8)

            // Header row: title + actions
            HStack(spacing: 12) {
                Text("Folders")
                    .font(.system(size: 24, weight: .bold))

                Spacer()

                // Processing pill button
                Button {
                    showProcessing = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Processing")
                            .font(.system(size: 12, weight: .medium))
                        if let status = model.queueStatus, status.totalItems > 0 {
                            Text("\(status.totalItems)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background {
                    Capsule().fill(.quaternary.opacity(0.5))
                }
                .help("View processing queue")

                Button {
                    Task { await model.refreshWatchedFolders() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Refresh")

                if model.isLoadingWatchedFolders {
                    ProgressView()
                        .frame(width: 14, height: 14)
                        .controlSize(.small)
                }

                Button(action: { showFolderPicker = true }) {
                    Label("Add Folder", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)

            if model.missingWatchedEndpoint {
                MissingEndpointBanner()
                    .padding(.horizontal, 32)
            }

            Divider()
                .padding(.horizontal, 32)

            // Folder list or empty state
            if model.isLoadingWatchedFolders {
                LoadingFoldersView()
            } else if model.watchedFolders.isEmpty {
                EmptyFoldersView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.watchedFolders) { folder in
                            FolderRowView(folder: folder)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Group {
                if backgroundStyle == BackgroundStyle.cosma.rawValue {
                    CosmaGradientBackground()
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
        .sheet(isPresented: $showProcessing) {
            QueueSheetView()
                .environment(model)
                .frame(minWidth: 580, minHeight: 450)
        }
        .alert(
            "Backend",
            isPresented: Binding(
                get: { model.jobsError != nil },
                set: { newValue in
                    if !newValue { model.jobsError = nil }
                }
            ),
            presenting: model.jobsError
        ) { _ in
            Button("OK", role: .cancel) { model.jobsError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                model.addFolder(url: url)
            }
        case .failure(let error):
            print("Error selecting folder: \(error.localizedDescription)")
        }
    }
}

// MARK: - Queue Sheet Wrapper

struct QueueSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            // Sheet header
            HStack {
                Text("Processing Queue")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                if let status = model.queueStatus {
                    Button {
                        Task { await model.toggleQueuePause() }
                    } label: {
                        Label(
                            status.manuallyPaused ? "Resume" : "Pause",
                            systemImage: status.manuallyPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            QueueContentView()
        }
    }
}

// MARK: - Loading View

struct LoadingFoldersView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .frame(maxWidth: 32)
                .frame(height: 32)
                .padding(.bottom, 4)
            Text("Syncing with backend...")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Missing Endpoint Banner

struct MissingEndpointBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text("Backend needs GET /api/watched-directories to show existing folders.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(12)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Empty State

struct EmptyFoldersView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.quaternary)

            Text("No Folders Being Watched")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Add folders to start indexing and searching your files")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FoldersView()
        .environment(AppModel())
        .frame(width: 900, height: 700)
}
