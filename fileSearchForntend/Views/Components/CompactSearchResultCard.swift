//
//  CompactSearchResultCard.swift
//  fileSearchForntend
//
//  Compact search result card for the floating panel
//

import SwiftUI
import UniformTypeIdentifiers

struct CompactSearchResultCard: View {
    let result: SearchResultItem
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File icon and name
            HStack(spacing: 8) {
                Image(systemName: fileIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(fileIconColor)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.file.filename)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let title = result.file.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
            }
            
            // Summary
            if let summary = result.file.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // Footer with relevance score
            HStack {
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                    Text(String(format: "%.0f%%", result.relevanceScore * 100))
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.yellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.yellow.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isHovered ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1),
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
            createDragProvider()
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
    
    private func openFile() {
        let url = URL(fileURLWithPath: result.file.filePath)
        NSWorkspace.shared.open(url)
    }
    
    private func getUTType(for fileExtension: String) -> UTType? {
        let ext = fileExtension.lowercased()
        
        switch ext {
        case "jpg", "jpeg":
            return UTType.jpeg
        case "png":
            return UTType.png
        case "gif":
            return UTType.gif
        case "heic":
            return UTType.heic
        case "tiff", "tif":
            return UTType.tiff
        case "pdf":
            return UTType.pdf
        case "txt":
            return UTType.plainText
        case "html", "htm":
            return UTType.html
        case "json":
            return UTType.json
        case "mp4":
            return UTType.mpeg4Movie
        case "mov":
            return UTType.quickTimeMovie
        case "mp3":
            return UTType.mp3
        default:
            return UTType(filenameExtension: ext)
        }
    }
    
    private func createDragProvider() -> NSItemProvider {
        let url = URL(fileURLWithPath: result.file.filePath)
        
        // Copy file to temp directory - this makes it work like Finder
        var tempFileURL: URL?
        do {
            // Copy file to temp directory
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(result.file.filename)
            
            // Remove if exists
            try? FileManager.default.removeItem(at: tempFile)
            
            // Copy the file
            try FileManager.default.copyItem(at: url, to: tempFile)
            tempFileURL = tempFile
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
