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
    var onZoomToMain: () -> Void = {}
    @Environment(\.updateQuickSearchLayout) private var updateLayout

    private var hasActiveSearch: Bool {
        !model.popupSearchText.isEmpty
            || !model.popupSearchTokens.isEmpty
            || !model.popupSearchResults.isEmpty
    }

    /// True while the user is typing an @folder token — the last whitespace-
    /// separated word starts with '@' and the text doesn't end with a space.
    /// A trailing space means the mention is "finished" so the dropdown
    /// dismisses. Drives the panel to surface folder suggestions instead of
    /// search results.
    private var isInFolderMention: Bool {
        if model.popupSearchText.hasSuffix(" ") { return false }
        guard let lastWord = model.popupSearchText.split(separator: " ").last else {
            return false
        }
        return String(lastWord).hasPrefix("@")
    }

    @FocusState private var isSearchFocused: Bool
    @State private var debounceTask: Task<Void, Never>?
    @State private var isExpanded: Bool = false
    // Two-phase expand: `isExpanded` grows the panel background first,
    // `contentReady` fades the title bar and results in once the panel
    // has settled at its target size. Collapse reverses the order —
    // content fades out, then the panel shrinks — so the user never
    // sees content clipped by a resizing background.
    @State private var contentReady: Bool = false
    @State private var contentFadeTask: Task<Void, Never>?
    // Lifted out of PopupSearchFieldView so the folder-suggestions panel
    // (rendered outside the clipped pill) shares the selection index with
    // the field's keyboard handlers (up/down/tab/enter).
    @State private var selectedSuggestionIndex: Int = 0
    // Panel hugs the pill exactly — no transparent padding around the
    // glass background, otherwise the empty panel area reads as a dark
    // rectangle behind the pill on dim wallpapers.
    private let collapsedHeight: CGFloat = 46
    // `expandedHeight` is the BASE content height (search bar + results).
    // Chrome (traffic-light row) is additive on the panel side — it extends
    // the panel upward, not into this budget.
    private let expandedHeight: CGFloat = 522
    private let chromeHeight: CGFloat = 42
    // Two widths so the panel reads as "just a search bar" while idle and
    // grows wider when the user starts a search. Collapsed width matches
    // the inner search-pill exactly (no halo around it). Expanded width
    // adds 20pt of breathing room on each side for the result tiles.
    // Both must match `QuickSearchOverlayController` constants of the same
    // names so the AppKit panel frame and the SwiftUI content stay aligned.
    private let collapsedWidth: CGFloat = 500
    private let expandedWidth: CGFloat = 540
    // Shared timing for the expand/collapse choreography. A tuned
    // ease-out curve (cubic-bezier 0.22, 1, 0.36, 1) feels "emphasized":
    // fast lift-off, long glide into place — much smoother than plain
    // easeInOut. The exact same duration + control points drive the
    // AppKit panel animator so the SwiftUI frame and the window frame
    // tween in lockstep with zero visible seam.
    private let transitionDuration: Double = 0.42
    private var transitionAnimation: Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: transitionDuration)
    }

    /// Total SwiftUI content height, kept in sync with the AppKit panel's
    /// frame so the outer glass background exactly fills the panel.
    /// Expanded panel always includes the chrome row — they grow as one
    /// unit, so a single boolean (`isExpanded`) drives the full geometry.
    private var panelContentHeight: CGFloat {
        let base = isExpanded ? expandedHeight : collapsedHeight
        let chrome: CGFloat = isExpanded ? chromeHeight : 0
        return base + chrome
    }

    private var panelContentWidth: CGFloat {
        isExpanded ? expandedWidth : collapsedWidth
    }

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
        // Spotlight-style single unified panel:
        //   Top: the search field row (icon + tokens + text field).
        //   Bottom (when expanded): a divider followed by results — or,
        //   while the user is typing an @folder mention, the folder
        //   suggestions take the results slot instead.
        // Both live inside ONE glass-rounded-rectangle — no inner pill
        // background, no inner stroke, no gap. They read as one page.
        VStack(spacing: 0) {
            // Title bar reserves its 42pt slot as soon as the panel starts
            // growing, but its contents (traffic lights, expand button)
            // stay hidden until the grow is done. Net effect: during the
            // grow you only see the background expanding — no buttons
            // sliding around inside an animating frame.
            titleBar
                .opacity(contentReady ? 1 : 0)
                .frame(height: isExpanded ? chromeHeight : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(contentReady)
                // Non-control areas of the title bar drag the window.
                // File tiles below get NO drag region, so their `.onDrag`
                // file drag-out survives.
                .background(WindowDragRegion())

            PopupSearchFieldView(
                isFocused: $isSearchFocused,
                selectedSuggestionIndex: $selectedSuggestionIndex,
                onEmptySubmit: clearAndClose
            )
            // The field carries its own whiter pill background (see
            // PopupSearchFieldView). When collapsed, the panel is the
            // SAME width as the pill — no horizontal padding around it.
            // When expanded, we inset by 20pt so the pill keeps its
            // identity inside the wider results panel.
            .frame(maxWidth: expandedWidth)
            .padding(.horizontal, isExpanded ? 20 : 0)
            .padding(.top, isExpanded ? 1 : 0)
            // Drag the popup from the empty pill chrome (magnifying-glass
            // icon, padding around the text field). The TextField itself
            // is an NSTextField and swallows its own mouseDown, so text
            // selection keeps working.
            .background(WindowDragRegion())

            if isExpanded {
                Group {
                    if isInFolderMention {
                        PopupFolderSuggestionsView(selectedIndex: $selectedSuggestionIndex)
                    } else {
                        VStack(spacing: 10) {
                            if !model.watchedFolders.isEmpty {
                                PopupFolderChipsView()
                            }
                            contentArea
                        }
                    }
                }
                .frame(maxWidth: expandedWidth, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .center)
                // Content is always mounted while expanded; it just fades
                // in once `contentReady` flips. That way the grow phase
                // shows only the empty background, and the reveal phase
                // shows content sitting inside a panel that's already
                // settled at its final size.
                .opacity(contentReady ? 1 : 0)
            }
        }
        .frame(width: panelContentWidth, height: panelContentHeight, alignment: .top)
        .background {
            // Window background — the thing the user sees grow. Always
            // rendered. In collapsed state it's a 540x46 rounded rect
            // (visually indistinguishable from the pill). In expanded
            // state it's the full 540x564 window. One continuous surface
            // the whole time.
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            if #available(macOS 14.0, *) {
                Color.clear.glassEffect(in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.18 : 0.08),
            radius: isExpanded ? 14 : 12,
            x: 0,
            y: isExpanded ? 6 : 4
        )
        .overlay {
            // Esc is the only thing that clears popup search state. The
            // hotkey just toggles visibility and preserves the previous
            // query + results, so users can re-open and resume where they
            // left off.
            Button(action: clearAndClose) { EmptyView() }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .overlay(alignment: .topTrailing) {
            // Collapsed pill: expand-to-main lives as a plain overlay at
            // the top-right. In expanded mode, the title bar takes over
            // and houses both traffic lights and the expand button.
            if !isExpanded {
                WindowControlButton(systemImage: "arrow.up.left.and.arrow.down.right") {
                    onZoomToMain()
                }
                .help("Expand to main window")
                .padding(.trailing, 10)
                .padding(.top, (collapsedHeight - 28) / 2)
            }
        }
        // Only the panel frame needs SwiftUI's implicit animation now —
        // content visibility is sequenced explicitly in `setExpanded`.
        .animation(transitionAnimation, value: isExpanded)
        .onAppear {
            // Preserve prior state across hide/show. First present has no
            // "from" state, so snap to the right shape without animating.
            let hasPrior = !model.popupSearchResults.isEmpty || !model.popupSearchText.isEmpty
            applyExpanded(hasPrior, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onExitCommand { clearAndClose() }
        .onChange(of: model.popupOpenCount) { _, _ in
            let hasPrior = !model.popupSearchResults.isEmpty || !model.popupSearchText.isEmpty
            applyExpanded(hasPrior, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onChange(of: model.popupSearchText) { _, newValue in
            debounceTask?.cancel()
            // Empty field + no tokens ⇒ collapse back to the pill.
            if newValue.isEmpty && model.popupSearchTokens.isEmpty {
                model.popupSearchResults = []
                setExpanded(false)
                return
            }
            // Any non-empty text expands the panel immediately — the user
            // gets visual feedback on the first keystroke rather than
            // staring at a collapsed pill for the 300ms debounce window.
            setExpanded(true)
            if isInFolderMention { return }
            guard !newValue.contains("@") else { return }
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                model.performPopupSearch()
            }
        }
        .onChange(of: model.popupIsSearching) { _, searching in
            if searching {
                setExpanded(true)
            }
        }
        .onChange(of: filteredResults.isEmpty) { _, empty in
            if !empty {
                setExpanded(true)
            }
        }
    }

    /// Called by Esc: wipe the popup search state and dismiss the overlay
    /// outright. Main window is never re-surfaced on dismiss — only the
    /// explicit expand button does that. The hotkey path preserves state
    /// by routing through a separate dismiss that skips the clear.
    private func clearAndClose() {
        model.popupSearchText = ""
        model.popupSearchResults = []
        model.popupSearchTokens = []
        model.popupSearchError = nil
        onClose()
    }

    /// Called by the X button: wipe popup state and collapse the overlay
    /// back to its empty (no-search) presentation. Stays in the overlay —
    /// does not dismiss or zoom to the main window. The expand button is
    /// the only path that surfaces the main window.
    private func clearSearchState() {
        model.popupSearchText = ""
        model.popupSearchResults = []
        model.popupSearchTokens = []
        model.popupSearchError = nil
        setExpanded(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        applyExpanded(expanded, animated: true)
    }

    /// Two-phase expand/collapse. On expand, the window background grows
    /// first and the inner content fades in afterward — so the user sees
    /// "the app growing" followed by "the content arriving", not a
    /// single blurry blob of stuff resizing at once.
    ///
    /// On collapse the order reverses: content fades out while the panel
    /// is still at full size, then the background shrinks back into the
    /// pill. This prevents content from being clipped by a resizing
    /// background during the collapse.
    ///
    /// `animated == false` snaps both phases immediately — used for the
    /// initial present and for re-open, where there is no meaningful
    /// "from" state to tween from.
    private func applyExpanded(_ expanded: Bool, animated: Bool) {
        contentFadeTask?.cancel()
        contentFadeTask = nil

        guard animated else {
            isExpanded = expanded
            contentReady = expanded
            updateLayout(expanded, expanded)
            return
        }

        if expanded {
            withAnimation(transitionAnimation) {
                isExpanded = true
            }
            updateLayout(true, true)
            // Fade content in just as the panel reaches its target size.
            // ~70% of the grow completes before the fade starts so the
            // final ~30% overlap hides any last-frame settle jitter.
            let delayMs = UInt64(transitionDuration * 700)
            contentFadeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    contentReady = true
                }
            }
        } else {
            withAnimation(.easeIn(duration: 0.12)) {
                contentReady = false
            }
            // Start the shrink once the content has cleared so the
            // fading text isn't also being clipped by the resizing frame.
            contentFadeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 110 * 1_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(transitionAnimation) {
                    isExpanded = false
                }
                updateLayout(false, false)
            }
        }
    }

    /// Window-chrome row shown above the search field while a search is
    /// active. Hosts the traffic-light controls on the left and the
    /// expand-to-main button on the right. Mirrors a native macOS titlebar.
    private var titleBar: some View {
        HStack {
            TrafficLightControls(
                onClose: clearAndClose,
                onMinimize: clearSearchState
            )
            Spacer()
            WindowControlButton(systemImage: "arrow.up.left.and.arrow.down.right") {
                onZoomToMain()
            }
            .help("Expand to main window")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var contentArea: some View {
        Group {
            if model.popupIsSearching {
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
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 2, alignment: .top),
                            count: 4
                        ),
                        alignment: .center,
                        spacing: 6
                    ) {
                        ForEach(Array(filteredResults.prefix(50).enumerated()), id: \.element.id) { index, item in
                            OverlayFileTile(result: item, appearIndex: index)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

}

// MARK: - Overlay Tile (Finder-style grid cell)

private struct OverlayFileTile: View {
    let result: SearchResultItem
    let appearIndex: Int
    @Environment(AppModel.self) private var model
    @State private var thumbnail: NSImage?
    @State private var appeared: Bool = false
    @State private var thumbnailVisible: Bool = false
    @State private var isHovered: Bool = false
    @State private var showDetail: Bool = false
    @State private var hoverTask: Task<Void, Never>?

    private var displayTitle: String {
        (result.file.title?.isEmpty == false ? result.file.title : nil) ?? result.file.filename
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .opacity(thumbnailVisible ? 1 : 0)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    thumbnailVisible = true
                                }
                            }
                    } else {
                        let icon = NSWorkspace.shared.icon(forFile: result.file.filePath)
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 86, height: 86)
                    }
                }
                .frame(width: 92, height: 92)

                FileTypeBadge(extension: result.file.fileExtension)
                    .offset(x: 4, y: 4)
            }
            .frame(width: 100, height: 96, alignment: .center)

            Text(displayTitle)
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
                .fill(isHovered ? Color.brandBlue.opacity(0.22) : Color.clear)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { showDetail = true }
                }
            } else {
                showDetail = false
            }
        }
        .popover(isPresented: $showDetail, arrowEdge: .bottom) {
            OverlayFileDetailCard(result: result, thumbnail: thumbnail)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            appeared = false
            thumbnailVisible = false
            withAnimation(.easeOut(duration: 0.25).delay(Double(min(appearIndex, 8)) * 0.03)) {
                appeared = true
            }
        }
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
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
        }
        .task {
            await loadThumbnail()
        }
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
        // The app is unsandboxed and relies on Full Disk Access, so we don't
        // need to gate the drag behind a security-scoped bookmark prompt —
        // that was firing an NSOpenPanel every time for files outside the
        // watched folders we had bookmarks for. Hand the original URL to
        // NSItemProvider and let the drop target (Finder, Mail, etc.) copy
        // lazily — same outcome as the old temp-copy path, minus the prompt.
        let url = URL(fileURLWithPath: result.file.filePath)
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        provider.suggestedName = result.file.filename
        return provider
    }
}

