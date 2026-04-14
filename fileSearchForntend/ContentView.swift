//
//  ContentView.swift
//  fileSearchForntend
//
//  Main app layout: HomeView with floating action buttons that open popovers.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
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

            // Tap-outside dismiss layer
            if showFoldersPopover || showProcessingPopover {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showFoldersPopover = false
                        showProcessingPopover = false
                    }
            }

            // Floating action buttons + inline dropdown panels
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
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
            .padding(.top, 10)
            .padding(.trailing, 24)
            .opacity(isSearchActive ? 0 : 1)
            .offset(y: isSearchActive ? -60 : 0)
            .allowsHitTesting(!isSearchActive)
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
            Color.brandBlue.opacity(0.12)

            VStack(spacing: 14) {
                Image(systemName: "plus.rectangle.on.folder.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.brandBlue)
                Text("Drop to add folder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.brandBlue.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 6)
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
                ScrollView {
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundStyle(.primary)
                .frame(width: 28)

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
    private var statusIcon: some View {
        switch folder.status {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
        case .indexing:
            ProgressView()
                .controlSize(.small)
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
