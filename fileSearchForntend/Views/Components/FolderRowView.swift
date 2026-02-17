//
//  FolderRowView.swift
//  fileSearchForntend
//
//  Individual row displaying a watched folder with progress
//  Ultra-compact layout with path following name, absolute timestamp, App Store-style progress
//

import SwiftUI
import AppKit

struct FolderRowView: View {
    @Environment(AppModel.self) private var model
    let folder: WatchedFolder
    @State private var showDeleteConfirmation = false
    @State private var isHovered = false
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                // Folder icon
                Image(systemName: "folder.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.blue)
                    .frame(width: 38)

                // Folder name + path stacked for better readability
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(folder.path)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                // Last Modified (absolute time format)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Text(formatLastModified(folder.lastModified))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.2), in: Capsule())
            
                StatusPill(folder: folder)

                // Progress indicator (App Store style)
                ProgressIndicatorView(folder: folder)
                    .padding(.leading, 2)
            
                Button {
                    model.reindex(folder: folder)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Re-index now")
                .disabled(folder.status == .indexing)

                // Remove button
                Button(role: .destructive, action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(isHovered ? 1.0 : 0.7))
                }
                .buttonStyle(.plain)
                .help("Remove folder")
            }

            if folder.lastIssueMessage != nil {
                FolderIssueBanner(folder: folder)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
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
                model.removeFolder(folder)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop indexing and remove this folder from your watched list.")
        }
        .onTapGesture {
            showingDetails = true
        }
        .onTapGesture(count: 2) {
            openInFinder()
        }
        .contextMenu {
            Button("Show in Finder") {
                openInFinder()
            }
        }
        .popover(isPresented: $showingDetails, arrowEdge: .leading) {
            FolderDetailView(folder: folder) {
                showingDetails = false
            }
            .frame(width: 320)
            .padding()
        }
    }

    // MARK: - Timestamp Formatting

    private func formatLastModified(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        // Check if it's today
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today \(formatter.string(from: date))"
        }

        // Check if it's yesterday
        if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Yesterday \(formatter.string(from: date))"
        }

        // Check if it's within this year
        let dateComponents = calendar.dateComponents([.year], from: date, to: now)
        if dateComponents.year == 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, HH:mm"
            return formatter.string(from: date)
        }

        // More than a year ago
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

private extension FolderRowView {
    func openInFinder() {
        let url = URL(fileURLWithPath: folder.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct FolderDetailView: View {
    let folder: WatchedFolder
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(folder.name)
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Close") {
                    onClose()
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(folder.path, systemImage: "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Label(folder.status.rawValue.capitalized, systemImage: "bolt.circle")
                    Spacer()
                    Label(format(date: folder.lastModified), systemImage: "clock")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                ProgressView(value: folder.progress)
                    .progressViewStyle(.linear)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Job Details")
                    .font(.system(size: 13, weight: .semibold))
                detailRow(title: "Backend ID", value: folder.backendID.map(String.init) ?? "–")
                detailRow(title: "Recursive", value: folder.recursive ? "Yes" : "No")
                detailRow(title: "File pattern", value: folder.filePattern ?? "Any")
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
        }
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Progress Indicator (App Store Style)

struct ProgressIndicatorView: View {
    let folder: WatchedFolder

    var body: some View {
        ZStack {
            if folder.status == .complete {
                // Just show green checkmark when complete
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: folder.status)
            } else {
                // Show circular progress indicator (App Store style)
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(.quaternary.opacity(0.3), lineWidth: 2)
                        .frame(width: 28, height: 28)

                    // Progress circle
                    Circle()
                        .trim(from: 0, to: folder.progress)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: folder.progress)

                    // Small percentage text or icon
                    if folder.status == .error {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.red)
                    } else if folder.lastIssueMessage != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                    } else if folder.status == .paused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(Int(folder.progress * 100))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 28, height: 28)
    }

    private var progressColor: Color {
        if folder.status == .complete {
            return .green
        }
        if folder.status == .error {
            return .red
        }
        if folder.lastIssueMessage != nil || folder.status == .paused {
            return .orange
        }
        if folder.status == .indexing {
            return .blue
        }
        return .gray
    }
}

struct StatusPill: View {
    let folder: WatchedFolder

    private var status: IndexStatus { folder.status }
    
    var body: some View {
        Text(statusLabel)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(statusTextColor)
            .background(statusColor.opacity(0.15), in: Capsule())
    }
    
    private var statusLabel: String {
        if folder.lastIssueMessage != nil {
            return "Continuing (skipping)"
        }
        switch status {
        case .idle:
            return "Idle"
        case .indexing:
            return "Indexing"
        case .paused:
            return "Paused"
        case .error:
            return "Error"
        case .complete:
            return "Complete"
        }
    }
    
    private var statusColor: Color {
        if folder.lastIssueMessage != nil {
            return .orange
        }
        switch status {
        case .idle:
            return .gray
        case .indexing:
            return .blue
        case .paused:
            return .orange
        case .error:
            return .red
        case .complete:
            return .green
        }
    }
    
    private var statusTextColor: Color {
        if folder.lastIssueMessage != nil {
            return .orange
        }
        return status == .idle ? .secondary : .primary
    }
}

private struct FolderIssueBanner: View {
    @Environment(AppModel.self) private var model
    let folder: WatchedFolder

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.lastIssueMessage ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                if let timestamp = folder.lastIssueDate {
                    Text(Self.relativeFormatter.localizedString(for: timestamp, relativeTo: Date()))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Text(issueSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Dismiss") {
                model.dismissFolderIssue(folder)
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.borderless)
            .foregroundStyle(.primary.opacity(0.7))
            .padding(.top, 2)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var issueSubtitle: String {
        let count = max(1, folder.skippedFileCount)
        if count == 1 {
            return "Skipped 1 file, continuing indexing…"
        }
        return "Skipped \(count) files so far, continuing indexing…"
    }
}

#Preview {
    VStack(spacing: 12) {
        FolderRowView(
            folder: WatchedFolder(
                name: "Documents",
                path: "/Users/you/Documents",
                progress: 0.42,
                status: .indexing,
                lastModified: Date() // Today
            )
        )

        FolderRowView(
            folder: WatchedFolder(
                name: "Photos",
                path: "/Users/you/Pictures/Photos",
                progress: 1.0,
                status: .complete,
                lastModified: Date().addingTimeInterval(-86400) // Yesterday
            )
        )

        FolderRowView(
            folder: WatchedFolder(
                name: "Downloads",
                path: "/Users/you/Downloads",
                progress: 0.75,
                status: .indexing,
                lastModified: Date().addingTimeInterval(-86400 * 30) // Last month
            )
        )

        FolderRowView(
            folder: WatchedFolder(
                name: "Manuals",
                path: "/Users/you/Documents/Manuals",
                progress: 0.33,
                status: .indexing,
                lastModified: Date(),
                lastIssueMessage: "Unsupported file format (.pkg)",
                lastIssueDate: Date().addingTimeInterval(-300),
                skippedFileCount: 2
            )
        )
    }
    .padding()
    .environment(AppModel())
    .frame(width: 800)
}
