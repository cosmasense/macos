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

enum SearchResultViewMode: String, CaseIterable {
    case list
    case grid

    var label: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        }
    }

    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

struct SearchResultsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedResultID: String?
    @FocusState private var resultsKeyFocus: Bool
    @AppStorage("searchResultViewMode") private var viewModeRaw: String = SearchResultViewMode.list.rawValue

    private var viewMode: SearchResultViewMode {
        get { SearchResultViewMode(rawValue: viewModeRaw) ?? .list }
    }

    /// Filters search results based on file existence and user-configured filter patterns.
    ///
    /// **Note: This is a temporary client-side implementation.**
    /// In the future, filtering should be performed server-side via the search API
    /// for better performance with large result sets. See `FileFilterService` for
    /// the planned API format and `AppModel.shouldFilterFile()` for the filtering logic.
    private var filteredResults: [SearchResultItem] {
        model.searchResults.filter { item in
            // Filter out files that don't exist
            guard FileManager.default.fileExists(atPath: item.file.filePath) else { return false }
            // Apply user-configured filter patterns
            if model.shouldFilterFile(filePath: item.file.filePath, filename: item.file.filename) {
                return false
            }
            return true
        }
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
            print("User cancelled file access permission")
        } catch AppModel.BookmarkError.folderUnknown {
            // Show alert to user
            let alert = NSAlert()
            alert.messageText = "Cannot Open File"
            alert.informativeText = "Unable to access this file. Please grant access to the containing folder when prompted."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Open File"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func previewResult(_ result: SearchResultItem) {
        do {
            try model.withSecurityScopedAccess(for: result.file.filePath) {
                let url = URL(fileURLWithPath: result.file.filePath)
                QuickLookPreviewCoordinator.shared.present(url: url)
            }
        } catch AppModel.BookmarkError.userCancelled {
            print("User cancelled file access permission")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Preview File"
            alert.informativeText = "Unable to access this file. Please grant access to the containing folder."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
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
                        // Header with result count + view mode toggle
                        HStack {
                            Text("\(filteredResults.count) result\(filteredResults.count == 1 ? "" : "s")")
                                .font(.system(size: 18, weight: .semibold))
                            Spacer()
                            Picker("View", selection: Binding(
                                get: { viewMode },
                                set: { viewModeRaw = $0.rawValue }
                            )) {
                                ForEach(SearchResultViewMode.allCases, id: \.self) { mode in
                                    Image(systemName: mode.icon)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 96)
                            .help("Switch between list and grid view")
                        }
                        .padding(.horizontal, 4)

                        if viewMode == .list {
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
                        } else {
                            ResultsGridView(
                                results: filteredResults,
                                selectedResultID: $selectedResultID,
                                onSelect: { id in
                                    selectedResultID = id
                                    resultsKeyFocus = true
                                },
                                onOpen: { openResult($0) },
                                onPreview: { previewResult($0) }
                            )
                        }
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

// MARK: - Results Grid View

struct ResultsGridView: View {
    let results: [SearchResultItem]
    @Binding var selectedResultID: String?
    let onSelect: (String) -> Void
    let onOpen: (SearchResultItem) -> Void
    let onPreview: (SearchResultItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 14, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(results) { result in
                SearchResultGridCell(
                    result: result,
                    isSelected: selectedResultID == result.id,
                    onSelect: { onSelect(result.id) },
                    onOpen: { onOpen(result) },
                    onPreview: { onPreview(result) }
                )
            }
        }
        .padding(.horizontal, 4)
    }
}

struct SearchResultGridCell: View {
    let result: SearchResultItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    @State private var isHovered = false
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            FileThumbnailView(
                url: URL(fileURLWithPath: result.file.filePath),
                size: CGSize(width: 110, height: 130)
            )

            Text(result.file.filename)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.08), lineWidth: isSelected ? 1 : 0.8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onSelect()
            onPreview()
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Quick Look") { onPreview() }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.file.filePath)])
            }
        }
        .onDrag {
            let url = URL(fileURLWithPath: result.file.filePath)
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            provider.suggestedName = result.file.filename
            return provider
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
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            // Larger file preview — natural aspect ratio
            FileThumbnailView(
                url: URL(fileURLWithPath: result.file.filePath),
                size: CGSize(width: 64, height: 80)
            )

            VStack(alignment: .leading, spacing: 3) {
                // Title (filename)
                Text(result.file.filename)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Summary below title
                if let summary = result.file.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 2)

                // File path — dark blue hyperlink with strong contrast on transparent bg
                Text(result.file.filePath)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(red: 0.10, green: 0.30, blue: 0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture {
                        let url = URL(fileURLWithPath: result.file.filePath)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 90)
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
        .onTapGesture {
            onSelect()
            onPreview()
        }
        .contextMenu {
            Button("Open") {
                onOpen()
            }
            Button("Quick Look") {
                onPreview()
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.file.filePath)])
            }
        }
        .onDrag {
            createDragProvider()
        }
    }

    private func createDragProvider() -> NSItemProvider {
        let url = URL(fileURLWithPath: result.file.filePath)

        var tempFileURL: URL?
        do {
            try model.withSecurityScopedAccess(for: url.path) {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(result.file.filename)
                try? FileManager.default.removeItem(at: tempFile)
                try FileManager.default.copyItem(at: url, to: tempFile)
                tempFileURL = tempFile
            }
        } catch {
            print("Failed to copy file for drag: \(error)")
        }

        if let tempFile = tempFileURL, let provider = NSItemProvider(contentsOf: tempFile) {
            provider.suggestedName = result.file.filename
            return provider
        }

        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        provider.suggestedName = result.file.filename
        return provider
    }
}

