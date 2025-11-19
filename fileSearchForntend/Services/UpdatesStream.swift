//
//  UpdatesStream.swift
//  fileSearchForntend
//
//  WebSocket/SSE connection for real-time backend updates
//

import Foundation

@MainActor
class UpdatesStream {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    private var urlSessionTask: URLSessionWebSocketTask?
    private var currentURL: URL?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTimer: Timer?

    var onEvent: ((BackendUpdateEvent) -> Void)?
    var onStateChange: ((State) -> Void)?

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func connect(to baseURL: URL) {
        disconnect()

        // Construct WebSocket URL (convert http:// to ws://)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
        if components.scheme == "http" {
            components.scheme = "ws"
        } else if components.scheme == "https" {
            components.scheme = "wss"
        }
        components.path = "/api/updates"

        guard let wsURL = components.url else {
            onStateChange?(.failed("Invalid WebSocket URL"))
            return
        }

        currentURL = wsURL
        reconnectAttempts = 0
        startConnection()
    }

    nonisolated func disconnect() {
        Task { @MainActor in
            reconnectTimer?.invalidate()
            reconnectTimer = nil
            urlSessionTask?.cancel(with: .goingAway, reason: nil)
            urlSessionTask = nil
            currentURL = nil
            reconnectAttempts = 0
            onStateChange?(.idle)
        }
    }

    private func startConnection() {
        guard let wsURL = currentURL else { return }

        onStateChange?(.connecting)

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: wsURL)

        urlSessionTask = task
        task.resume()

        // Start receiving messages
        receiveMessage()

        // Send ping to confirm connection
        task.sendPing { [weak self] error in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error {
                    self.handleConnectionError(error)
                } else {
                    self.onStateChange?(.connected)
                    self.reconnectAttempts = 0
                }
            }
        }
    }

    private func receiveMessage() {
        urlSessionTask?.receive { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    // Continue receiving
                    self.receiveMessage()

                case .failure(let error):
                    self.handleConnectionError(error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return }
            do {
                let event = try jsonDecoder.decode(BackendUpdateEvent.self, from: data)
                onEvent?(event)
            } catch {
                print("Failed to decode backend update event: \(error)")
            }

        case .data(let data):
            do {
                let event = try jsonDecoder.decode(BackendUpdateEvent.self, from: data)
                onEvent?(event)
            } catch {
                print("Failed to decode backend update event: \(error)")
            }

        @unknown default:
            break
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
