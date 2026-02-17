//
//  WatchedFolder.swift
//  fileSearchForntend
//
//  Data model for folders being watched/indexed by the backend
//

import Foundation

enum IndexStatus: String, Codable {
    case idle
    case indexing
    case paused
    case error
    case complete
}

struct WatchedFolder: Identifiable, Hashable, Codable {
    var backendID: Int?
    var name: String
    var path: String
    var progress: Double // 0.0...1.0
    var status: IndexStatus
    var lastModified: Date
    var recursive: Bool
    var filePattern: String?
    var lastIssueMessage: String? = nil
    var lastIssueDate: Date? = nil
    var skippedFileCount: Int = 0
    
    var id: String { path }
    
    init(
        backendID: Int? = nil,
        name: String? = nil,
        path: String,
        progress: Double = 0.0,
        status: IndexStatus = .idle,
        lastModified: Date = Date(),
        recursive: Bool = true,
        filePattern: String? = nil,
        lastIssueMessage: String? = nil,
        lastIssueDate: Date? = nil,
        skippedFileCount: Int = 0
    ) {
        self.backendID = backendID
        let normalizedPath = (path as NSString).standardizingPath
        self.path = normalizedPath
        let resolvedName = name ?? URL(fileURLWithPath: normalizedPath).lastPathComponent
        self.name = resolvedName.isEmpty ? normalizedPath : resolvedName
        self.progress = progress
        self.status = status
        self.lastModified = lastModified
        self.recursive = recursive
        self.filePattern = filePattern
        self.lastIssueMessage = lastIssueMessage
        self.lastIssueDate = lastIssueDate
        self.skippedFileCount = skippedFileCount
    }
    
    init(response: JobResponse) {
        let folderName = URL(fileURLWithPath: response.path).lastPathComponent
        // isActive means the watch job is enabled, not that indexing is complete.
        // Real status/progress comes from SSE events; default to idle.
        self.init(
            backendID: response.id,
            name: folderName,
            path: response.path,
            progress: 0.0,
            status: .idle,
            lastModified: response.updatedAt ?? response.createdAt ?? Date(),
            recursive: response.recursive,
            filePattern: response.filePattern
        )
    }
}
