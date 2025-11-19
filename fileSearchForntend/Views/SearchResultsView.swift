//
//  SearchResultsView.swift
//  fileSearchForntend
//
//  Displays search results with file metadata
//

import SwiftUI
import UniformTypeIdentifiers

struct SearchResultsView: View {
    @Environment(AppModel.self) private var model
    
    var body: some View {
        VStack(spacing: 0) {
            if model.isSearching {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Searching...")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 60)
            } else if let error = model.searchError {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red.opacity(0.7))
                    
                    Text("Search Error")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button("Try Again") {
                        model.clearSearchResults()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 60)
            } else if model.searchResults.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    
                    Text("No results found")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("Try a different search query")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 60)
            } else {
                // Results list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(model.searchResults.count) results")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            model.clearSearchResults()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                Text("Clear")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.searchResults) { result in
                                SearchResultRow(result: result)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResultItem
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // File icon
                Image(systemName: fileIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(fileIconColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Filename
                    Text(result.file.filename)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    // File path
                    Text(result.file.filePath)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Relevance score
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                    Text(String(format: "%.0f%%", result.relevanceScore * 100))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.yellow.opacity(0.15))
                .clipShape(Capsule())
            }
            
            // Title and summary if available
            if let title = result.file.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            
            if let summary = result.file.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            // Metadata
            HStack(spacing: 16) {
                Label(
                    formatDate(result.file.modified),
                    systemImage: "calendar"
                )
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                
                if !result.file.fileExtension.isEmpty {
                    Label(
                        result.file.fileExtension.uppercased(),
                        systemImage: "doc"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isHovered ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            openFile()
        }
        .onDrag {
            let url = URL(fileURLWithPath: result.file.filePath)
            let itemProvider = NSItemProvider()
            
            // Register the file URL
            itemProvider.registerFileRepresentation(forTypeIdentifier: "public.file-url", visibility: .all) { completion in
                completion(url, true, nil)
                return nil
            }
            
            // Register the actual file data with appropriate UTType
            if let utType = UTType(filenameExtension: result.file.fileExtension) {
                itemProvider.registerFileRepresentation(forTypeIdentifier: utType.identifier, visibility: .all) { completion in
                    completion(url, true, nil)
                    return nil
                }
            }
            
            // Also register as NSURL for backwards compatibility
            itemProvider.registerObject(url as NSURL, visibility: .all)
            
            return itemProvider
        }
    }
    
    private var fileIcon: String {
        switch result.file.fileExtension.lowercased() {
        case "pdf":
            return "doc.fill"
        case "txt", "md":
            return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif", "heic":
            return "photo.fill"
        case "mov", "mp4", "avi":
            return "video.fill"
        case "mp3", "wav", "aac":
            return "music.note"
        case "zip", "rar", "7z":
            return "archivebox.fill"
        case "swift", "py", "js", "java", "cpp", "c", "h":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }
    
    private var fileIconColor: Color {
        switch result.file.fileExtension.lowercased() {
        case "pdf":
            return .red
        case "txt", "md":
            return .blue
        case "jpg", "jpeg", "png", "gif", "heic":
            return .orange
        case "mov", "mp4", "avi":
            return .purple
        case "mp3", "wav", "aac":
            return .pink
        case "swift", "py", "js", "java", "cpp", "c", "h":
            return .green
        default:
            return .gray
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func openFile() {
        let url = URL(fileURLWithPath: result.file.filePath)
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    let model = AppModel()
    model.searchResults = [
        SearchResultItem(
            file: FileResponse(
                filePath: "/Users/you/Documents/example.pdf",
                filename: "example.pdf",
                fileExtension: "pdf",
                created: Date().addingTimeInterval(-86400 * 30),
                modified: Date().addingTimeInterval(-86400 * 2),
                accessed: Date(),
                title: "Example Document",
                summary: "This is an example document with some content for testing."
            ),
            relevanceScore: 0.95
        ),
        SearchResultItem(
            file: FileResponse(
                filePath: "/Users/you/Documents/notes.txt",
                filename: "notes.txt",
                fileExtension: "txt",
                created: Date().addingTimeInterval(-86400 * 10),
                modified: Date().addingTimeInterval(-86400),
                accessed: Date(),
                title: "My Notes",
                summary: "Quick notes about various topics."
            ),
            relevanceScore: 0.78
        )
    ]
    
    return SearchResultsView()
        .environment(model)
        .frame(width: 680, height: 500)
}
