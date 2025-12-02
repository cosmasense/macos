//
//  QuickSearchOverlayView.swift
//  fileSearchForntend
//
//  Floating quick-search UI with glass background and horizontal results.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct QuickSearchOverlayView: View {
    @Environment(AppModel.self) private var model
    var onClose: () -> Void
    @Environment(\.updateQuickSearchLayout) private var updateLayout

    @FocusState private var isSearchFocused: Bool
    @State private var lastResultCount: Int = 0
    @State private var hasExpandedOnce: Bool = false
    private let collapsedHeight: CGFloat = 140
    private let expandedHeight: CGFloat = 380
    @State private var dragLocation: CGPoint = .zero

    private var filteredResults: [SearchResultItem] {
        guard model.hideHiddenFiles else { return model.searchResults }
        return model.searchResults.filter { !$0.file.filename.hasPrefix(".") }
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
            updateLayout(!filteredResults.isEmpty)
        }
        .onExitCommand { onClose() }
        .onChange(of: filteredResults.count) { _, newValue in
            lastResultCount = newValue
            if !filteredResults.isEmpty {
                hasExpandedOnce = true
            }
            updateLayout(shouldExpand)
        }
        .onChange(of: shouldExpand) { oldValue, newValue in
            // Only update layout when expand state actually changes
            if oldValue != newValue {
                updateLayout(newValue)
            }
        }
    }

    private var contentArea: some View {
        Group {
            if model.isSearching {
                ProgressView()
                    .controlSize(.regular)
                    .padding(.vertical, 12)
            } else if filteredResults.isEmpty {
                Text(model.searchText.isEmpty ? "Start typing to search your files" : "No files found")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(filteredResults.prefix(12)) { item in
                            OverlayFileTile(result: item)
                                .frame(width: 190, height: 190)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, minHeight: 200, idealHeight: 220)
                .animation(.easeInOut(duration: 0.2), value: filteredResults)
            }
        }
    }

    private var overlayHeight: CGFloat {
        shouldExpand ? expandedHeight : collapsedHeight
    }

    private var shouldExpand: Bool {
        hasExpandedOnce || !filteredResults.isEmpty
    }
}

// MARK: - Overlay Tile

private struct OverlayFileTile: View {
    let result: SearchResultItem
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            let icon = NSWorkspace.shared.icon(forFile: result.file.filePath)
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .shadow(radius: 4, y: 2)

            Text(result.file.title?.isEmpty == false ? result.file.title! : result.file.filename)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: 8)
        .onTapGesture {
            openResult()
        }
        .onDrag {
            dragProvider()
        } preview: {
            let icon = NSWorkspace.shared.icon(forFile: result.file.filePath)
            VStack {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                Text(result.file.filename)
                    .font(.system(size: 12))
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func openResult() {
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
