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
        VStack(spacing: 0) {
            // Header with Add Folder button
            HStack {
                Text("Watched Folders")
                    .font(.system(size: 22, weight: .semibold))

                Spacer()

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

            Divider()

            // Folder list or empty state
            if model.watchedFolders.isEmpty {
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
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
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
