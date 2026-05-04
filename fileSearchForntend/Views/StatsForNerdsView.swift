//
//  StatsForNerdsView.swift
//  fileSearchForntend
//
//  Debug-detail panel reachable from a search result's right-click
//  menu. Surfaces the stuff that decides whether a file ranks well —
//  the LLM-written summary, extracted keywords, embedding presence,
//  pipeline status — so users can diagnose poor hits (especially on
//  images, where the vision-summary is the only signal the embedder
//  ever sees) without dropping into SQLite.
//

import SwiftUI
import AppKit

struct StatsForNerdsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let filePath: String

    @State private var details: FileDetailsResponse?
    @State private var loadError: String?
    @State private var isLoading: Bool = true
    /// Visual state for the in-flight Reindex button. `.idle` is the
    /// default; the button flips to `.queued` once the backend
    /// accepts the reindex request, to give the user instant
    /// feedback even though the actual re-processing is async.
    @State private var reindexState: ReindexState = .idle

    private enum ReindexState: Equatable {
        case idle
        case requesting
        case queued
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading {
                        loadingState
                    } else if let loadError {
                        errorState(loadError)
                    } else if let details {
                        if details.found {
                            content(details)
                        } else {
                            notIndexedState
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 540)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.brandBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stats for Nerds")
                    .font(.system(size: 14, weight: .semibold))
                Text((filePath as NSString).lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            reindexButton
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Triggers a backend `/api/queue/reindex` for this file: deletes
    /// the existing DB row and re-enqueues the path. Useful when
    /// iterating on parser/summarizer logic — no need to clear the
    /// whole watched folder or restart the backend.
    private var reindexButton: some View {
        let label: String
        let icon: String
        let disabled: Bool
        switch reindexState {
        case .idle:
            label = "Reindex"
            icon = "arrow.counterclockwise"
            disabled = false
        case .requesting:
            label = "Queuing…"
            icon = "arrow.counterclockwise"
            disabled = true
        case .queued:
            label = "Queued"
            icon = "checkmark.circle"
            disabled = true
        case .failed:
            label = "Retry"
            icon = "exclamationmark.triangle"
            disabled = false
        }
        return Button {
            Task { await reindex() }
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(disabled)
        .help(reindexHelpText)
    }

    private var reindexHelpText: String {
        switch reindexState {
        case .idle:
            return "Delete this file's DB row and re-enqueue it for processing."
        case .requesting:
            return "Sending reindex request to the backend…"
        case .queued:
            return "Reindex queued. Watch the queue for updates."
        case .failed(let msg):
            return "Reindex failed: \(msg)"
        }
    }

    private func reindex() async {
        reindexState = .requesting
        do {
            let response = try await model.apiClient.reindexFile(filePath: filePath)
            if response.success {
                reindexState = .queued
                // Auto-reset to idle after a short delay so the user
                // can hit it again without dismissing the panel.
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if case .queued = reindexState {
                        reindexState = .idle
                    }
                }
                // Refresh details after the backend has had a moment
                // to drop the old row + enqueue the new one.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    await load()
                }
            } else {
                reindexState = .failed(response.message)
            }
        } catch {
            reindexState = .failed(error.localizedDescription)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text("Couldn't load file details")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await load() }
            }
            .controlSize(.small)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var notIndexedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Not in the index yet")
                .font(.system(size: 13, weight: .semibold))
            Text("This file is in your search results but the database doesn't have a record for it. Most likely it was just discovered and hasn't been parsed yet, or it lives outside any watched folder.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ d: FileDetailsResponse) -> some View {
        statusSection(d)
        summarySection(d)
        keywordsSection(d)
        embeddingSection(d)
        identitySection(d)
        timelineSection(d)
        rawJSONSection(d)
    }

    // MARK: Sections

    private func statusSection(_ d: FileDetailsResponse) -> some View {
        sectionCard(title: "Pipeline status", systemImage: "flowchart.fill") {
            HStack(spacing: 8) {
                statusPill(d.status ?? "—")
                if let err = d.processingError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private func summarySection(_ d: FileDetailsResponse) -> some View {
        sectionCard(title: "LLM summary", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 6) {
                if let title = d.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
                if let s = d.summary, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    placeholder("No summary yet — the summarizer either hasn't reached this file or returned empty.")
                }
            }
        }
    }

    private func keywordsSection(_ d: FileDetailsResponse) -> some View {
        sectionCard(title: "Keywords (\(d.keywords.count))", systemImage: "tag.fill") {
            if d.keywords.isEmpty {
                placeholder("No keywords extracted. For images this usually means the vision summary was empty or the LLM returned malformed JSON.")
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(d.keywords, id: \.self) { kw in
                        Text(kw)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.brandBlue.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.brandBlue)
                    }
                }
            }
        }
    }

    private func embeddingSection(_ d: FileDetailsResponse) -> some View {
        sectionCard(title: "Embedding", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: d.hasEmbedding ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(d.hasEmbedding ? .green : .red)
                    Text(d.hasEmbedding ? "Stored in vec0" : "Missing — file won't appear in semantic search")
                        .font(.system(size: 12))
                }
                if let model = d.embeddingModel {
                    keyValue("Model", model)
                }
                if let dims = d.embeddingDimensions {
                    keyValue("Dimensions", String(dims))
                }
            }
        }
    }

    private func identitySection(_ d: FileDetailsResponse) -> some View {
        sectionCard(title: "Identity", systemImage: "doc.text.fill") {
            VStack(alignment: .leading, spacing: 3) {
                keyValue("Path", d.filePath, monospaced: true, selectable: true)
                if let id = d.fileId { keyValue("DB id", String(id)) }
                if let ext = d.fileExtension, !ext.isEmpty { keyValue("Extension", ext) }
                if let ct = d.contentType, !ct.isEmpty { keyValue("Content-Type", ct, monospaced: true) }
                if let size = d.fileSize { keyValue("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
                if let hash = d.contentHash, !hash.isEmpty { keyValue("Content hash", hash, monospaced: true, selectable: true) }
                if let owner = d.owner, !owner.isEmpty { keyValue("Owner", owner) }
                if let perms = d.permissions, !perms.isEmpty { keyValue("Permissions", perms, monospaced: true) }
            }
        }
    }

    private func timelineSection(_ d: FileDetailsResponse) -> some View {
        sectionCard(title: "Timeline", systemImage: "clock.fill") {
            VStack(alignment: .leading, spacing: 3) {
                timeRow("File created", d.created)
                timeRow("File modified", d.modified)
                timeRow("File accessed", d.accessed)
                timeRow("Parsed", d.parsedAt)
                timeRow("Summarized", d.summarizedAt)
                timeRow("Embedded", d.embeddedAt)
                timeRow("DB created", d.createdAt)
                timeRow("DB updated", d.updatedAt)
            }
        }
    }

    private func rawJSONSection(_ d: FileDetailsResponse) -> some View {
        // Lets advanced users copy-paste the whole record into an
        // issue / chat without us having to enumerate every field.
        let json = (try? jsonString(d)) ?? "<encoding error>"
        return sectionCard(title: "Raw response", systemImage: "curlybraces") {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    Text(json)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(json, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Building blocks

    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func keyValue(
        _ key: String,
        _ value: String,
        monospaced: Bool = false,
        selectable: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Group {
                if selectable {
                    Text(value)
                        .textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(.system(size: 12, design: monospaced ? .monospaced : .default))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func timeRow(_ label: String, _ epochSeconds: Int?) -> some View {
        keyValue(label, formatTimestamp(epochSeconds))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .italic()
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func statusPill(_ status: String) -> some View {
        let color: Color = {
            switch status.uppercased() {
            case "COMPLETE": return .green
            case "INDEXED_PARTIAL": return .orange
            case "FAILED": return .red
            case "DISCOVERED", "PARSED", "SUMMARIZED": return .brandBlue
            default: return .gray
            }
        }()
        // Friendlier label for the new partial status.
        let label = status.uppercased() == "INDEXED_PARTIAL"
            ? "PARTIAL"
            : status
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ epochSeconds: Int?) -> String {
        guard let s = epochSeconds, s > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(s))
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private func jsonString(_ d: FileDetailsResponse) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(d)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            details = try await model.apiClient.fetchFileDetails(path: filePath)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// FlowLayout (wrapping HStack used for the keywords cloud) lives in
// Views/Settings/FileFilterSection.swift — reused here as-is.
