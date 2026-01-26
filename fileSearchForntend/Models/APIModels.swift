//
//  APIModels.swift
//  fileSearchForntend
//
//  API response and request models matching the new backend API
//

import Foundation

// MARK: - File Models

struct FileResponse: Codable, Identifiable, Hashable {
    let filePath: String
    let filename: String
    let fileExtension: String
    let created: Date
    let modified: Date
    let accessed: Date
    let title: String?
    let summary: String?
    let keywords: [String]?

    var id: String { filePath }

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case filename
        case fileExtension = "extension"
        case created
        case modified
        case accessed
        case title
        case summary
        case keywords
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(filePath)
    }

    static func == (lhs: FileResponse, rhs: FileResponse) -> Bool {
        lhs.filePath == rhs.filePath
    }
}

struct FileStatsResponse: Codable {
    let totalFiles: Int
    let totalSize: Int
    let fileTypes: [String: Int]
    let lastIndexed: String?

    enum CodingKeys: String, CodingKey {
        case totalFiles = "total_files"
        case totalSize = "total_size"
        case fileTypes = "file_types"
        case lastIndexed = "last_indexed"
    }
}

// MARK: - Watch Job Models

struct JobResponse: Codable, Identifiable, Hashable {
    let id: Int
    let path: String
    let isActive: Bool
    let recursive: Bool
    let filePattern: String?
    let lastScan: Date?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case isActive = "is_active"
        case recursive
        case filePattern = "file_pattern"
        case lastScan = "last_scan"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: JobResponse, rhs: JobResponse) -> Bool {
        lhs.id == rhs.id
    }
}

struct JobsListResponse: Codable {
    let jobs: [JobResponse]
}

struct WatchRequest: Codable {
    let directoryPath: String

    enum CodingKeys: String, CodingKey {
        case directoryPath = "directory_path"
    }
}

struct WatchResponse: Codable {
    let success: Bool
    let message: String
    let filesIndexed: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case filesIndexed = "files_indexed"
    }
}

struct DeleteJobResponse: Codable {
    let success: Bool
    let message: String
    let jobId: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case jobId = "job_id"
    }
}

// MARK: - Index Models

struct IndexDirectoryRequest: Codable {
    let directoryPath: String

    enum CodingKeys: String, CodingKey {
        case directoryPath = "directory_path"
    }
}

struct IndexDirectoryResponse: Codable {
    let success: Bool
    let message: String
    let filesIndexed: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case filesIndexed = "files_indexed"
    }
}

struct IndexFileRequest: Codable {
    let filePath: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
    }
}

struct IndexFileResponse: Codable {
    let success: Bool
    let message: String
    let fileId: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case fileId = "file_id"
    }
}

// MARK: - Search Models

struct SearchRequest: Codable {
    let query: String
    let directory: String?
    let filters: [String: String]?
    let limit: Int?
}

struct SearchResponse: Codable {
    let results: [SearchResultItem]
}

struct SearchResultItem: Codable, Identifiable, Hashable {
    let file: FileResponse
    let relevanceScore: Double

    var id: String { file.filePath }

    enum CodingKeys: String, CodingKey {
        case file
        case relevanceScore = "relevance_score"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(file.filePath)
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.file.filePath == rhs.file.filePath
    }
}

// MARK: - Status Models

struct StatusResponse: Codable {
    let status: String?
    let jobs: Int?
    let version: String?
}

// MARK: - Backend Update Events (for SSE)

/// Backend SSE event structure
/// Backend sends: {"opcode": "file_parsing", "data": {"path": "...", "filename": "..."}}
struct BackendUpdateEvent: Codable {
    let opcode: EventOpcode
    let data: EventData

    /// Convenience accessors that map backend field names to frontend expectations
    var filePath: String? {
        data.path
    }

    var directoryPath: String? {
        // For directory events, path is the directory
        // For file events, extract directory from file path
        if opcode.isDirectoryEvent {
            return data.path
        }
        return nil
    }

    var errorMessage: String? {
        data.error
    }

    var reason: String? {
        data.reason
    }

    var filename: String? {
        data.filename
    }

    var srcPath: String? {
        data.srcPath
    }

    var destPath: String? {
        data.destPath
    }

    var message: String? {
        data.message
    }
}

/// Nested data payload from backend events
struct EventData: Codable {
    let path: String?
    let filename: String?
    let error: String?
    let reason: String?
    let srcPath: String?
    let destPath: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case path
        case filename
        case error
        case reason
        case srcPath = "src_path"
        case destPath = "dest_path"
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        srcPath = try container.decodeIfPresent(String.self, forKey: .srcPath)
        destPath = try container.decodeIfPresent(String.self, forKey: .destPath)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

enum EventOpcode: String, Codable {
    // Watch management
    case watchStarted = "watch_started"
    case watchAdded = "watch_added"
    case watchRemoved = "watch_removed"