// MARK: - File Type Badge

/// Small colored pill anchored to the bottom-right of a thumbnail, showing
/// the file extension. Color-coded by category so users can scan the grid
/// and spot docs vs. images vs. code at a glance.
struct FileTypeBadge: View {
    let `extension`: String

    private var label: String {
        let ext = self.extension.uppercased()
        // Keep it short — anything over 4 chars gets truncated.
        return ext.count > 4 ? String(ext.prefix(4)) : ext
    }

    private var color: Color {
        switch self.extension.lowercased() {
        case "pdf": return .red
        case "txt", "md", "rtf": return .blue
        case "doc", "docx": return Color(red: 0.18, green: 0.42, blue: 0.87)
        case "xls", "xlsx", "csv": return .green
        case "ppt", "pptx", "key": return .orange
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp": return .pink
        case "mov", "mp4", "avi", "mkv": return .purple
        case "mp3", "wav", "aac", "flac", "m4a": return Color(red: 0.85, green: 0.34, blue: 0.58)
        case "zip", "rar", "7z", "tar", "gz": return .brown
        case "swift", "py", "js", "ts", "java", "cpp", "c", "h", "rb", "go", "rs": return .teal
        case "html", "htm", "css": return .indigo
        case "json", "xml", "yaml", "yml": return .cyan
        default: return .gray
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color)
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8)
            )
    }
}

