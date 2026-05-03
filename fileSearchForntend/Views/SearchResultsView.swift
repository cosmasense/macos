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
    /// Live column count for the grid view, recomputed from the
    /// container's width whenever it changes. Drives up/down arrow
    /// navigation in grid mode so a single arrow press jumps a whole
    /// row instead of advancing one cell.
    @State private var gridColumnCount: Int = 4

    private var viewMode: SearchResultViewMode {
        get { SearchResultViewMode(rawValue: viewModeRaw) ?? .list }
    }

    // Grid layout constants — kept in sync with ResultsGridView's
    // GridItem so the column count we compute here actually matches
    // the column count SwiftUI ends up rendering.
    fileprivate static let gridMinCellWidth: CGFloat = 130
    fileprivate static let gridSpacing: CGFloat = 14
    fileprivate static let gridHorizontalPadding: CGFloat = 4

    /// Mirrors GridItem.adaptive's column-count formula:
    /// floor((W + spacing) / (minimum + spacing)).
    fileprivate static func columnCount(for width: CGFloat) -> Int {
        let usable = max(0, width - 2 * gridHorizontalPadding)
        let count = Int(floor((usable + gridSpacing) / (gridMinCellWidth + gridSpacing)))
        return max(1, count)
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
        // Single-URL fallback — used by context-menu "Quick Look".
        // Multi-item navigation is set up in previewSelectedResult so
        // arrowing inside Quick Look walks the full result list.
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

    /// Quick Look the currently-selected result. Hands the entire
    /// filtered result list to the panel so its built-in left/right
    /// arrows walk the search results — Finder semantics. Selection in
    /// the underlying list/grid follows the panel via the
    /// onIndexChanged callback.
    private func previewSelectedResult() {
        guard let result = selectedResult,
              let selectedIndex = filteredResults.firstIndex(where: { $0.id == result.id })
        else { return }

        let urls = filteredResults.map { URL(fileURLWithPath: $0.file.filePath) }
        let ids = filteredResults.map { $0.id }
        let selectionBinding = $selectedResultID

        do {
            // Wrap only the initial file in security-scoped access so
            // the bookmark prompt fires once (on first preview); QL's
            // navigation between items relies on FDA being granted, so
            // we don't try to scope every URL up front. Files outside
            // any bookmarked folder will still preview correctly because
            // the app is unsandboxed.
            try model.withSecurityScopedAccess(for: result.file.filePath) {
                QuickLookPreviewCoordinator.shared.present(
                    urls: urls,
                    selectedIndex: selectedIndex,
                    onIndexChanged: { newIndex in
                        guard newIndex >= 0, newIndex < ids.count else { return }
                        selectionBinding.wrappedValue = ids[newIndex]
                    }
                )
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
    
    private func pruneSelectionIfNeeded() {
        if let id = selectedResultID,
           !filteredResults.contains(where: { $0.id == id }) {
            selectedResultID = nil
        }
    }

    var body: some View {
        @Bindable var model = model
        return GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Track container width → recompute grid column count.
                    // Hidden/zero-size — purely an observer.
                    Color.clear
                        .frame(height: 0)
                        .onAppear {
                            gridColumnCount = Self.columnCount(for: geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            gridColumnCount = Self.columnCount(for: newWidth)
                        }
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
                            ViewModeToggle(
                                selection: Binding(
                                    get: { viewMode },
                                    set: { viewModeRaw = $0.rawValue }
                                )
                            )
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
            // List: next item. Grid: jump down one full row.
            moveSelection(by: viewMode == .grid ? gridColumnCount : 1)
            return filteredResults.isEmpty ? .ignored : .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: viewMode == .grid ? -gridColumnCount : -1)
            return filteredResults.isEmpty ? .ignored : .handled
        }
        .onKeyPress(.leftArrow) {
            // Only meaningful in grid mode — list rows are full-width
            // so left/right have no spatial meaning. Ignored in list
            // so left/right could one day be repurposed for tabbing
            // between panes without reworking this code.
            guard viewMode == .grid else { return .ignored }
            moveSelection(by: -1)
            return filteredResults.isEmpty ? .ignored : .handled
        }
        .onKeyPress(.rightArrow) {
            guard viewMode == .grid else { return .ignored }
            moveSelection(by: 1)
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
    
    /// Move the selection by `delta` items in the flat result array.
    /// Grid mode passes ±columnCount for vertical moves and ±1 for
    /// horizontal; list mode passes ±1. Clamps at the bounds rather
    /// than ignoring out-of-range moves so up at the top row in grid
    /// mode lands on row 0 instead of feeling stuck.
    private func moveSelection(by delta: Int) {
        guard !filteredResults.isEmpty else { return }
        if selectedResultID == nil {
            selectedResultID = filteredResults.first?.id
            return
        }
        guard let index = filteredResults.firstIndex(where: { $0.id == selectedResultID }) else {
            selectedResultID = filteredResults.first?.id
            return
        }
        let newIndex = max(0, min(filteredResults.count - 1, index + delta))
        if newIndex != index {
            selectedResultID = filteredResults[newIndex].id
        }
    }
}


// MARK: - View Mode Toggle

/// Custom list/grid toggle with brand-blue highlight. Replaces the default
/// segmented Picker so the active tint uses `Color.brandBlue` (not the system
/// accent) and the chrome reads less like an iOS control.
private struct ViewModeToggle: View {
    @Binding var selection: SearchResultViewMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SearchResultViewMode.allCases, id: \.self) { mode in
                ViewModeButton(
                    mode: mode,
                    isSelected: selection == mode,
                    action: { selection = mode }
                )
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }
}

private struct ViewModeButton: View {
    let mode: SearchResultViewMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: mode.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
                .frame(width: 34, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fillColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var fillColor: Color {
        if isSelected { return Color.brandBlue }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
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
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                SearchResultRow(
                    result: result,
                    index: index,
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
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                SearchResultGridCell(
                    result: result,
                    index: index,
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
    var index: Int = 100
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    @State private var isHovered = false
    @State private var showStats = false
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                FileThumbnailView(
                    url: URL(fileURLWithPath: result.file.filePath),
                    size: CGSize(width: 92, height: 92),
                    priority: index
                )
                .frame(width: 100, height: 96, alignment: .center)

                FileTypeBadge(extension: result.file.fileExtension)
                    .offset(x: 4, y: 4)
            }
            .frame(width: 100, height: 96, alignment: .center)

            // Filename instead of LLM-generated title — matches list view
            // semantics so users can scan grid + list interchangeably and
            // recognize files by their on-disk name. The LLM title can be
            // creative ("Field Trip Memories") but the user usually
            // searches for "IMG_1234.JPG" and wants that exact label.
            Text(result.file.filename)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.brandBlue.opacity(0.22) : (isHovered ? Color.brandBlue.opacity(0.22) : Color.clear))
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        // Finder semantics: single click selects, double click opens,
        // right-click → context menu, Space → Quick Look. Both
        // gestures registered together — SwiftUI fires the single-tap
        // closure on the first click of a double too, but onSelect is
        // idempotent so the redundant call is harmless.
        .onTapGesture(count: 2) {
            onOpen()
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Quick Look") { onPreview() }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.file.filePath)])
            }
            Divider()
            // Pulls full DB record + LLM summary + embedding metadata
            // for this file. Useful when an image (or any other) hit
            // looks wrong and you want to see what the indexer
            // actually wrote without dropping into sqlite.
            Button("Stats for Nerds…") { showStats = true }
        }
        .sheet(isPresented: $showStats) {
            StatsForNerdsView(filePath: result.file.filePath)
                .environment(model)
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
    var index: Int = 100
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    @State private var isHovered = false
    @State private var metadata: FileMetadata = .empty
    @State private var showStats = false
    @Environment(AppModel.self) private var model

    private var parentFolderName: String {
        let parent = (result.file.filePath as NSString).deletingLastPathComponent
        return (parent as NSString).lastPathComponent
    }

    /// Backend annotates partial summaries with "[partial: ...]" when
    /// the file's summarize budget elapsed before all chunks were
    /// covered (or fast-mode capped at one chunk). Surfaced as a
    /// small chip so users know the result was indexed by head only.
    private var isPartialCoverage: Bool {
        (result.file.summary ?? "").contains("[partial:")
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                FileThumbnailView(
                    url: URL(fileURLWithPath: result.file.filePath),
                    size: CGSize(width: 68, height: 68),
                    priority: index
                )
                FileTypeBadge(extension: result.file.fileExtension)
                    .offset(x: 4, y: 4)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 2) {
                // Title (filename) + optional partial-coverage chip
                HStack(spacing: 6) {
                    Text(result.file.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isPartialCoverage {
                        Text("partial")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                            .help("This file's summary was generated from a partial pass — long content was truncated to fit the per-file budget. Search still works but the summary may not cover the whole document.")
                    }
                }

                // Spotlight-style metadata: type · size · date · 📁 parent
                HStack(spacing: 6) {
                    if !metadata.typeDescription.isEmpty {
                        Text(metadata.typeDescription)
                    }
                    if !metadata.sizeString.isEmpty {
                        Text("·")
                        Text(metadata.sizeString)
                    }
                    if !metadata.dateString.isEmpty {
                        Text("·")
                        Text(metadata.dateString)
                    }
                    if !parentFolderName.isEmpty {
                        Text("·")
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(parentFolderName)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 88)
        .task(id: result.file.filePath) {
            metadata = FileMetadata.load(path: result.file.filePath)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.brandBlue.opacity(0.22) : (isHovered ? Color.brandBlue.opacity(0.22) : Color.clear))
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        // Finder semantics: single click selects, double click opens,
        // right-click → context menu, Space → Quick Look. Both
        // gestures registered together — SwiftUI fires the single-tap
        // closure on the first click of a double too, but onSelect is
        // idempotent so the redundant call is harmless.
        .onTapGesture(count: 2) {
            onOpen()
        }
        .onTapGesture {
            onSelect()
        }
        // Drag originates from anywhere on the row, but the drag image
        // shows only the file thumbnail — the row's text/paths are
        // context, not something the user wants to see flying with the cursor.
        .onDrag {
            createDragProvider()
        } preview: {
            FileThumbnailView(
                url: URL(fileURLWithPath: result.file.filePath),
                size: CGSize(width: 64, height: 80),
                priority: index
            )
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
            Divider()
            Button("Stats for Nerds…") { showStats = true }
        }
        .sheet(isPresented: $showStats) {
            StatsForNerdsView(filePath: result.file.filePath)
                .environment(model)
        }
    }

    private func createDragProvider() -> NSItemProvider {
        // Unsandboxed app + Full Disk Access means we can hand the original
        // file URL directly to the drop target — no temp copy, and no
        // bookmark prompt for files that live outside a watched folder.
        let url = URL(fileURLWithPath: result.file.filePath)
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

/// Bounded, priority-aware loader for QLThumbnailGenerator requests.
///
/// Why this exists: firing 20+ `generateBestRepresentation` calls at once
/// doesn't give you 20-way parallelism — QuickLook's XPC services
/// serialize requests per file-type handler internally, so flooding it
/// actually hurts. Throttling to 4 in-flight requests + prioritizing
/// visible rows trades a negligible amount of headroom for a much
/// smoother pop-in.
private final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .userInitiated
        return q
    }()

    /// `priority`: lower = earlier in the results list = load sooner.
    /// OperationQueue doesn't guarantee strict FIFO-by-priority, but it
    /// strongly biases picks toward higher QueuePriority values.
    func load(url: URL,
              pixelSize: CGSize,
              scale: CGFloat,
              priority: Int,
              completion: @escaping (NSImage?) -> Void) {
        let op = BlockOperation {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: pixelSize,
                scale: scale,
                representationTypes: .thumbnail
            )
            let sema = DispatchSemaphore(value: 0)
            var result: NSImage?
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                if let cg = rep?.cgImage {
                    result = NSImage(cgImage: cg, size: .zero)
                }
                sema.signal()
            }
            // Block this operation's slot until QL is done so the
            // concurrency cap is meaningful; without the wait all 20 ops
            // finish in microseconds and fan out to QL anyway.
            _ = sema.wait(timeout: .now() + 10)
            if let img = result {
                ThumbnailCache.shared.store(img, for: url)
            }
            DispatchQueue.main.async { completion(result) }
        }
        // 0→first rows → .veryHigh, later rows step down so the queue
        // drains in roughly visible-first order.
        switch priority {
        case ..<4:  op.queuePriority = .veryHigh
        case 4..<8: op.queuePriority = .high
        case 8..<16: op.queuePriority = .normal
        default:    op.queuePriority = .low
        }
        queue.addOperation(op)
    }

    /// Fast synchronous-ish icon lookup: returns the Finder icon for the
    /// file so the slot isn't blank while we wait for the real thumbnail.
    /// NSWorkspace.icon is cheap (cached per file type) and stays on the
    /// calling queue — safe to call from the main thread.
    func quickIcon(for url: URL, size: CGSize) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = size
        return icon
    }
}

private struct FileThumbnailView: View {
    let url: URL
    var size: CGSize = CGSize(width: 64, height: 80)
    /// Ordering hint — index of this row in the result list. Lower values
    /// load first so the top of the page fills in before rows the user
    /// hasn't scrolled to yet. Default 100 = low-priority so call sites
    /// that don't know their index don't starve prioritized ones.
    var priority: Int = 100
    @State private var image: NSImage?
    @State private var isFullThumbnail: Bool = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                    // Subtle crossfade when upgrading from icon → thumbnail
                    .animation(.easeInOut(duration: 0.18), value: isFullThumbnail)
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
        guard !isFullThumbnail else { return }

        // 1. Cache hit — instant, skip the whole pipeline.
        if let cached = ThumbnailCache.shared.image(for: url) {
            image = cached
            isFullThumbnail = true
            return
        }

        // 2. Show Finder icon immediately so the slot isn't blank while
        // QuickLook churns. NSWorkspace.icon is in-process and cheap.
        if image == nil {
            image = ThumbnailLoader.shared.quickIcon(for: url, size: size)
        }

        // 3. Queue the real thumbnail with visible-row priority. When it
        // arrives, swap in place (the `image` binding handles the transition).
        let pixelSize = CGSize(width: size.width * 3, height: size.height * 3)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        ThumbnailLoader.shared.load(
            url: url,
            pixelSize: pixelSize,
            scale: scale,
            priority: priority
        ) { ns in
            guard let ns else { return }
            image = ns
            isFullThumbnail = true
        }
    }
}

// MARK: - File Metadata (Spotlight-style)

/// Human-readable file attributes shown under the filename in list rows.
/// Loaded lazily via `.task` so we don't stat every result up-front.
struct FileMetadata: Equatable {
    var typeDescription: String
    var sizeString: String
    var dateString: String

    static let empty = FileMetadata(typeDescription: "", sizeString: "", dateString: "")

    static func load(path: String) -> FileMetadata {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .localizedTypeDescriptionKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return .empty
        }

        let type = values.localizedTypeDescription ?? ""

        var size = ""
        if let bytes = values.fileSize {
            size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }

        var date = ""
        if let modified = values.contentModificationDate {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            date = f.string(from: modified)
        }

        return FileMetadata(typeDescription: type, sizeString: size, dateString: date)
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
    /// Fired whenever Quick Look's panel switches items (user pressed
    /// the panel's built-in left/right arrows). Lets the host view sync
    /// its underlying selection so closing Quick Look leaves the row /
    /// cell that was last previewed selected — the same behavior Finder
    /// has when you arrow through Quick Look there.
    private var indexChangedHandler: ((Int) -> Void)?
    private var indexObservation: NSKeyValueObservation?

    func present(url: URL) {
        urls = [url]
        currentIndex = 0
        indexChangedHandler = nil
        showPanel()
    }

    /// Present Quick Look with multiple URLs (all search results).
    /// `selectedIndex` is the initially focused item. `onIndexChanged`
    /// fires every time the user navigates within the panel.
    func present(urls: [URL], selectedIndex: Int, onIndexChanged: ((Int) -> Void)? = nil) {
        self.urls = urls
        self.currentIndex = max(0, min(selectedIndex, urls.count - 1))
        self.indexChangedHandler = onIndexChanged
        showPanel()
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

        // Replace any prior observation — a fresh present() may have a
        // different urls array and handler.
        indexObservation?.invalidate()
        indexObservation = panel.observe(
            \.currentPreviewItemIndex,
            options: [.new]
        ) { [weak self] panel, _ in
            guard let self else { return }
            let idx = panel.currentPreviewItemIndex
            self.currentIndex = idx
            // KVO fires on the panel's queue; bounce to main so the
            // host view's @State mutation stays on the main actor.
            DispatchQueue.main.async {
                self.indexChangedHandler?(idx)
            }
        }
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
