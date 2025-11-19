//
//  SearchResultsView.swift
//  fileSearchForntend
//
//  Displays search results with loading and error states
//

import SwiftUI

struct SearchResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Loading state
                    if model.isSearching {
                        LoadingStateView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    }
                    // Error state
                    else if let error = model.searchError {
                        ErrorStateView(error: error)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                    // Results
                    else if !model.searchResults.isEmpty {
                        ResultsListView(results: model.searchResults)
                    }
                    // Empty results
                    else {
                        EmptyResultsView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    }
                }
            }
            .frame(height: geometry.size.height)
        }
    }
}

// MARK: - Loading State

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(.circular)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(results) { result in
                    SearchResultRow(result: result)
                }
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResultItem
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            openFile()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // File name
                HStack(spacing: 8) {
                    Image(systemName: fileIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                        .frame(width: 20)

                    Text(result.filename)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    // Relevance score if available
                    if let score = result.relevanceScore {
                        Text(String(format: "%.0f%%", score * 100))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.5), in: Capsule())
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.quaternary)
                        .opacity(isHovered ? 1 : 0)
                }

                // File path
                Text(result.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 28)

                // Summary if available
                if let summary = result.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.leading, 28)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var fileIcon: String {
        let ext = (result.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.fill"
        case "doc", "docx", "txt", "rtf":
            return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "heic":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv":
            return "video.fill"
        case "mp3", "wav", "aac", "flac":
            return "music.note"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox.fill"
        case "swift", "py", "js", "ts", "java", "cpp", "c", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "xls", "xlsx", "csv":
            return "tablecells.fill"
        case "ppt", "pptx":
            return "rectangle.on.rectangle.angled"
        default:
            return "doc.fill"
        }
    }

    private func openFile() {
        let url = URL(fileURLWithPath: result.path)
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    SearchResultsView()
        .environment(AppModel())
        .frame(width: 800, height: 600)
}
