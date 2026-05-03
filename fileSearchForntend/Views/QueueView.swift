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
            // Top bar: text tabs on the left, pause button pinned right.
            HStack(spacing: 22) {
                ForEach(QueueTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(
                                size: 15,
                                weight: selectedTab == tab ? .bold : .regular
                            ))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            // Fixed width per tab so switching weight doesn't
                            // reflow the layout. Sized just past "Current" at
                            // 15pt bold so the underline hugs the label.
                            .frame(width: 64)
                            .padding(.bottom, 6)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(selectedTab == tab ? Color.primary : .clear)
                                    .frame(height: 2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Group chip + pause button so they share a tight spacing
                // (8pt) instead of the wide 22pt gap between tab labels.
                HStack(spacing: 8) {
                    if let status = model.queueStatus, status.schedulerPaused {
                        SchedulerWarningChip(failingRules: status.failingRules)
                    }
                    QueuePauseButton()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 11)

            // Status summary (only on current tab)
            if selectedTab == .current, let status = model.queueStatus {
                QueueStatusSummaryView(status: status)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }

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
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(sortedQueueItems) { item in
                        QueueItemRow(item: item) {
                            Task { await model.removeQueueItem(itemId: item.id) }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 14)
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
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(model.recentFiles) { file in
                        RecentFileRow(file: file)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 14)
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
                FailedTabHeader(files: model.failedFiles) {
                    // Fire reindex for each failed file. Keep them as
                    // separate tasks so one slow file doesn't serialize
                    // the rest; the backend queue handles concurrency.
                    let paths = model.failedFiles.map { $0.filePath }
                    for path in paths {
                        Task { await model.reindexFile(filePath: path) }
                    }
                }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(model.failedFiles) { file in
                            FailedFileRow(file: file) {
                                Task { await model.reindexFile(filePath: file.filePath) }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
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
        if status.totalItems > 0 {
            HStack(spacing: 16) {
                // Cooldown is a backend-only debounce after a file changes.
                // We intentionally don't surface it in the UI — it confused
                // users into thinking indexing was stuck. Cooling-down files
                // are folded into "Waiting" from the user's perspective.
                QueueCountPill(label: "Total", count: status.totalItems, color: .primary)
                QueueCountPill(label: "Waiting", count: status.waiting + status.coolingDown, color: .green)
                QueueCountPill(label: "Processing", count: status.processing, color: .orange)
                Spacer()
            }
        }
    }

    // Pause state is now surfaced entirely by the pause button (color +
    // icon) and the scheduler warning chip next to it — the large banner
    // that used to live here was redundant and crowded the popover.
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

            // Status pill. cooling_down is an internal debounce state that
            // confuses users (they see "Cooling Down" and think indexing
            // is stuck), so we display it as "Waiting" instead.
            Text(displayStatus)
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
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch item.status {
        case "cooling_down", "waiting": return .green
        case "processing": return .orange
        default: return .secondary
        }
    }

    private var displayStatus: String {
        item.status == "cooling_down"
            ? "Waiting"
            : item.status.replacingOccurrences(of: "_", with: " ").capitalized
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
        .padding(.vertical, 8)
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

            // Per-row "Share Error" was removed — the header's "Copy All
            // Errors" covers the reporting case, and most users just want
            // Reindex here. Context menu still offers per-file copy for the
            // rare case where someone wants a single file's report.

            Button(action: onReindex) {
                Label("Reindex", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
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
    let onRetryAll: () -> Void
    @State private var didCopy = false
    @State private var didRetry = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(files.count) failed \(files.count == 1 ? "file" : "files")")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            // Retry all — fires one reindex per failed file. Users asked
            // for this because the per-row Reindex button is tedious when
            // the failure was a one-off (backend down, transient I/O error)
            // and all 50+ files can be kicked at once.
            Button {
                onRetryAll()
                withAnimation(.easeInOut(duration: 0.2)) { didRetry = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeInOut(duration: 0.2)) { didRetry = false }
                }
            } label: {
                Label(didRetry ? "Retrying…" : "Retry All Failed",
                      systemImage: didRetry ? "checkmark" : "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(didRetry ? .green : .brandBlue)
            .help("Queue every failed file for reindexing")
            .disabled(files.isEmpty)

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

    private var manuallyPaused: Bool { model.queueStatus?.manuallyPaused == true }
    private var schedulerPaused: Bool { model.queueStatus?.schedulerPaused == true }
    /// Authoritative "is the queue actually paused" — uses the backend's
    /// computed `paused` field (which already accounts for the user
    /// override on top of scheduler + bootstrap), not the per-flag OR
    /// of `manually_paused || scheduler_paused`. With the v0.8.8
    /// override semantics, those two flags can both be false while the
    /// queue is running because of an override=True nudge, or both
    /// false while the queue is paused via override=False. Trusting the
    /// backend's combined `paused` keeps the button label honest.
    private var isPaused: Bool { model.queueStatus?.paused == true }
    /// One-shot override state from the backend.
    ///   nil    → no override, scheduler/manual flags reflect reality
    ///   true   → user nudged "run now" (overrides scheduler pause)
    ///   false  → user nudged "pause now" (overrides scheduler run)
    private var userOverride: Bool? { model.queueStatus?.userOverride }

    /// Scheduler-paused wins over manual pause for color, because the
    /// scheduler is the more informative state (it tells the user *why*
    /// indexing isn't running right now, which manual pause doesn't).
    private var tint: Color? {
        // Override → scheduler-pause: "running because the user said so" → no special tint
        if userOverride == true && schedulerPaused { return nil }
        if schedulerPaused { return .orange }
        if manuallyPaused { return .brandBlue }
        return nil
    }

    private var schedulerReason: String {
        let labels = (model.queueStatus?.failingRules ?? [])
            .compactMap { SchedulerRuleType(rawValue: $0)?.label.lowercased() }
        return labels.isEmpty ? "conditions not met" : labels.joined(separator: ", ")
    }

    private var helpText: String {
        // Override states get their own messages — they're the most
        // surprising case (the queue is in a state opposite to what the
        // scheduler/manual flags would suggest).
        if userOverride == true && schedulerPaused {
            return "Running by your override even though the scheduler would pause for \(schedulerReason). Click to pause. The override clears automatically once the scheduler conditions change."
        }
        if userOverride == false && !schedulerPaused {
            return "Paused by you. Click to start. The pause clears automatically once the scheduler conditions change."
        }
        switch (manuallyPaused, schedulerPaused) {
        case (true, true):
            return "Paused by you and by the scheduler (waiting on \(schedulerReason)). Click to start. You can modify the schedule in Settings › Indexing."
        case (true, false):
            return "Paused by you. Click to start."
        case (false, true):
            return "Paused by scheduler — waiting on \(schedulerReason). Click to start. You can modify the schedule in Settings › Indexing."
        case (false, false):
            return "Pause queue"
        }
    }

    var body: some View {
        Button {
            Task { await handleTap() }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPaused ? .white : .primary)
                .frame(width: 26, height: 26)
                .background {
                    Circle().fill(backgroundFill)
                }
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.2), value: manuallyPaused)
        .animation(.easeOut(duration: 0.2), value: schedulerPaused)
        .animation(.easeOut(duration: 0.2), value: userOverride)
    }

    /// Glyph reflects the *next action* the user will take by tapping:
    ///   - queue paused now (whether by manual, scheduler, or override) → play
    ///   - queue running now → pause
    /// This is more honest than "show pause when scheduler is the blocker
    /// even though clicking starts" — under the override semantics the
    /// click always flips the current state, so the icon always reflects
    /// the inverse.
    private var iconName: String {
        isPaused ? "play.fill" : "pause.fill"
    }

    /// Tap is a one-shot override toggle: whatever the queue is doing
    /// right now, the user wants the opposite, until the scheduler's
    /// next decision transition. Backend handles the override semantics
    /// (manual_pause / manual_resume route through `_user_override`),
    /// so the frontend just needs to call the existing pause/resume
    /// endpoints based on what's currently happening.
    private func handleTap() async {
        if isPaused {
            await model.forceResumeQueue()
        } else {
            await model.toggleQueuePause()
        }
    }

    private var backgroundFill: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint.opacity(isHovering ? 1.0 : 0.9))
        }
        return AnyShapeStyle(.quaternary.opacity(isHovering ? 0.45 : 0.25))
    }
}

// MARK: - Scheduler Warning Chip

/// Compact orange chip surfaced next to the pause button when the
/// scheduler is blocking indexing. Inline label names the single failing
/// rule (e.g., "Battery Level"); when multiple rules fail it collapses to
/// "N scheduling" so the chip stays compact. Click to see the full list.
/// Shown for the brief window after a search: the backend has
/// preempted the indexing queue so the embedder/LLM gets uncontended
/// hardware. Auto-clears (no action needed).
struct SearchPreemptChip: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Paused for search")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.15), in: Capsule())
        .help("Indexing is paused for a few seconds so search has uncontended GPU/CPU. Resumes automatically.")
    }
}


