//
//  JobsView.swift
//  fileSearchForntend
//
//  Manages watched folders and displays indexing progress
//  Includes merged Queue (Processing) tab via segmented picker
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Folders Tab Enum

enum FoldersTab: String, CaseIterable, Identifiable {
    case folders = "Folders"
    case processing = "Processing"

    var id: String { rawValue }
}

struct FoldersView: View {
    @Environment(AppModel.self) private var model
    @State private var showFolderPicker = false
    @State private var selectedTab: FoldersTab = .folders

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Folders")
                    .font(.system(size: 22, weight: .semibold))

                Spacer()

                Button {
                    Task {
                        if selectedTab == .folders {
                            await model.refreshWatchedFolders()
                        } else {
                            await model.refreshQueueStatus()
                            await model.refreshQueueItems()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Refresh")

                if model.isLoadingWatchedFolders || model.isLoadingQueue {
                    ProgressView()
                        .frame(width: 16, height: 16)
                        .controlSize(.small)
                        .padding(.horizontal, 6)
                }

                if selectedTab == .folders {
                    Button(action: {
                        showFolderPicker = true
                    }) {
                        Label("Add Folder", systemImage: "plus")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if selectedTab == .processing, let status = model.queueStatus {
                    Button {
                        Task { await model.toggleQueuePause() }
                    } label: {
                        Label(
                            status.manuallyPaused ? "Resume" : "Pause",
                            systemImage: status.manuallyPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            // Segmented picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(FoldersTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)
            .padding(.bottom, 12)

            if selectedTab == .folders {
                if model.missingWatchedEndpoint {
                    MissingEndpointBanner()
                        .padding(.horizontal, 32)
                }

                Divider()

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
            } else {
                QueueContentView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Folders")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(.ultraThinMaterial)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
        .alert(
            "Backend",
            isPresented: Binding(
                get: { model.jobsError != nil },
                set: { newValue in
                    if !newValue {
                        model.jobsError = nil
                    }
                }
            ),
            presenting: model.jobsError
        ) { _ in
            Button("OK", role: .cancel) {
                model.jobsError = nil
            }
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

// MARK: - Loading View

struct LoadingFoldersView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .frame(maxWidth: 32)
                .frame(height: 32)
                .padding(.bottom, 4)
            Text("Syncing with backend…")
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
        .frame(width: 1000, height: 700)
}
