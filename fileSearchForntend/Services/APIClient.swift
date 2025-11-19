//
//  APIClient.swift
//  fileSearchForntend
//
//  HTTP client for backend API communication
//

import Foundation

class APIClient {
    static let shared = APIClient()

    private var baseURL: URL

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(baseURL: URL = URL(string: "http://localhost:8000")!) {
        self.baseURL = baseURL
    }

    func currentBaseURL() -> URL {
        baseURL
    }

    func updateBaseURL(_ url: URL) {
        baseURL = url
    }

    // MARK: - Status

    func fetchStatus() async throws -> StatusResponse {
        let url = baseURL.appendingPathComponent("/api/status")
        return try await get(url: url)
    }

    // MARK: - Watched Directories

    func fetchWatchedDirectories() async throws -> [WatchedDirectoryResponse] {
        let url = baseURL.appendingPathComponent("/api/watched")
        return try await get(url: url)
    }

    func startWatchingDirectory(path: String) async throws -> WatchedDirectoryResponse {
        let url = baseURL.appendingPathComponent("/api/watch")
        let body = ["path": path]
        return try await post(url: url, body: body)
    }

    func indexDirectory(path: String) async throws -> StatusResponse {
        let url = baseURL.appendingPathComponent("/api/index")
        let body = ["path": path]
        return try await post(url: url, body: body)
    }

    // MARK: - Search

    func search(
        query: String,
        filters: [String: String]? = nil,
        limit: Int = 50,
        directory: String? = nil
    ) async throws -> SearchResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/search"), resolvingAgainstBaseURL: true)!
        var queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "\(limit)")]

        if let directory = directory {
            queryItems.append(URLQueryItem(name: "directory", value: directory))
        }

        if let filters = filters {
            for (key, value) in filters {
                queryItems.append(URLQueryItem(name: key, value: value))
            }
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        return try await get(url: url)
    }

    // MARK: - Summarizer Models

    func fetchSummarizerModels() async throws -> SummarizerModelsResponse {
        let url = baseURL.appendingPathComponent("/api/summarizer/models")
        return try await get(url: url)
    }

    func selectSummarizerModel(provider: String) async throws -> SummarizerModelsResponse {
        let url = baseURL.appendingPathComponent("/api/summarizer/select")
        let body = ["provider": provider]
        return try await post(url: url, body: body)
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        return try handleResponse(data: data, response: response)
    }

    private func post<T: Decodable>(url: URL, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        return try handleResponse(data: data, response: response)
    }

    private func handleResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = try? JSONDecoder().decode([String: String].self, from: data)
            throw APIError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorMessage?["error"] ?? errorMessage?["message"]
            )
        }

        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
