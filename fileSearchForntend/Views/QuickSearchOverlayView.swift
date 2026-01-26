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
    private let collapsedHeight: CGFloat = 140
    private let expandedHeight: CGFloat = 380

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

            SearchFieldView(isFocused: $isSearchFocused)

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .frame(width: 940, height: overlayHeight, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.25), value: shouldExpand)
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
            updateLayout(shouldExpand)
        }
        .onExitCommand { onClose() }
        .onChange(of: shouldExpand) { oldValue, newValue in
            // Single source of truth for layout changes
            if oldValue != newValue {
                updateLayout(newValue)
            }
        }
    }

    private var contentArea: some View {
        Group {
            if model.searchText.isEmpty {
                // Show nothing when search is empty (collapsed state)
                EmptyView()
            } else if model.isSearching {
                ProgressView()
                    .controlSize(.regular)
                    .padding(.vertical, 12)
            } else if filteredResults.isEmpty {
                Text("No files found")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
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
        .animation(.easeInOut(duration: 0.25), value: shouldExpand)
    }

    private var overlayHeight: CGFloat {
        shouldExpand ? expandedHeight : collapsedHeight
    }

    private var shouldExpand: Bool {
        // Only expand if we have results AND search text is not empty
        !model.searchText.isEmpty && !filteredResults.isEmpty
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
