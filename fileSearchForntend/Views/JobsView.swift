//
//  JobsView.swift
//  fileSearchForntend
//
//  Manages watched folders and displays indexing progress
//  Redesigned for macOS 26 with compact layout
//

import SwiftUI
import UniformTypeIdentifiers

struct JobsView: View {
    @Environment(AppModel.self) private var model
    @State private var showFolderPicker = false

    var body: some View {
        @Bindable var model = model
        
        VStack(spacing: 0) {
            // Header with Add Folder button
            HStack {
                Text("Watched Folders")
                    .font(.system(size: 22, weight: .semibold))
                
                ConnectionStatusView(state: model.backendConnectionState)
                    .padding(.leading, 12)

                Spacer()
                
                Button {
                    Task {
                        await model.refreshWatchedFolders()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Refresh from backend")
                
                if model.isLoadingWatchedFolders {
                    ProgressView()
                        .frame(width: 16, height: 16)
                        .controlSize(.small)
                        .padding(.horizontal, 6)
                }

                Button(action: {
                    showFolderPicker = true
                }) {
                    Label("Add Folder", systemImage: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Jobs")
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

// MARK: - Connection Status

struct ConnectionStatusView: View {
    let state: AppModel.BackendConnectionState
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(state.statusDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.2), in: Capsule())
    }
    
    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .error:
            return .red
        case .idle:
            return .gray
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
    JobsView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}
