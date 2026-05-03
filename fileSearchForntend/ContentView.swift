//
//  ContentView.swift
//  fileSearchForntend
//
//  Main app layout: HomeView with floating action buttons that open popovers.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.zoomToPopup) private var zoomToPopup
    @State private var showFolderPicker = false
    @State private var showFoldersPopover = false
    @State private var showProcessingPopover = false
    @State private var isDropTargeted = false

    private var isSearchActive: Bool {
        model.isSearchFieldFocused || !model.searchResults.isEmpty || model.isSearching || model.searchError != nil
    }

    var body: some View {
        @Bindable var model = model

        ZStack(alignment: .topTrailing) {
            HomeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Full-window tap catcher that dismisses any open popover.
            // Sits between HomeView and the popover VStack so taps on the
            // buttons/popover (above it in z-order) still hit them, while
            // taps on the title-bar/header area or any other empty surface
            // dismiss. NSEvent-based ClickOutsideDismissMonitor below
            // handles bounds outside the SwiftUI hit-test area; this layer
            // covers the spot the AppKit-level monitor misses (the
            // title-bar drag region absorbs leftMouseDown before the local
            // monitor sees it).
            if showFoldersPopover || showProcessingPopover {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showFoldersPopover = false
                        showProcessingPopover = false
                    }
                    .transition(.identity)
            }

            // Floating action buttons + inline dropdown panels
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Group {
                        ActionPillButton(
                            title: "Add Folder",
                            systemImage: "plus"
                        ) {
                            showFoldersPopover = false
                            showProcessingPopover = false
                            showFolderPicker = true
                        }

                        ActionPillButton(
                            title: "View Folders",
                            systemImage: "folder.fill"
                        ) {
                            showProcessingPopover = false
                            showFoldersPopover.toggle()
                        }

                        ActionPillButton(
                            title: "Processing",
                            systemImage: "arrow.triangle.2.circlepath",
                            badge: (model.queueStatus?.totalItems).flatMap { $0 > 0 ? $0 : nil }
                        ) {
                            showFoldersPopover = false
                            showProcessingPopover.toggle()
                        }
                    }
                    .opacity(isSearchActive ? 0 : 1)
                    .offset(y: isSearchActive ? -60 : 0)
                    .allowsHitTesting(!isSearchActive)

                    WindowControlButton(systemImage: "arrow.down.right.and.arrow.up.left") {
                        zoomToPopup()
                    }
                    .help("Collapse to Quick Search")
                }

                if showFoldersPopover {
                    FoldersPopover()
                        .environment(model)
                        .frame(width: 440, height: 340)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }

                if showProcessingPopover {
                    ProcessingPopover()
                        .environment(model)
                        .frame(width: 480, height: 380)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 20)
            .background(
                // Passive click-outside dismissal. Uses an NSEvent monitor
                // instead of a full-window tap layer, because a tap-layer
                // hit-tests every mouse event and would steal drag-out
                // gestures on the search results behind the popover.
                ClickOutsideDismissMonitor(
                    isActive: showFoldersPopover || showProcessingPopover,
                    onOutsideClick: {
                        showFoldersPopover = false
                        showProcessingPopover = false
                    }
                )
            )
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isSearchActive)
            .animation(.easeOut(duration: 0.2), value: showFoldersPopover)
            .animation(.easeOut(duration: 0.2), value: showProcessingPopover)

            // Drop overlay — shown while dragging a folder over the window
            if isDropTargeted {
                DropTargetOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: model.modelAvailabilityWarning)
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleFolderDrop(providers: providers)
        }
        .task {
            // Two-tier polling: status (counts) is tiny JSON and drives the
            // badge, so poll fast. Failed/recent lists can be huge (10k+
            // failures with error strings), so poll much less often — a
            // 4 s cadence there was stacking 60 s requests and DDoS'ing
            // the backend.
            var tick = 0
            while !Task.isCancelled {
                await model.refreshQueueStatus()
                if tick % 8 == 0 {  // ~every 32s
                    await model.refreshFailedFiles()
                    await model.refreshRecentFiles()
                }
                tick &+= 1
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.addFolder(url: url)
            }
        }
    }

    private func handleFolderDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
                Task { @MainActor in
                    model.addFolder(url: url)
                }
            }
        }
        return accepted
    }
}

// MARK: - Drop Target Overlay

struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            // Frosted white wash — blurs whatever is behind and lightens
            // the whole window so the call-to-action pops.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.45))

            // Match the empty-state "Drag and drop to add folders" copy in
             // RecentSearchesView: same 16pt medium secondary-gray type, and
             // the line (non-filled) SF Symbol tinted to match.
            VStack(spacing: 14) {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop to add folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Click-Outside Dismiss Monitor

/// Installs an NSEvent local monitor that dismisses the popover when the
/// user clicks outside its bounds *or* presses Esc. The mouse monitor
/// observes events passively — it never consumes them — so drag-out
/// gestures on views behind the popover (e.g. dragging a search result to
/// Finder) keep working. The Esc monitor consumes the event so the search
/// field's own Esc handler doesn't also clear the query.
private struct ClickOutsideDismissMonitor: NSViewRepresentable {
    let isActive: Bool
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onOutsideClick = onOutsideClick
        // Only touch the monitor after the view is in a window — installing
        // a local event monitor before the host has attached to a window
        // means the closure captures a dangling weak reference on the very
        // first event, and AppKit occasionally promotes that into a fatal
        // "invalid reuse after initialization failure" during app launch.
        if nsView.window != nil {
            context.coordinator.syncMonitor(isActive: isActive)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.syncMonitor(isActive: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onOutsideClick: onOutsideClick) }

    final class Coordinator {
        weak var hostView: NSView?
        var onOutsideClick: () -> Void
        private var mouseMonitor: Any?
        private var keyMonitor: Any?

        init(onOutsideClick: @escaping () -> Void) {
            self.onOutsideClick = onOutsideClick
        }

        deinit {
            // Defensive: clean up monitors even if SwiftUI never calls
            // dismantleNSView (e.g., the parent View disappears without a
            // tidy teardown path).
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
            }
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        func syncMonitor(isActive: Bool) {
            if isActive, mouseMonitor == nil {
                let mouseToken = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    guard
                        let self,
                        let host = self.hostView,
                        let window = host.window,
                        event.window === window
                    else { return event }

                    let locInHost = host.convert(event.locationInWindow, from: nil)
                    if !host.bounds.contains(locInHost) {
                        self.onOutsideClick()
                    }
                    return event
                }
                self.mouseMonitor = mouseToken
            } else if !isActive, let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }

            if isActive, keyMonitor == nil {
                // Esc (keyCode 53) closes the popover. Consumed so it
                // doesn't also bubble up to HomeView's Esc handler, which
                // would clear the search query as a side effect.
                let keyToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard
                        let self,
                        let host = self.hostView,
                        let window = host.window,
                        event.window === window,
                        event.keyCode == 53
                    else { return event }

                    self.onOutsideClick()
                    return nil
                }
                self.keyMonitor = keyToken
            } else if !isActive, let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }
}

// MARK: - Pill Button

struct ActionPillButton: View {
    let title: String
    let systemImage: String
    var badge: Int? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)

                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay(alignment: .top) {
            if isHovering {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .fixedSize()
                    .offset(y: 52)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Folders Popover

struct FoldersPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isLoadingWatchedFolders {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.watchedFolders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("No folders watched yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Use “Add Folder” to start indexing")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(model.watchedFolders) { folder in
                            CompactFolderRow(folder: folder)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
            }
        }
    }
}

// MARK: - Compact Folder Row (for popover)

struct CompactFolderRow: View {
    @Environment(AppModel.self) private var model
    let folder: WatchedFolder
    @State private var confirmDelete = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 20))
                    .foregroundStyle(isExpanded ? Color.brandBlue : .primary)
                    .frame(width: 28)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(folder.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                statusIcon

                Button {
                    model.reindex(folder: folder)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Re-index")
                .disabled(folder.status == .indexing)

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isExpanded ? Color.primary.opacity(0.04) : .clear)
        )
        .confirmationDialog(
            "Remove \(folder.name)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { model.removeFolder(folder) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            detailRow(label: "Status", value: folder.status.rawValue.capitalized)

            if folder.totalFileCount > 0 {
                let processed = folder.indexedFileCount + folder.skippedFileCount
                detailRow(label: "Progress", value: "\(processed) / \(folder.totalFileCount) files (\(Int(folder.progress * 100))%)")
            } else if folder.indexedFileCount > 0 {
                detailRow(label: "Indexed", value: "\(folder.indexedFileCount) files")
            }

            if folder.skippedFileCount > 0 {
                detailRow(label: "Skipped", value: "\(folder.skippedFileCount) files")
            }

            detailRow(label: "Last modified", value: formatDate(folder.lastModified))
            detailRow(label: "Recursive", value: folder.recursive ? "Yes" : "No")

            if let pattern = folder.filePattern, !pattern.isEmpty {
                detailRow(label: "Pattern", value: pattern)
            }

            if let issue = folder.lastIssueMessage, !issue.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last issue")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(issue)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
            }

            Button {
                openInFinder()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10))
                    Text("Show in Finder")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.brandBlue)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func openInFinder() {
        let url = URL(fileURLWithPath: folder.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch folder.status {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
        case .indexing:
            RotatingIndexingIcon()
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
        }
    }
}

// MARK: - Rotating Indexing Icon

/// Small spinning icon shown next to a folder row while it's actively
/// indexing. Native ProgressView animates fine on macOS but reads as a
/// static asterisk at small sizes, so we drive the rotation explicitly
/// to make "this folder is working" obvious.
private struct RotatingIndexingIcon: View {
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "arrow.2.circlepath")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.brandBlue)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Processing Popover

struct ProcessingPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        QueueContentView()
    }
}

// MARK: - Model Warning Banner

struct ModelWarningBanner: View {
    let warning: AppModel.ModelAvailabilityWarning
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Summarizer model unavailable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(warning.provider): \(warning.model)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(warning.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 280, alignment: .leading)

            VStack(spacing: 4) {
                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Retry model check")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
        .environment(AppModel())
        .frame(width: 900, height: 600)
}
