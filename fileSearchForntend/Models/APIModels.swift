//
//  APIModels.swift
//  fileSearchForntend
//
//  API response and request models
//

import Foundation

// MARK: - Watched Directory Models

struct WatchedDirectoryResponse: Codable {
    let id: Int
    let normalizedPath: String
    let displayName: String?
    let recursive: Bool
    let filePattern: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case normalizedPath = "normalized_path"
        case displayName = "display_name"
        case recursive
        case filePattern = "file_pattern"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Search Models

struct SearchResponse: Codable {
    let results: [SearchResultItem]
    let query: String
    let totalResults: Int?

    enum CodingKeys: String, CodingKey {
        case results
        case query
        case totalResults = "total_results"
    }
}

struct SearchResultItem: Codable, Identifiable, Hashable {
    let id: String
    let path: String
    let filename: String
    let summary: String?
    let relevanceScore: Double?
    let lastModified: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case filename
        case summary
        case relevanceScore = "relevance_score"
        case lastModified = "last_modified"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Summarizer Models

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
        // Default to true if not provided
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
    }
}

// MARK: - Status Models

struct StatusResponse: Codable {
    let status: String
    let jobs: Int
    let version: String?
}

// MARK: - Backend Update Events

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