struct SchedulerWarningChip: View {
    let failingRules: [String]
    @State private var showDetails: Bool = false

    private var ruleLabels: [String] {
        failingRules.compactMap { SchedulerRuleType(rawValue: $0)?.label }
    }

    private var chipLabel: String {
        let labels = ruleLabels
        if labels.count >= 2 { return "\(labels.count) scheduling" }
        if let only = labels.first { return only }
        return "Scheduler paused"
    }

    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(chipLabel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Scheduler is holding indexing — click to see why")
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            SchedulerWarningDetails(failingRules: failingRules)
        }
    }
}

/// Popover body for `SchedulerWarningChip`: lists every failing rule by
/// its human label and reminds the user where to edit the schedule.
private struct SchedulerWarningDetails: View {
    let failingRules: [String]

    private var ruleLabels: [String] {
        failingRules.compactMap { SchedulerRuleType(rawValue: $0)?.label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Scheduler is holding indexing")
                    .font(.system(size: 13, weight: .semibold))
            }

            if ruleLabels.isEmpty {
                Text("Conditions for the current schedule aren't met.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Waiting on:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(ruleLabels, id: \.self) { label in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.orange)
                            Text(label)
                                .font(.system(size: 12))
                        }
                    }
                }
            }

            Divider()

            Text("Edit the schedule in Settings › Indexing.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(minWidth: 240, alignment: .leading)
    }
}

#Preview {
    QueueContentView()
        .environment(AppModel())
        .frame(width: 1000, height: 700)
}
