//
//  QuickSearchOverlayView.swift
//  fileSearchForntend
//
//  Floating quick-search UI with glass background and horizontal results.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing
import QuickLookUI

struct QuickSearchOverlayView: View {
    @Environment(AppModel.self) private var model
    var onClose: () -> Void
    @Environment(\.updateQuickSearchLayout) private var updateLayout

    @FocusState private var isSearchFocused: Bool
    private let fixedHeight: CGFloat = 380

    /// Filters popup search results based on file existence and user-configured filter patterns.
    private var filteredResults: [SearchResultItem] {
        model.popupSearchResults.filter { item in
            // Filter out files that don't exist
            guard FileManager.default.fileExists(atPath: item.file.filePath) else { return false }
            // Apply user-configured filter patterns
            if model.shouldFilterFile(filePath: item.file.filePath, filename: item.file.filename) {
                return false
            }
            return true
        }
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close")

                DragHandle()
                    .frame(height: 18)
                    .padding(.trailing, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                Spacer()
            }

            PopupSearchFieldView(isFocused: $isSearchFocused)

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .frame(width: 940, height: fixedHeight, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
            ZStack {
                if #available(macOS 14.0, *) {
                    Color.clear.glassEffect(in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.26)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.78),
                                Color.white.opacity(0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.4
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 12)
        .shadow(color: Color.accentColor.opacity(0.06), radius: 14, y: 6)
        .onAppear {
            isSearchFocused = true
            updateLayout(true)  // Always expanded
        }
        .onExitCommand { onClose() }
    }

    private var contentArea: some View {
        Group {
            if model.popupSearchText.isEmpty {
                // Empty state - prompt user to search
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Type to search files")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.popupIsSearching {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No files found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(filteredResults.prefix(20)) { item in
                            OverlayFileTile(result: item)
                                .frame(width: 150, height: 180)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, minHeight: 190, idealHeight: 200)
            }
        }
    }

}

// MARK: - Overlay Tile

private struct OverlayFileTile: View {
    let result: SearchResultItem
    @Environment(AppModel.self) private var model
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Top 2/3: Preview and filename
            VStack(spacing: 8) {
                // Thumbnail/Preview area
                Group {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 100, maxHeight: 70)
                    } else {
                        let icon = NSWorkspace.shared.icon(forFile: result.file.filePath)
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(height: 70)
                .shadow(radius: 3, y: 2)

                // Filename
                Text(result.file.title?.isEmpty == false ? result.file.title! : result.file.filename)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 8)

            // Bottom 1/3: Path and Summary
            VStack(alignment: .leading, spacing: 3) {
                // File path
                Text(shortenedPath)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)

