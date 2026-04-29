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
    // SSE byte buffer — touched only from the URLSession delegate queue,
    // which is a serial OperationQueue we own (see init). Marking it
    // `nonisolated(unsafe)` lets the delegate methods run off-main without
    // hopping to @MainActor for every byte received. Before this change,
    // every `didReceive data:` callback dispatched onto the main actor
    // and ran the full SSE parse + JSON decode there — during a discovery
    // sweep that can be thousands of events per second, the UI thread
    // stalled and the whole app appeared frozen.
    private nonisolated(unsafe) var eventBuffer = ""
    private let maxBufferSize = 1_000_000  // 1MB safety limit

    // Closures are assigned once during `configureStreams` (MainActor) and
    // then invoked from the SSE delegate queue. Mark as `nonisolated(unsafe)`
    // so the delegate callbacks can read them without hopping to MainActor
    // for every event. The closures themselves are responsible for
    // re-entering MainActor before mutating any UI state — see
    // `AppModel.configureStreams`.
    nonisolated(unsafe) var onEvent: ((BackendUpdateEvent) -> Void)?
    nonisolated(unsafe) var onStateChange: ((State) -> Void)?

    nonisolated private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity
        // Dedicated serial queue for SSE delegate callbacks. Serial so
        // `eventBuffer` can be touched without a lock; off-main so SSE
        // parsing/decoding doesn't compete with view updates.
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        delegateQueue.name = "com.filesearch.UpdatesStream.sse"
        session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
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

    /// Parse one or more SSE chunks. Runs on the URLSession delegate queue
    /// (background, serial), NOT on the main actor — see the
    /// `eventBuffer` comment for context. Only the final `onEvent` hop
    /// crosses to MainActor (handled by AppModel.configureStreams).
    nonisolated private func handleReceivedData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        eventBuffer += text

        // Prevent unbounded buffer growth from malformed/incomplete events
        if eventBuffer.count > maxBufferSize {
            print("[UpdatesStream] Buffer overflow (\(eventBuffer.count) chars), clearing")
            eventBuffer = ""
            return
        }

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

    nonisolated private func parseAndEmitEvent(_ eventText: String) {
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
        // We're already on the dedicated serial delegate queue (see init).
        // Parse + decode here; only the resolved BackendUpdateEvent crosses
        // to the main actor, via `onEvent`'s callback in AppModel.
        handleReceivedData(data)
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
