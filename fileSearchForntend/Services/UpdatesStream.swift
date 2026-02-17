//
//  UpdatesStream.swift
//  fileSearchForntend
//
//  Server-Sent Events (SSE) connection for real-time backend updates
//  Updated to use SSE instead of WebSocket per new backend API
//

import Foundation

@MainActor
class UpdatesStream: NSObject {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    private var dataTask: URLSessionDataTask?
    private var currentURL: URL?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTimer: Timer?
    private var session: URLSession?
    private var eventBuffer = ""

    var onEvent: ((BackendUpdateEvent) -> Void)?
    var onStateChange: ((State) -> Void)?

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func connect(to baseURL: URL) {
        // Clean up synchronously (we're on @MainActor) to avoid race conditions
        // where a deferred disconnect Task overwrites the new connection state.
        cleanupConnection()

        // Construct SSE URL (trailing slash required — Quart redirects without it)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
        components.path = "/api/updates/"

        guard let sseURL = components.url else {
            onStateChange?(.failed("Invalid SSE URL"))
            return
        }

        currentURL = sseURL
        reconnectAttempts = 0
        startConnection()
    }

    nonisolated func disconnect() {
        Task { @MainActor in
            self.cleanupConnection()
            self.currentURL = nil
            self.onStateChange?(.idle)
        }
    }

    private func cleanupConnection() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        dataTask?.cancel()
        dataTask = nil
        eventBuffer = ""
        reconnectAttempts = 0
    }

    private func startConnection() {
        guard let sseURL = currentURL else { return }

        onStateChange?(.connecting)

        var request = URLRequest(url: sseURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity

        eventBuffer = ""
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    private func handleReceivedData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        eventBuffer += text

        // SSE format: "data: {json}\n\n" or "data: {json}\n"
        // Split by double newlines to find complete events
        let events = eventBuffer.components(separatedBy: "\n\n")

        // Keep the last incomplete event in the buffer
        if !eventBuffer.hasSuffix("\n\n") {
            eventBuffer = events.last ?? ""
        } else {
            eventBuffer = ""
        }

        // Process complete events
        for eventText in events.dropLast() where !eventText.isEmpty {
            parseAndEmitEvent(eventText)
        }
    }

    private func parseAndEmitEvent(_ eventText: String) {
        // SSE lines can be:
        // data: {json}
        // event: event_name
        // id: event_id
        // : comment

        let lines = eventText.components(separatedBy: "\n")
        var dataLines: [String] = []

        for line in lines {
            if line.hasPrefix("data:") {
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                dataLines.append(data)
            }
        }

        // Join all data lines (in case of multi-line events)
        let jsonString = dataLines.joined(separator: "\n")
        guard !jsonString.isEmpty,
              let jsonData = jsonString.data(using: .utf8) else {
            return
        }

        do {
            let event = try jsonDecoder.decode(BackendUpdateEvent.self, from: jsonData)
            onEvent?(event)
        } catch {
            print("Failed to decode SSE event: \(error)")
            print("JSON string: \(jsonString)")
        }
    }

    private func handleConnectionError(_ error: Error) {
        let errorMessage = error.localizedDescription
        onStateChange?(.failed(errorMessage))

        // Attempt reconnection with exponential backoff
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)

            reconnectTimer?.invalidate()
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.startConnection()
                }
            }
        }
    }
}

// MARK: - URLSessionDataDelegate

extension UpdatesStream: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        if (200...299).contains(httpResponse.statusCode) {
            // Allow data flow immediately — don't defer behind main actor
            completionHandler(.allow)
            Task { @MainActor in
                self.onStateChange?(.connected)
                self.reconnectAttempts = 0
            }
        } else {
            completionHandler(.cancel)
            Task { @MainActor in
                let error = NSError(domain: "SSEError", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"
                ])
                self.handleConnectionError(error)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in
            self.handleReceivedData(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }

        // NSURLErrorCancelled (-999) is emitted whenever we intentionally
        // stop the stream (e.g., switching backends). Don't show that as a failure.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }

        Task { @MainActor in
            self.handleConnectionError(error)
        }
    }
}