// MARK: - File Thumbnail & Filter Toggle

/// Process-wide cache so scrolling away/back doesn't regenerate thumbnails.
/// Keyed on the file URL path.
private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 500  // ~500 thumbnails kept in memory
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func store(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url.path as NSString)
    }
}

private struct FileThumbnailView: View {
    let url: URL
    var size: CGSize = CGSize(width: 64, height: 80)
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.quaternary.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(0.3))
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .onAppear(perform: loadThumbnail)
    }

    private func loadThumbnail() {
        guard image == nil else { return }

        // Hit the cache first for instant display
        if let cached = ThumbnailCache.shared.image(for: url) {
            image = cached
            return
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size.width * 3, height: size.height * 3),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let nsImage = NSImage(cgImage: cgImage, size: .zero)
            ThumbnailCache.shared.store(nsImage, for: url)
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

// SearchResultDetailView — commented out, replaced by Quick Look preview on click
//private struct SearchResultDetailView: View {
//    let result: SearchResultItem
//    let onClose: () -> Void
//    ...
//}

// MARK: - Quick Look Coordinator

private final class QuickLookPreviewCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPreviewCoordinator()
    private var urls: [URL] = []
    private var currentIndex: Int = 0

    func present(url: URL) {
        urls = [url]
        currentIndex = 0
        showPanel()
    }

    /// Present Quick Look with multiple URLs (all search results).
    /// `selectedIndex` is the initially focused item.
    func present(urls: [URL], selectedIndex: Int) {
        self.urls = urls
        self.currentIndex = min(selectedIndex, urls.count - 1)
        showPanel()
    }

    /// Update the selected item without reopening the panel.
    func updateSelection(index: Int) {
        guard index >= 0, index < urls.count else { return }
        currentIndex = index
        QLPreviewPanel.shared()?.reloadData()
    }

    private func showPanel() {
        guard let panel = QLPreviewPanel.shared() else {
            if let url = urls.first {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            return
        }
        panel.dataSource = self
        panel.currentPreviewItemIndex = currentIndex
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