// MARK: - Hover Detail Card

private struct OverlayFileDetailCard: View {
    let result: SearchResultItem
    let thumbnail: NSImage?

    private var displayTitle: String {
        (result.file.title?.isEmpty == false ? result.file.title : nil) ?? result.file.filename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: result.file.filePath))
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(result.file.filename)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let summary = result.file.summary, !summary.isEmpty {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 4) {
                    Label("AI Analysis", systemImage: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 4) {
                Label("Path", systemImage: "folder")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(result.file.filePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
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
    @Environment(CosmaManager.self) private var cosmaManager
    @FocusState.Binding var isFocused: Bool
    @Binding var selectedSuggestionIndex: Int
    var onEmptySubmit: () -> Void = {}
    @State private var backspaceMonitor: Any?

    // Mirror of HomeView.aiReady — search is a no-op if either the
    // bootstrap files aren't on disk or the embedder hasn't loaded into
    // memory yet. Without this gate, the popup overlay let users submit
    // queries during cold-start and they came back empty.
    private var aiReady: Bool { cosmaManager.bootstrapReady && model.embedderReady }

    /// Matches the outer overlay's definition: user is composing an @folder
    /// mention iff the last whitespace-separated word starts with '@' and
    /// the text doesn't end with a trailing space (space = mention done).
    private var isInFolderMention: Bool {
        if model.popupSearchText.hasSuffix(" ") { return false }
        guard let lastWord = model.popupSearchText.split(separator: " ").last else {
            return false
        }
        return String(lastWord).hasPrefix("@")
    }

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

                    TextField(aiReady ? "Search files or type @folder..." : "Setting up AI models — search paused", text: $model.popupSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .disabled(!aiReady)
                        .opacity(aiReady ? 1 : 0.55)
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
                .frame(minHeight: 30)

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
            .padding(.vertical, 8)
            // Matches HomeView.SearchFieldView: inner minHeight 28 + vertical
            // pad 8 = ~44pt search bar.
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.85))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
        }
        .onChange(of: isInFolderMention) { _, isActive in
            if !isActive {
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
        if !suggestions.isEmpty && isInFolderMention {
            selectFolder(suggestions[selectedSuggestionIndex])
        } else if !model.popupSearchText.isEmpty || !model.popupSearchTokens.isEmpty {
            model.performPopupSearch()
        } else {
            // Empty field + no tokens: treat Return like Esc — clear popup
            // state and dismiss the overlay.
            onEmptySubmit()
        }
    }

    private func handleTabKey() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && isInFolderMention {
            selectFolder(suggestions[0])
        }
    }

    private func handleUpArrow() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && isInFolderMention {
            selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
        }
    }

    private func handleDownArrow() {
        let suggestions = getSuggestions()
        if !suggestions.isEmpty && isInFolderMention {
            selectedSuggestionIndex = min(suggestions.count - 1, selectedSuggestionIndex + 1)
        }
    }

    private func getSuggestions() -> [WatchedFolder] {
        // A trailing space means the user has "finished" the mention —
        // surface no suggestions so the dropdown dismisses.
        if model.popupSearchText.hasSuffix(" ") { return [] }

        let words = model.popupSearchText.split(separator: " ")
        guard let lastWord = words.last else { return [] }

        let word = String(lastWord)
        guard word.hasPrefix("@") else { return [] }

        let query = String(word.dropFirst()).lowercased()
        if query.isEmpty {
            // Bare "@" — show every watched folder so the user can pick.
            return model.watchedFolders
        }
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
                colors: [Color.brandBlue.opacity(0.9), Color.brandBlue],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .brandBlue.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Popup Folder Chips

private struct PopupFolderChipsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.watchedFolders) { folder in
                    PopupFolderFilterChip(folder: folder)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct PopupFolderFilterChip: View {
    @Environment(AppModel.self) private var model
    let folder: WatchedFolder

    private var isActive: Bool {
        model.popupSearchTokens.contains { $0.kind == .folder && $0.value == folder.name }
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isActive {
                    model.popupSearchTokens.removeAll { $0.kind == .folder && $0.value == folder.name }
                } else {
                    let token = SearchToken(kind: .folder, value: folder.name)
                    model.popupSearchTokens.append(token)
                }
            }
            model.performPopupSearch()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? Color.brandBlue
                    : Color.primary.opacity(0.06),
                in: Capsule()
            )
            .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
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
                                .foregroundStyle(Color.brandBlue)

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
        // A trailing space means the user has "finished" the mention —
        // surface no suggestions so the dropdown dismisses.
        if model.popupSearchText.hasSuffix(" ") { return [] }

        let words = model.popupSearchText.split(separator: " ")
        guard let lastWord = words.last else { return [] }

        let word = String(lastWord)
        guard word.hasPrefix("@") else { return [] }

        let query = String(word.dropFirst()).lowercased()
        if query.isEmpty {
            // Bare "@" — show every watched folder so the user can pick.
            return model.watchedFolders
        }
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
