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

struct BackendUpdateEvent: Codable {
    let opcode: EventOpcode
    let filePath: String?
    let directoryPath: String?
    let errorMessage: String?
    let progress: Double?

    enum CodingKeys: String, CodingKey {
        case opcode
        case filePath = "file_path"
        case directoryPath = "directory_path"
        case errorMessage = "error_message"
        case progress
    }
}

enum EventOpcode: String, Codable {
    case watchStarted = "watch_started"
    case directoryProcessingStarted = "directory_processing_started"
    case directoryProcessingCompleted = "directory_processing_completed"
    case fileParsing = "file_parsing"
    case fileParsed = "file_parsed"
    case fileSummarizing = "file_summarizing"
    case fileSummarized = "file_summarized"
    case fileEmbedding = "file_embedding"
    case fileEmbedded = "file_embedded"
    case fileComplete = "file_complete"
    case fileFailed = "file_failed"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = EventOpcode(rawValue: rawValue) ?? .unknown
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
