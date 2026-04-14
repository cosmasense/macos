//
//  QueueView.swift
//  fileSearchForntend
//
//  Queue content view: status summary, pause/resume, item list
//  Embedded inside FoldersView as the "Processing" tab.
//  Three sub-tabs: Current | Recent | Failed
//

import SwiftUI

enum QueueTab: String, CaseIterable, Identifiable {
    case current = "Current"
    case recent = "Recent"
    case failed = "Failed"

    var id: String { rawValue }
}

/// Self-contained queue view that manages its own polling lifecycle.
/// Used as embedded content in FoldersView's "Processing" tab.
struct QueueContentView: View {
    @Environment(AppModel.self) private var model
    @State private var pollingTask: Task<Void, Never>?
    @State private var selectedTab: QueueTab = .current

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: tabs + pause button
            HStack(spacing: 10) {
                Picker("Queue Tab", selection: $selectedTab) {
                    ForEach(QueueTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                QueuePauseButton()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Status summary (only on current tab)
            if selectedTab == .current, let status = model.queueStatus {
                QueueStatusSummaryView(status: status)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
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
        .task {
            await model.refreshQueueStatus()
            await model.refreshQueueItems()
            startPolling(for: .current)
        }
        .onChange(of: selectedTab) { _, newTab in
            pollingTask?.cancel()
            Task {
                switch newTab {
                case .current:
                    await model.refreshQueueStatus()
                    await model.refreshQueueItems()
                case .recent:
                    await model.refreshRecentFiles()
                case .failed:
                    await model.refreshFailedFiles()
                }
                startPolling(for: newTab)
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
                LazyVStack(spacing: 6) {
                    ForEach(sortedQueueItems) { item in
                        QueueItemRow(item: item) {
                            Task { await model.removeQueueItem(itemId: item.id) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
    }

    /// Current queue ordered for visibility: things that are actively running
    /// bubble to the top, cooling_down (debounce window after a file change)
    /// sinks to the bottom.
    private var sortedQueueItems: [QueueItemResponse] {
        func rank(_ status: String) -> Int {
            switch status {
            case "processing":   return 0
            case "waiting":      return 1
            case "cooling_down": return 2
            default:             return 3
            }
        }
        return model.queueItems.sorted { a, b in
            let ra = rank(a.status), rb = rank(b.status)
            if ra != rb { return ra < rb }
            // Stable tiebreaker by filename so the order doesn't jump around
            return a.filePath < b.filePath
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
                LazyVStack(spacing: 6) {
                    ForEach(model.recentFiles) { file in
                        RecentFileRow(file: file)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
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
            VStack(spacing: 0) {
                FailedTabHeader(files: model.failedFiles)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.failedFiles) { file in
                            FailedFileRow(file: file) {
                                Task { await model.reindexFile(filePath: file.filePath) }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func startPolling(for tab: QueueTab) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                // Recent/Failed can poll slower — they only change on file
                // completion, not on per-stage progress ticks.
                let delay: Duration = tab == .current ? .seconds(2) : .seconds(5)
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { break }
                switch tab {
                case .current:
                    await model.refreshQueueStatus()
                    await model.refreshQueueItems()
                case .recent:
                    await model.refreshRecentFiles()
                case .failed:
                    await model.refreshFailedFiles()
                }
            }
        }
    }
}

// MARK: - Status Summary

struct QueueStatusSummaryView: View {
    @Environment(AppModel.self) private var model
    let status: QueueStatusResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                QueueCountPill(label: "Total", count: status.totalItems, color: .primary)
                QueueCountPill(label: "Cooling Down", count: status.coolingDown, color: .brandBlue)
                QueueCountPill(label: "Waiting", count: status.waiting, color: .green)
                QueueCountPill(label: "Processing", count: status.processing, color: .orange)
                Spacer()
            }

            if status.paused {
                HStack(spacing: 8) {
                    Image(systemName: pauseIcon)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pauseTitle)
                            .font(.system(size: 13, weight: .semibold))
                        if !pauseReason.isEmpty {
                            Text(pauseReason)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .foregroundStyle(pauseBannerColor)
                .padding(10)
                .background(pauseBannerColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var pauseIcon: String {
        if status.schedulerPaused {
            return "calendar.badge.clock"
        }
        return "pause.circle.fill"
    }

    private var pauseBannerColor: Color {
        status.schedulerPaused ? .orange : .yellow
    }

    private var pauseTitle: String {
        if status.manuallyPaused && status.schedulerPaused {
            return "Paused by user and scheduler"
        } else if status.schedulerPaused {
            return "Paused by scheduler"
        } else {
            return "Paused by user"
        }
    }

    private var pauseReason: String {
        if status.schedulerPaused {
            let labels = status.failingRules.compactMap { SchedulerRuleType(rawValue: $0)?.label }
            if !labels.isEmpty {
                return "Failing: " + labels.joined(separator: ", ")
            }
            return "Scheduler conditions not met"
        }
        return ""
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

    private var statusColor: Color {
        switch item.status {
        case "cooling_down": return .brandBlue
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
    @State private var didCopy = false

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

            // Share Error — copies a debuggable report to the clipboard
            Button {
                copyErrorReport()
            } label: {
                Label(didCopy ? "Copied" : "Share Error",
                      systemImage: didCopy ? "checkmark" : "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(didCopy ? .green : .brandBlue)
            .help("Copy error details to clipboard for debugging")

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
        .contextMenu {
            Button("Copy Error Report") { copyErrorReport() }
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.filePath, forType: .string)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.filePath)])
            }
        }
    }

    private func copyErrorReport() {
        let report = Self.buildErrorReport(for: file)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
        }
    }

    /// Multi-line error report suitable for pasting into a bug report.
    static func buildErrorReport(for file: ProcessedFileItem) -> String {
        let fm = FileManager.default
        let fileExists = fm.fileExists(atPath: file.filePath)
        var size: Int64 = 0
        if let attrs = try? fm.attributesOfItem(atPath: file.filePath),
           let s = attrs[.size] as? Int64 {
            size = s
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return """
        SAIL — Failed File Error Report
        ================================
        Timestamp:   \(timestamp)
        App version: \(appVersion) (build \(appBuild))

        File
        ----
        Name:       \(file.filename)
        Path:       \(file.filePath)
        Extension:  \(file.fileExtension)
        Exists:     \(fileExists ? "yes" : "NO (removed?)")
        Size:       \(size) bytes
        Status:     \(file.status)
        Updated At: \(file.updatedAt.map { String($0) } ?? "—")

        Error
        -----
        \(file.processingError ?? "(no error message)")
        """
    }
}

// MARK: - Failed Tab Header

/// Header row for the Failed tab: file count + a single "Copy All Errors"
/// button that bundles every failed file into one clipboard payload.
struct FailedTabHeader: View {
    let files: [ProcessedFileItem]
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(files.count) failed \(files.count == 1 ? "file" : "files")")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                copyAllErrors()
            } label: {
                Label(didCopy ? "Copied all" : "Copy All Errors",
                      systemImage: didCopy ? "checkmark" : "square.and.arrow.up.on.square")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(didCopy ? .green : .brandBlue)
            .help("Copy a combined error report for every failed file to the clipboard")
        }
    }

    private func copyAllErrors() {
        let combined = Self.buildCombinedReport(for: files)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
        }
    }

    /// Stitch every failed file into one multi-section clipboard payload.
    /// Header is shown once; individual file sections follow, separated by
    /// a visible divider so it stays readable when pasted into an email.
    static func buildCombinedReport(for files: [ProcessedFileItem]) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        var lines: [String] = []
        lines.append("SAIL — Combined Failed Files Report")
        lines.append(String(repeating: "=", count: 40))
        lines.append("Timestamp:   \(timestamp)")
        lines.append("App version: \(appVersion) (build \(appBuild))")
        lines.append("Total failed: \(files.count)")
        lines.append("")

        for (index, file) in files.enumerated() {
            lines.append("── [\(index + 1)/\(files.count)] ──────────────────────")
            lines.append("Name:       \(file.filename)")
            lines.append("Path:       \(file.filePath)")
            lines.append("Extension:  \(file.fileExtension)")
            lines.append("Status:     \(file.status)")
            if let ts = file.updatedAt {
                let date = Date(timeIntervalSince1970: TimeInterval(ts))
                lines.append("Updated:    \(ISO8601DateFormatter().string(from: date))")
            }
            lines.append("Error:      \(file.processingError ?? "(no error message)")")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Pause Button

struct QueuePauseButton: View {
    @Environment(AppModel.self) private var model
    @State private var isHovering = false

    private var isPaused: Bool { model.queueStatus?.manuallyPaused == true }

    var body: some View {
        Button {
            Task { await model.toggleQueuePause() }
        } label: {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPaused ? Color.brandBlue : .primary)
                .frame(width: 26, height: 26)
                .background(.quaternary.opacity(isHovering ? 0.45 : 0.25), in: Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isPaused ? "Resume queue" : "Pause queue")
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

#Preview {
    QueueContentView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}
