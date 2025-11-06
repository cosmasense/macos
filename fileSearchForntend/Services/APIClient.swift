//
//  APIClient.swift
//  fileSearchForntend
//
//  Main API client for backend communication
//

import Foundation

/// Configuration for the API client
struct APIConfiguration {
    let baseURL: URL
    let timeout: TimeInterval
    
    static let `default` = APIConfiguration(
        baseURL: URL(string: "http://localhost:8080")!,
        timeout: 30.0
    )
}

/// Errors that can occur during API operations
enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case serverError(statusCode: Int, message: String?)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message ?? "Unknown error")"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}

/// Main API client for backend communication
@Observable
class APIClient {
    let configuration: APIConfiguration
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    
    init(configuration: APIConfiguration = .default) {
        self.configuration = configuration
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        self.session = URLSession(configuration: sessionConfig)
        
        // Configure JSON encoder/decoder for date handling
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
        
        self.jsonDecoder = JSONDecoder()
        // Custom date decoder to handle backend format: "2025-10-29T09:19:01"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        self.jsonDecoder.dateDecodingStrategy = .formatted(dateFormatter)
    }
    
    // MARK: - Search
    
    /// Performs a search query against the backend
    /// - Parameter request: The search request parameters
    /// - Returns: Search response with results
    /// - Throws: APIError if the request fails
    func search(_ request: SearchRequest) async throws -> SearchResponse {
        let endpoint = configuration.baseURL.appendingPathComponent("/api/search/")
        
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try jsonEncoder.encode(request)
        } catch {
            throw APIError.decodingError(error)
        }
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8)
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let searchResponse = try jsonDecoder.decode(SearchResponse.self, from: data)
            return searchResponse
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Performs a simple text search
    /// - Parameters:
    ///   - query: The search query string
    ///   - limit: Maximum number of results (default: 50)
    ///   - directory: Optional directory to search within
    /// - Returns: Search response with results
    func search(query: String, limit: Int = 50, directory: String? = nil) async throws -> SearchResponse {
        let request = SearchRequest(query: query, limit: limit, directory: directory)
        return try await search(request)
    }
    
    /// Performs a search with filters
    /// - Parameters:
    ///   - query: The search query string
    ///   - filters: Dictionary of filter key-value pairs
    ///   - limit: Maximum number of results (default: 50)
    ///   - directory: Optional directory to search within
    /// - Returns: Search response with results
    func search(
        query: String,
        filters: [String: String],
        limit: Int = 50,
        directory: String? = nil
    ) async throws -> SearchResponse {
        let request = SearchRequest(query: query, filters: filters, limit: limit, directory: directory)
        return try await search(request)
    }
}

// MARK: - Shared Instance

extension APIClient {
    /// Shared instance for app-wide use
    static let shared = APIClient()
}