                // Summary
                if let summary = result.file.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(result.file.fileExtension.uppercased() + " file")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 6)
        .onTapGesture(count: 2) {
            openInDefaultApp()
        }
        .onTapGesture(count: 1) {
            openInQuickLook()
        }
        .contextMenu {
            Button {
                openInQuickLook()
            } label: {
                Label("Quick Look", systemImage: "eye")
            }

            Button {
                openInDefaultApp()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }

            Divider()

            Button {
                showInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Button {
                copyPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
        .onDrag {
            dragProvider()
        } preview: {
            let icon = thumbnail ?? NSWorkspace.shared.icon(forFile: result.file.filePath)
            VStack {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                Text(result.file.filename)
                    .font(.system(size: 11))
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .task {
            await loadThumbnail()
        }
    }

    private var shortenedPath: String {
        let path = result.file.filePath
        let components = path.split(separator: "/")
        // Show last 2-3 directory components
        if components.count > 3 {
            let shortened = components.suffix(3).joined(separator: "/")
            return ".../" + shortened
        }
        return path
    }

    private func loadThumbnail() async {
        let url = URL(fileURLWithPath: result.file.filePath)
        let size = CGSize(width: 200, height: 140)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            await MainActor.run {
                self.thumbnail = representation.nsImage
            }
        } catch {
            // Fall back to file icon (already showing)
            print("Thumbnail generation failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func openInQuickLook() {
        let url = URL(fileURLWithPath: result.file.filePath)
        QuickLookHelper.shared.preview(url: url)
    }

    private func openInDefaultApp() {
        do {
            try model.withSecurityScopedAccess(for: result.file.filePath) {
                let url = URL(fileURLWithPath: result.file.filePath)
                NSWorkspace.shared.open(url)
            }
        } catch AppModel.BookmarkError.userCancelled {
            print("User cancelled file access permission")
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Cannot Open File"
                alert.informativeText = "Unable to access this file. Please grant access when prompted."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func showInFinder() {
        let url = URL(fileURLWithPath: result.file.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.file.filePath, forType: .string)
    }

    private func dragProvider() -> NSItemProvider {
        let url = URL(fileURLWithPath: result.file.filePath)

        // Read file data and copy to temp location - this makes it work like Finder
        var tempFileURL: URL?
        do {
            try model.withSecurityScopedAccess(for: url.path) {
                // Copy file to temp directory
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(result.file.filename)

                // Remove if exists
                try? FileManager.default.removeItem(at: tempFile)

                // Copy the file
                try FileManager.default.copyItem(at: url, to: tempFile)
                tempFileURL = tempFile
            }
        } catch {
            print("Failed to copy file for drag: \(error)")
        }

        // If we successfully created a temp copy, use that
        // This makes it behave exactly like dragging from Finder!
        if let tempFile = tempFileURL, let provider = NSItemProvider(contentsOf: tempFile) {
            provider.suggestedName = result.file.filename
            return provider
        }

        // Fallback: just provide the original URL
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        provider.suggestedName = result.file.filename
        return provider
    }
}

// MARK: - Quick Look Helper

private class QuickLookHelper: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookHelper()

    private var currentURL: URL?

    func preview(url: URL) {
        currentURL = url

        DispatchQueue.main.async {
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        return currentURL as? QLPreviewItem
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        return false
    }
}

// MARK: - Popup Search Field (uses popup-specific state)

struct PopupSearchFieldView: View {
    @Environment(AppModel.self) private var model
    @FocusState.Binding var isFocused: Bool
    @State private var selectedSuggestionIndex: Int = 0
    @State private var backspaceMonitor: Any?

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(model.popupSearchTokens) { token in
                        PopupTokenChipView(token: token) {
                            removeToken(token)
                        }
                    }

                    TextField("Search files or type @folder...", text: $model.popupSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .onSubmit {
                            handleEnterKey()
                        }
                        .onChange(of: model.popupSearchText) { oldValue, newValue in
                            handleTextChange(oldValue: oldValue, newValue: newValue)
                        }
                        .onKeyPress(.tab) {
                            handleTabKey()
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            handleUpArrow()
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            handleDownArrow()
                            return .handled
                        }
                }

                if !model.popupSearchText.isEmpty || !model.popupSearchTokens.isEmpty {
                    Button(action: {
                        model.popupSearchText = ""
                        model.popupSearchTokens = []
                        model.popupSearchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                if #available(macOS 14.0, *) {
                    Color.clear.glassEffect(in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        isFocused
                            ? Color.accentColor.opacity(0.5)
                            : Color.white.opacity(0.2),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .shadow(
                color: isFocused
                    ? Color.accentColor.opacity(0.3)
                    : Color.black.opacity(0.08),
                radius: isFocused ? 16 : 12,
                x: 0,
                y: isFocused ? 6 : 4
            )

            if model.popupSearchText.contains("@") {
                PopupFolderSuggestionsView(selectedIndex: $selectedSuggestionIndex)
            }
        }
        .onChange(of: model.popupSearchText.contains("@")) { oldValue, newValue in
            if !newValue {
                selectedSuggestionIndex = 0
            }
        }
        .onAppear {
            setupBackspaceMonitor()
        }
        .onDisappear {
            removeBackspaceMonitor()
        }
    }

    private func setupBackspaceMonitor() {
        backspaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isFocused else { return event }
            if event.keyCode == 51 && model.popupSearchText.isEmpty && !model.popupSearchTokens.isEmpty {
                _ = withAnimation(.easeInOut(duration: 0.2)) {
                    model.popupSearchTokens.removeLast()
                }
                return nil
            }
            return event
        }
    }

    private func removeBackspaceMonitor() {
        if let monitor = backspaceMonitor {
            NSEvent.removeMonitor(monitor)
            backspaceMonitor = nil
        }
    }

    private func handleTextChange(oldValue: String, newValue: String) {
        selectedSuggestionIndex = 0
        checkForTokenCreation()
    }

    private func handleEnterKey() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && model.popupSearchText.contains("@") {
            selectFolder(suggestions[selectedSuggestionIndex])
        } else if !model.popupSearchText.isEmpty || !model.popupSearchTokens.isEmpty {
            model.performPopupSearch()
        }
    }

    private func handleTabKey() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && model.popupSearchText.contains("@") {
            selectFolder(suggestions[0])
        }
    }

    private func handleUpArrow() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && model.popupSearchText.contains("@") {
            selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
        }
    }

    private func handleDownArrow() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && model.popupSearchText.contains("@") {
            selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
        }
    }

    private func getSuggestions() -> [WatchedFolder] {
        let words = model.popupSearchText.split(separator: " ")
        guard let lastWord = words.last else { return [] }

        let word = String(lastWord)
        guard word.hasPrefix("@"), word.count > 1 else { return [] }

        let query = String(word.dropFirst()).lowercased()
        return model.watchedFolders.filter {
            $0.name.lowercased().hasPrefix(query)
        }
    }

    private func removeToken(_ token: SearchToken) {
        withAnimation(.easeInOut(duration: 0.2)) {
            model.popupSearchTokens.removeAll { $0.id == token.id }
        }
    }

    private func checkForTokenCreation() {
        let words = model.popupSearchText.split(separator: " ")
        guard let lastWord = words.last else { return }

        let word = String(lastWord)
        guard word.hasPrefix("@"), word.count > 1 else { return }

        let folderName = String(word.dropFirst())
        let matchingFolder = model.watchedFolders.first {
            $0.name.caseInsensitiveCompare(folderName) == .orderedSame
        }

        if let folder = matchingFolder {
            withAnimation(.easeInOut(duration: 0.2)) {
                createToken(for: folder.name)
            }
        }
    }

    private func createToken(for folderName: String) {
        let newToken = SearchToken(kind: .folder, value: folderName)
        if !model.popupSearchTokens.contains(newToken) {
            model.popupSearchTokens.append(newToken)
        }
        model.popupSearchText = model.popupSearchText
            .replacingOccurrences(of: "@\(folderName)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func selectFolder(_ folder: WatchedFolder) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let newToken = SearchToken(kind: .folder, value: folder.name)
            if !model.popupSearchTokens.contains(newToken) {
                model.popupSearchTokens.append(newToken)
            }
            let words = model.popupSearchText.split(separator: " ")
            var newText = model.popupSearchText
            if let lastWord = words.last, String(lastWord).hasPrefix("@") {
                newText = model.popupSearchText
                    .replacingOccurrences(of: String(lastWord), with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            model.popupSearchText = newText
        }
    }
}

// MARK: - Popup Token Chip

private struct PopupTokenChipView: View {
    let token: SearchToken
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(token.value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.9), Color.blue],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Popup Folder Suggestions

private struct PopupFolderSuggestionsView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedIndex: Int

    var body: some View {
        let suggestions = getSuggestions()

        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, folder in
                    Button(action: {
                        selectFolder(folder)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)

                            Text("@\(folder.name)")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            index == selectedIndex
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < suggestions.count - 1 {
                        Divider()
                            .padding(.leading, 38)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
            .padding(.top, 4)
        }
    }

    private func getSuggestions() -> [WatchedFolder] {
        let words = model.popupSearchText.split(separator: " ")
        guard let lastWord = words.last else { return [] }

        let word = String(lastWord)
        guard word.hasPrefix("@"), word.count > 1 else { return [] }

        let query = String(word.dropFirst()).lowercased()
        return model.watchedFolders.filter {
            $0.name.lowercased().hasPrefix(query)
        }
    }

    private func selectFolder(_ folder: WatchedFolder) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let newToken = SearchToken(kind: .folder, value: folder.name)
            if !model.popupSearchTokens.contains(newToken) {
                model.popupSearchTokens.append(newToken)
            }
            let words = model.popupSearchText.split(separator: " ")
            var newText = model.popupSearchText
            if let lastWord = words.last, String(lastWord).hasPrefix("@") {
                newText = model.popupSearchText
                    .replacingOccurrences(of: String(lastWord), with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            model.popupSearchText = newText
        }
    }
}
