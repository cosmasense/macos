//
//  APIClient.swift
//  fileSearchForntend
//
//  HTTP client for backend API communication
//  Updated to match new backend API specifications
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

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = APIClient.iso8601Formatter.date(from: raw) {
                return date
            }
            if let date = APIClient.iso8601WithFractional.date(from: raw) {
                return date
            }
            if let date = APIClient.plainDateFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(raw)")
        }
        return decoder
    }()

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(baseURL: URL = URL(string: "http://localhost:60534")!) {
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
        let url = baseURL.appendingPathComponent("/api/status/")
        return try await get(url: url)
    }

    // MARK: - Watch Jobs (formerly Watched Directories)

    func fetchWatchJobs() async throws -> JobsListResponse {
        let url = baseURL.appendingPathComponent("/api/watch/jobs")
        return try await get(url: url)
    }

    func startWatchingDirectory(path: String) async throws -> WatchResponse {
        let url = baseURL.appendingPathComponent("/api/watch/")
        let request = WatchRequest(directoryPath: path)
        return try await post(url: url, body: request)
    }

    func deleteWatchJob(jobId: Int) async throws -> DeleteJobResponse {
        let url = baseURL.appendingPathComponent("/api/watch/jobs/\(jobId)")
        return try await delete(url: url)
    }

    // MARK: - Indexing

    func indexDirectory(path: String) async throws -> IndexDirectoryResponse {
        let url = baseURL.appendingPathComponent("/api/index/directory/")
        let request = IndexDirectoryRequest(directoryPath: path)
        return try await post(url: url, body: request)
    }

    func indexFile(path: String) async throws -> IndexFileResponse {
        let url = baseURL.appendingPathComponent("/api/index/file/")
        let request = IndexFileRequest(filePath: path)
        return try await post(url: url, body: request)
    }

    // MARK: - Search

    func search(
        query: String,
        directory: String? = nil,
        filters: [String: String]? = nil,
        limit: Int = 50
    ) async throws -> SearchResponse {
        let url = baseURL.appendingPathComponent("/api/search/")
        let request = SearchRequest(
            query: query,
            directory: directory,
            filters: filters,
            limit: limit
        )
        return try await post(url: url, body: request)
    }

    // MARK: - Files

    func fetchFileStats() async throws -> FileStatsResponse {
        let url = baseURL.appendingPathComponent("/api/files/stats")
        return try await get(url: url)
    }

    func fetchFile(fileId: Int) async throws -> FileResponse {
        let url = baseURL.appendingPathComponent("/api/files/\(fileId)/")
        return try await get(url: url)
    }

    // MARK: - Filter Configuration

    func fetchFilterConfig() async throws -> FilterConfigResponse {
        let url = baseURL.appendingPathComponent("/api/filters/config")
        return try await get(url: url)
    }

    func updateFilterConfig(
        mode: String? = nil,
        exclude: [String]? = nil,
        include: [String]? = nil,
        blacklistExclude: [String]? = nil,
        blacklistInclude: [String]? = nil,
        whitelistInclude: [String]? = nil,
        whitelistExclude: [String]? = nil,
        applyImmediately: Bool = true
    ) async throws -> UpdateFilterConfigResponse {
        let url = baseURL.appendingPathComponent("/api/filters/config")
        let request = UpdateFilterConfigRequest(
            mode: mode,
            exclude: exclude,
            include: include,
            blacklistExclude: blacklistExclude,
            blacklistInclude: blacklistInclude,
            whitelistInclude: whitelistInclude,
            whitelistExclude: whitelistExclude,
            applyImmediately: applyImmediately
        )
        return try await put(url: url, body: request)
    }

    func applyFilterChanges() async throws -> UpdateFilterConfigResponse {
        let url = baseURL.appendingPathComponent("/api/filters/apply")
        // Empty struct for POST with no body
        struct EmptyBody: Encodable {}
        return try await post(url: url, body: EmptyBody())
    }

    func addFilterPattern(pattern: String, patternType: String = "exclude") async throws -> AddPatternResponse {
        let url = baseURL.appendingPathComponent("/api/filters/pattern")
        let request = AddPatternRequest(pattern: pattern, patternType: patternType)
        return try await post(url: url, body: request)
    }

    func removeFilterPattern(pattern: String, patternType: String = "exclude") async throws -> RemovePatternResponse {
        let url = baseURL.appendingPathComponent("/api/filters/pattern")
        let request = RemovePatternRequest(pattern: pattern, patternType: patternType)
        return try await deleteWithBody(url: url, body: request)
    }

    func resetFilterConfig() async throws -> UpdateFilterConfigResponse {
        let url = baseURL.appendingPathComponent("/api/filters/reset")
        return try await postEmpty(url: url)
    }

    func fetchDefaultFilterConfig() async throws -> FilterConfigResponse {
        let url = baseURL.appendingPathComponent("/api/filters/defaults")
        return try await get(url: url)
    }

    // MARK: - Queue

    func fetchQueueStatus() async throws -> QueueStatusResponse {
        let url = baseURL.appendingPathComponent("/api/queue/status")
        return try await get(url: url)
    }

    func pauseQueue() async throws -> QueueActionResponse {
        struct EmptyBody: Encodable {}
        let url = baseURL.appendingPathComponent("/api/queue/pause")
        return try await post(url: url, body: EmptyBody())
    }

    func resumeQueue() async throws -> QueueActionResponse {
        struct EmptyBody: Encodable {}
        let url = baseURL.appendingPathComponent("/api/queue/resume")
        return try await post(url: url, body: EmptyBody())
    }

    func fetchQueueItems() async throws -> QueueItemsResponse {
        let url = baseURL.appendingPathComponent("/api/queue/items")
        return try await get(url: url)
    }

    func removeQueueItem(itemId: String) async throws -> QueueActionResponse {
        let url = baseURL.appendingPathComponent("/api/queue/items/\(itemId)")
        return try await delete(url: url)
    }

    // MARK: - Scheduler

    func fetchScheduler() async throws -> SchedulerResponse {
        let url = baseURL.appendingPathComponent("/api/queue/scheduler")
        return try await get(url: url)
    }

    func updateScheduler(
        enabled: Bool? = nil,
        combineMode: String? = nil,
        checkIntervalSeconds: Int? = nil,
        rules: [SchedulerRuleRequest]? = nil
    ) async throws -> SchedulerResponse {
        let url = baseURL.appendingPathComponent("/api/queue/scheduler")
        let request = SchedulerUpdateRequest(
            enabled: enabled,
            combineMode: combineMode,
            checkIntervalSeconds: checkIntervalSeconds,
            rules: rules
        )
        return try await put(url: url, body: request)
    }

    // MARK: - System Metrics

    func fetchSystemMetrics() async throws -> MetricsResponse {
        let url = baseURL.appendingPathComponent("/api/queue/metrics")
        return try await get(url: url)
    }

    // MARK: - Deprecated Summarizer Models (backend no longer supports these)

    @available(*, deprecated, message: "Backend no longer supports summarizer model selection")
    func fetchSummarizerModels() async throws -> SummarizerModelsResponse {
        throw APIError.serverError(statusCode: 404, message: "Summarizer models API has been removed")
    }

    @available(*, deprecated, message: "Backend no longer supports summarizer model selection")
    func selectSummarizerModel(provider: String) async throws -> SummarizerModelsResponse {
        throw APIError.serverError(statusCode: 404, message: "Summarizer models API has been removed")
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        return try handleResponse(data: data, response: response)
    }

    private func post<T: Encodable, R: Decodable>(url: URL, body: T) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        request.httpBody = try jsonEncoder.encode(body)

        let (data, response) = try await session.data(for: request)
        return try handleResponse(data: data, response: response)
    }

    private func delete<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        return try handleResponse(data: data, response: response)
    }

    private func put<T: Encodable, R: Decodable>(url: URL, body: T) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        request.httpBody = try jsonEncoder.encode(body)

        let (data, response) = try await session.data(for: request)
        return try handleResponse(data: data, response: response)
    }

    private func deleteWithBody<T: Encodable, R: Decodable>(url: URL, body: T) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        request.httpBody = try jsonEncoder.encode(body)

        let (data, response) = try await session.data(for: request)
        return try handleResponse(data: data, response: response)
    }

    private func postEmpty<R: Decodable>(url: URL) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
