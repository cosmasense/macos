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
    var id: UUID = UUID()
    var name: String
    var path: String
    var progress: Double // 0.0...1.0
    var status: IndexStatus
    var lastModified: Date = Date()
}
