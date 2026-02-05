//
//  QueueView.swift
//  fileSearchForntend
//
//  Queue management view: status summary, pause/resume, item list
//  Three tabs: Current | Recent | Failed
//

import SwiftUI

enum QueueTab: String, CaseIterable, Identifiable {
    case current = "Current"
    case recent = "Recent"
    case failed = "Failed"

    var id: String { rawValue }
}

struct QueueView: View {
    @Environment(AppModel.self) private var model
    @State private var pollingTask: Task<Void, Never>?
    @State private var selectedTab: QueueTab = .current

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Queue")
                    .font(.system(size: 22, weight: .semibold))

                Spacer()

                if model.isLoadingQueue {
                    ProgressView()
                        .frame(width: 16, height: 16)
                        .controlSize(.small)
                        .padding(.horizontal, 6)
                }

                Button {
                    Task {
                        await refreshCurrentTab()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Refresh")

                if selectedTab == .current, let status = model.queueStatus {
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

            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(QueueTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)
            .padding(.bottom, 12)

            // Status summary (only on current tab)
            if selectedTab == .current, let status = model.queueStatus {
                QueueStatusSummaryView(status: status)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)
            }

            Divider()

            // Tab content
            switch selectedTab {
            case .current:
                currentTabContent
            case .recent:
                recentTabContent
            case .failed:
                failedTabContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Queue")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(.ultraThinMaterial)
        .task {
            await model.refreshQueueStatus()
            await model.refreshQueueItems()
            startPolling()
        }
        .onChange(of: selectedTab) { _, newTab in
            pollingTask?.cancel()
            Task {
                switch newTab {
                case .current:
                    await model.refreshQueueStatus()
                    await model.refreshQueueItems()
                    startPolling()
                case .recent:
                    await model.refreshRecentFiles()
                case .failed:
                    await model.refreshFailedFiles()
                }
            }
        }
        .onDisappear {
            pollingTask?.cancel()
        }
        .alert(
            "Queue Error",
            isPresented: Binding(
                get: { model.queueError != nil },
                set: { if !$0 { model.queueError = nil } }
            ),
            presenting: model.queueError
        ) { _ in
            Button("OK", role: .cancel) { model.queueError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Current Tab

    @ViewBuilder
    private var currentTabContent: some View {
        if model.queueItems.isEmpty && !model.isLoadingQueue {
            VStack(spacing: 18) {
                Image(systemName: "tray")
                    .font(.system(size: 56))
                    .foregroundStyle(.quaternary)

                Text("Queue is Empty")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Files will appear here when they are queued for indexing")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.queueItems) { item in
                        QueueItemRow(item: item) {
                            Task { await model.removeQueueItem(itemId: item.id) }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
    }

    // MARK: - Recent Tab

    @ViewBuilder
    private var recentTabContent: some View {
        if model.recentFiles.isEmpty {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.quaternary)

                Text("No Recent Files")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Successfully processed files will appear here")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.recentFiles) { file in
                        RecentFileRow(file: file)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
    }

    // MARK: - Failed Tab

    @ViewBuilder
    private var failedTabContent: some View {
        if model.failedFiles.isEmpty {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 56))
                    .foregroundStyle(.quaternary)

                Text("No Failed Files")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Files that fail processing will appear here with an option to retry")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.failedFiles) { file in
                        FailedFileRow(file: file) {
                            Task { await model.reindexFile(filePath: file.filePath) }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
    }

    // MARK: - Helpers

    private func refreshCurrentTab() async {
        switch selectedTab {
        case .current:
            await model.refreshQueueStatus()
            await model.refreshQueueItems()
        case .recent:
            await model.refreshRecentFiles()
        case .failed:
            await model.refreshFailedFiles()
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await model.refreshQueueStatus()
                await model.refreshQueueItems()
            }
        }
    }
}

// MARK: - Status Summary

struct QueueStatusSummaryView: View {
    let status: QueueStatusResponse

    var body: some View {
        HStack(spacing: 16) {
            QueueCountPill(label: "Total", count: status.totalItems, color: .primary)
            QueueCountPill(label: "Cooling Down", count: status.coolingDown, color: .blue)
            QueueCountPill(label: "Waiting", count: status.waiting, color: .green)
            QueueCountPill(label: "Processing", count: status.processing, color: .orange)

            Spacer()

            if status.paused {
                HStack(spacing: 4) {
                    Image(systemName: "pause.circle.fill")
                    Text(status.schedulerPaused ? "Scheduler Paused" : "Paused")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.15), in: Capsule())
            }
        }
    }
}

struct QueueCountPill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.2), in: Capsule())
    }
}

// MARK: - Queue Item Row

struct QueueItemRow: View {
    let item: QueueItemResponse
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(systemName: "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: item.filePath).lastPathComponent)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Text(item.filePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Action badge
            Text(item.action.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(actionColor, in: Capsule())

            // Status pill
            Text(item.status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15), in: Capsule())

            // Retry count
            if item.retryCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text("\(item.retryCount)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.orange)
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from queue")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var actionColor: Color {
        switch item.action {
        case "index": return .blue
        case "delete": return .red
        case "move": return .purple
        case "embed_fallback": return .orange
        default: return .gray
        }
    }

    private var statusColor: Color {
        switch item.status {
        case "cooling_down": return .blue
        case "waiting": return .green
        case "processing": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Recent File Row

struct RecentFileRow: View {
    let file: ProcessedFileItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Text(file.filePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let ts = file.updatedAt {
                Text(relativeTime(from: ts))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func relativeTime(from timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Failed File Row

struct FailedFileRow: View {
    let file: ProcessedFileItem
    let onReindex: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Text(file.filePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if let error = file.processingError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onReindex) {
                Label("Reindex", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    QueueView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}
