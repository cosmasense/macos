//
//  SearchResultsView.swift
//  fileSearchForntend
//
//  Displays search results with loading and error states
//

import SwiftUI
import AppKit
import QuickLookThumbnailing
import QuickLookUI

struct SearchResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedResultID: String?
    @FocusState private var resultsKeyFocus: Bool

    private var filteredResults: [SearchResultItem] {
        guard model.hideHiddenFiles else { return model.searchResults }
        return model.searchResults.filter { !isHiddenFile($0) }
    }

    private func isHiddenFile(_ item: SearchResultItem) -> Bool {
        item.file.filename.hasPrefix(".")
    }

    private var selectedResult: SearchResultItem? {
        filteredResults.first { $0.id == selectedResultID }
    }

    private func openResult(_ result: SearchResultItem) {
        do {
            try model.withSecurityScopedAccess(for: result.file.filePath) {
                let url = URL(fileURLWithPath: result.file.filePath)
                NSWorkspace.shared.open(url)
            }
        } catch AppModel.BookmarkError.userCancelled {
            // no-op
        } catch {
            print("Failed to open file: \(error)")
        }
    }

    private func previewResult(_ result: SearchResultItem) {
        do {
            try model.withSecurityScopedAccess(for: result.file.filePath) {
                let url = URL(fileURLWithPath: result.file.filePath)
                QuickLookPreviewCoordinator.shared.present(url: url)
            }
        } catch AppModel.BookmarkError.userCancelled {
            // user cancelled; no-op
        } catch {
            print("Failed to preview file: \(error)")
        }
    }

    private func openSelectedResult() {
        guard let result = selectedResult else { return }
        openResult(result)
    }

    private func previewSelectedResult() {
        guard let result = selectedResult else { return }
        previewResult(result)
    }
    
    private func pruneSelectionIfNeeded() {
        if let id = selectedResultID,
           !filteredResults.contains(where: { $0.id == id }) {
            selectedResultID = nil
        }
    }

    var body: some View {
        @Bindable var model = model
        return GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isSearching {
                        LoadingStateView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if let error = model.searchError {
                        ErrorStateView(error: error)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if !filteredResults.isEmpty {
                        ResultsListView(
                            results: filteredResults,
                            selectedResultID: $selectedResultID,
                            onSelect: { id in
                                selectedResultID = id
                                resultsKeyFocus = true
                            },
                            onOpen: { openResult($0) },
                            onPreview: { previewResult($0) }
                        )
                    } else if !model.searchResults.isEmpty {
                        FilteredResultsEmptyView()
                    } else {
                        EmptyResultsView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    }
                }
            }
            .frame(height: geometry.size.height)
        }
        .focusable(true)
        .focusEffectDisabled()
        .focused($resultsKeyFocus)
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return filteredResults.isEmpty ? .ignored : .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return filteredResults.isEmpty ? .ignored : .handled
        }
        .onKeyPress(.space) {
            previewSelectedResult()
            return selectedResultID == nil ? .ignored : .handled
        }
        .onKeyPress(.return) {
            openSelectedResult()
            return selectedResultID == nil ? .ignored : .handled
        }
        .onChange(of: filteredResults, initial: false) { _, _ in
            pruneSelectionIfNeeded()
        }
    }
    
    private func moveSelection(_ delta: Int) {
        guard !filteredResults.isEmpty else { return }
        if selectedResultID == nil {
            selectedResultID = filteredResults.first?.id
            return
        }
        if let index = filteredResults.firstIndex(where: { $0.id == selectedResultID }),
           filteredResults.indices.contains(index + delta) {
            selectedResultID = filteredResults[index + delta].id
        }
    }
}


// MARK: - Loading State

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .frame(maxWidth: 32)
                .frame(height: 32)

            Text("Searching files...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Error State

struct ErrorStateView: View {
    @Environment(AppModel.self) private var model
    let error: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red.opacity(0.8))

            Text("Search Failed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if model.canRetryLastSearch {
                Button(action: {
                    model.retryLastSearch()
                }) {
                    Label("Retry Search", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Empty Results

struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("No Results Found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Try different search terms or check your folder filters")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Results List

struct ResultsListView: View {
    let results: [SearchResultItem]
    @Binding var selectedResultID: String?
    let onSelect: (String) -> Void
    let onOpen: (SearchResultItem) -> Void
    let onPreview: (SearchResultItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(results) { result in
                    SearchResultRow(
                        result: result,
                        isSelected: selectedResultID == result.id,
                        onSelect: {
                            onSelect(result.id)
                        },
                        onOpen: {
                            onOpen(result)
                        },
                        onPreview: {
                            onPreview(result)
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResultItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    @State private var isHovered = false
    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                FileThumbnailView(
                    url: URL(fileURLWithPath: result.file.filePath),
                    onPreview: onPreview
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(result.file.filename)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(String(format: "%.0f%%", result.relevanceScore * 100))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.3), in: Capsule())

                        Image(systemName: "arrow.right")
                            .font(.system(size: 13))
                            .foregroundStyle(.quaternary)
                            .opacity(isHovered ? 1 : 0)
                    }

                    Text(result.file.filePath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let summary = result.file.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : (isHovered ? Color.primary.opacity(0.03) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: isSelected ? 1 : 0.8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            onSelect()
            showingDetail = true
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onOpen()
        })
        .contextMenu {
            Button("Quick Look") {
                onPreview()
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.file.filePath)])
            }
        }
        .popover(isPresented: $showingDetail) {
            SearchResultDetailView(result: result) {
                showingDetail = false
            }
            .frame(width: 360)
            .padding()
        }
        .onDrag {
            let provider = NSItemProvider(object: NSURL(fileURLWithPath: result.file.filePath))
            return provider
        }
    }
}

// MARK: - File Thumbnail & Filter Toggle

private struct FileThumbnailView: View {
    let url: URL
    var onPreview: () -> Void
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary.opacity(0.3))
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 40, height: 40)
            }
        }
        .onAppear(perform: generateThumbnail)
        .onTapGesture(count: 1, perform: onPreview)
    }

    private func generateThumbnail() {
        guard image == nil else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 120, height: 120),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let nsImage = NSImage(cgImage: cgImage, size: .zero)
            DispatchQueue.main.async {
                image = nsImage
            }
        }
    }
}

private struct FilteredResultsEmptyView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("All results are hidden files")
                .font(.system(size: 17, weight: .semibold))

            Text("Update Settings → General to show files whose names start with “.”.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

private struct SearchResultDetailView: View {
    let result: SearchResultItem
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(result.file.filename)
                    .font(.title3.bold())
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(.borderless)
            }
            
            Text(result.file.filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            if let summary = result.file.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Accessed \(format(date: result.file.accessed))", systemImage: "clock")
                Label("Created \(format(date: result.file.created))", systemImage: "doc")
                Label("Modified \(format(date: result.file.modified))", systemImage: "pencil")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }
    
    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Quick Look Coordinator

private final class QuickLookPreviewCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPreviewCoordinator()
    private var urls: [URL] = []

    func present(url: URL) {
        urls = [url]
        guard let panel = QLPreviewPanel.shared() else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}

#Preview {
    SearchResultsView()
        .environment(AppModel())
        .frame(width: 800, height: 600)
}
