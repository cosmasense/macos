//
//  FolderRowView.swift
//  fileSearchForntend
//
//  Individual row displaying a watched folder with progress
//  Redesigned with compact horizontal layout and Liquid Glass material
//

import SwiftUI

struct FolderRowView: View {
    @Environment(AppModel.self) private var model
    let folder: WatchedFolder
    @State private var showDeleteConfirmation = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            // Folder icon
            Image(systemName: "folder.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
                .frame(width: 40)

            // Folder info (compact)
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(folder.path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 20)

            // Progress indicator (more compact)
            ProgressIndicatorView(folder: folder)

            // Remove button
            Button(role: .destructive, action: {
                showDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                    .foregroundStyle(.red.opacity(isHovered ? 1.0 : 0.7))
            }
            .buttonStyle(.plain)
            .help("Remove folder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .confirmationDialog(
            "Remove \(folder.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                withAnimation {
                    model.removeFolder(folder)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop indexing and remove this folder from your watched list.")
        }
    }
}

// MARK: - Progress Indicator

struct ProgressIndicatorView: View {
    let folder: WatchedFolder

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(.quaternary.opacity(0.4), lineWidth: 2.5)
                .frame(width: 50, height: 50)

            // Progress circle
            Circle()
                .trim(from: 0, to: folder.progress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: folder.progress)

            // Status icon or percentage
            Group {
                if folder.status == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: folder.status)
                } else if folder.status == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                } else if folder.status == .paused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                } else {
                    Text("\(Int(folder.progress * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 50, height: 50)
    }

    private var progressColor: Color {
        switch folder.status {
        case .complete:
            return .green
        case .error:
            return .red
        case .paused:
            return .orange
        case .indexing:
            return .blue
        case .idle:
            return .gray
        }
    }
}

#Preview {
    VStack(spacing: 14) {
        FolderRowView(
            folder: WatchedFolder(
                name: "Documents",
                path: "/Users/you/Documents",
                progress: 0.42,
                status: .indexing
            )
        )

        FolderRowView(
            folder: WatchedFolder(
                name: "Photos",
                path: "/Users/you/Pictures/Photos",
                progress: 1.0,
                status: .complete
            )
        )
    }
    .padding()
    .environment(AppModel())
    .frame(width: 800)
}
