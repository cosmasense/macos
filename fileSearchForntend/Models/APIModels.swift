//
//  APIModels.swift
//  fileSearchForntend
//
//  API request and response models for backend communication
//

import Foundation

// MARK: - File Response

/// Shared API response model for file metadata across endpoints
struct FileResponse: Codable, Identifiable, Equatable {
    let filePath: String
    let filename: String
    let fileExtension: String
    let created: Date
    let modified: Date
    let accessed: Date
    let title: String?
    let summary: String?
    
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
    }
}

// MARK: - Search Models

/// Request body for searching files
struct SearchRequest: Codable {
    let query: String
    let filters: [String: String]?
    let limit: Int
    let directory: String?
    
    init(query: String, filters: [String: String]? = nil, limit: Int = 50, directory: String? = nil) {
        self.query = query
        self.filters = filters
        self.limit = limit
        self.directory = directory
    }
}

/// A single search result
struct SearchResultItem: Codable, Identifiable, Equatable {
    let file: FileResponse
    let relevanceScore: Float
    
    var id: String { file.id }
    
    enum CodingKeys: String, CodingKey {
        case file
        case relevanceScore = "relevance_score"
    }
    
    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.id == rhs.id && lhs.relevanceScore == rhs.relevanceScore
    }
}

/// Response for search queries
struct SearchResponse: Codable {
    let results: [SearchResultItem]
}
