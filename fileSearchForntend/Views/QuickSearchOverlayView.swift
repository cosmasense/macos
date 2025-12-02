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

    @FocusState private var isSearchFocused: Bool
    @State private var lastResultCount: Int = 0

    private var filteredResults: [SearchResultItem] {
        guard model.hideHiddenFiles else { return model.searchResults }
        return model.searchResults.filter { !$0.file.filename.hasPrefix(".") }
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            HStack {
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
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                Color.white.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.4
                    )
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 44, y: 24)
        .shadow(color: Color.accentColor.opacity(0.12), radius: 30, y: 16)
        .onAppear { isSearchFocused = true }
        .onExitCommand { onClose() }
        .onChange(of: filteredResults.count) { _, newValue in
            lastResultCount = newValue
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
        filteredResults.isEmpty ? 220 : 340
    }
}

// MARK: - Overlay Tile

private struct OverlayFileTile: View {
    let result: SearchResultItem

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
        let url = URL(fileURLWithPath: result.file.filePath)
        NSWorkspace.shared.open(url)
    }

    private func dragProvider() -> NSItemProvider {
        let url = URL(fileURLWithPath: result.file.filePath)
        let provider = NSItemProvider()

        provider.registerDataRepresentation(forTypeIdentifier: "public.file-url", visibility: .all) { completion in
            do {
                let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                completion(data, nil)
            } catch {
                completion(url.absoluteURL.dataRepresentation, nil)
            }
            return nil
        }

        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(url.absoluteURL.dataRepresentation, nil)
            return nil
        }

        provider.registerObject(url as NSURL, visibility: .all)
        provider.suggestedName = result.file.filename
        return provider
    }
}