    // Directory processing
    case directoryProcessingStarted = "directory_processing_started"
    case directoryProcessingCompleted = "directory_processing_completed"

    // File processing pipeline
    case fileParsing = "file_parsing"
    case fileParsed = "file_parsed"
    case fileSummarizing = "file_summarizing"
    case fileSummarized = "file_summarized"
    case fileEmbedding = "file_embedding"
    case fileEmbedded = "file_embedded"
    case fileComplete = "file_complete"
    case fileFailed = "file_failed"
    case fileSkipped = "file_skipped"

    // File system events
    case fileCreated = "file_created"
    case fileModified = "file_modified"
    case fileDeleted = "file_deleted"
    case fileMoved = "file_moved"

    // General events
    case statusUpdate = "status_update"
    case error = "error"
    case info = "info"
    case shuttingDown = "shutting_down"

    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = EventOpcode(rawValue: rawValue) ?? .unknown
    }

    /// Whether this opcode represents a directory-level event
    var isDirectoryEvent: Bool {
        switch self {
        case .watchStarted, .watchAdded, .watchRemoved,
             .directoryProcessingStarted, .directoryProcessingCompleted:
            return true
        default:
            return false
        }
    }

    /// Whether this opcode represents a file-level event
    var isFileEvent: Bool {
        switch self {
        case .fileParsing, .fileParsed, .fileSummarizing, .fileSummarized,
             .fileEmbedding, .fileEmbedded, .fileComplete, .fileFailed,
             .fileSkipped, .fileCreated, .fileModified, .fileDeleted, .fileMoved:
            return true
        default:
            return false
        }
    }
}

// MARK: - Deprecated Models (kept for compatibility during migration)

// These models are deprecated as the backend no longer supports summarizer model selection
struct SummarizerModelsResponse: Codable {
    let providers: [SummarizerModelOption]
    let current: String
}

struct SummarizerModelOption: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let description: String?
    let available: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case description
        case available
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
    }
}

// MARK: - Filter Config Models

/// Filter mode - whether patterns are used as blacklist or whitelist
enum FilterMode: String, Codable {
    case blacklist
    case whitelist
}

/// Response containing the current filter configuration
struct FilterConfigResponse: Codable {
    let version: Int
    let mode: String
    // Legacy fields (deprecated but kept for compatibility)
    let exclude: [String]
    let include: [String]
    // Mode-specific pattern storage (NEW)
    let blacklistExclude: [String]
    let blacklistInclude: [String]
    let whitelistInclude: [String]
    let whitelistExclude: [String]
    let configPath: String

    enum CodingKeys: String, CodingKey {
        case version
        case mode
        case exclude
        case include
        case blacklistExclude = "blacklist_exclude"
        case blacklistInclude = "blacklist_include"
        case whitelistInclude = "whitelist_include"
        case whitelistExclude = "whitelist_exclude"
        case configPath = "config_path"
    }
}

/// Request to update filter configuration
struct UpdateFilterConfigRequest: Codable {
    let mode: String?
    // Legacy fields (deprecated but kept for compatibility)
    let exclude: [String]?
    let include: [String]?
    // Mode-specific pattern storage (NEW)
    let blacklistExclude: [String]?
    let blacklistInclude: [String]?
    let whitelistInclude: [String]?
    let whitelistExclude: [String]?
    // Control whether to apply changes immediately
    let applyImmediately: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case exclude
        case include
        case blacklistExclude = "blacklist_exclude"
        case blacklistInclude = "blacklist_include"
        case whitelistInclude = "whitelist_include"
        case whitelistExclude = "whitelist_exclude"
        case applyImmediately = "apply_immediately"
    }
}

/// Response after updating filter configuration
struct UpdateFilterConfigResponse: Codable {
    let success: Bool
    let message: String
    let config: FilterConfigResponse
    let removedCount: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case config
        case removedCount = "removed_count"
    }
}

/// Request to add a filter pattern
struct AddPatternRequest: Codable {
    let pattern: String
    let patternType: String

    enum CodingKeys: String, CodingKey {
        case pattern
        case patternType = "pattern_type"
    }
}

/// Response after adding a pattern
struct AddPatternResponse: Codable {
    let success: Bool
    let message: String
    let removedCount: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case removedCount = "removed_count"
    }
}

/// Request to remove a filter pattern
struct RemovePatternRequest: Codable {
    let pattern: String
    let patternType: String

    enum CodingKeys: String, CodingKey {
        case pattern
        case patternType = "pattern_type"
    }
}

/// Response after removing a pattern
struct RemovePatternResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: - Error Models

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let statusCode, let message):
            if let message = message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error (\(statusCode))"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
