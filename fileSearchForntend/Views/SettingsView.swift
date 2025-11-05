//
//  SettingsView.swift
//  AI File Organizer
//
//  Settings view with Models and General configuration
//  Designed for easy data integration in the future
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedLLMModel") private var selectedLLMModel = "GPT-4"
    @AppStorage("selectedEmbeddingModel") private var selectedEmbeddingModel = "text-embedding-3-small"
    @AppStorage("launchAtStartup") private var launchAtStartup = false
    @AppStorage("backendURL") private var backendURL = "http://localhost:8000"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Models Section
                ModelsSection(
                    selectedLLMModel: $selectedLLMModel,
                    selectedEmbeddingModel: $selectedEmbeddingModel
                )

                Divider()
                    .padding(.horizontal, -32)

                // General Section
                GeneralSection(
                    launchAtStartup: $launchAtStartup,
                    backendURL: $backendURL
                )

                Divider()
                    .padding(.horizontal, -32)

                // Feedback Section
                FeedbackSection()

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Settings")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

// MARK: - Models Section

struct ModelsSection: View {
    @Binding var selectedLLMModel: String
    @Binding var selectedEmbeddingModel: String

    // Placeholder model lists (easy to replace with backend data)
    let llmModels = [
        "GPT-4",
        "GPT-4 Turbo",
        "GPT-3.5 Turbo",
        "Claude 3 Opus",
        "Claude 3 Sonnet",
        "Claude 3 Haiku",
        "Gemini Pro"
    ]

    let embeddingModels = [
        "text-embedding-3-small",
        "text-embedding-3-large",
        "text-embedding-ada-002"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Models")
                .font(.system(size: 20, weight: .semibold))

            // LLM Summary Model
            VStack(alignment: .leading, spacing: 8) {
                Text("LLM Summary Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedLLMModel) {
                    ForEach(llmModels, id: \.self) { model in
                        Text(model)
                            .tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 300, alignment: .leading)
            }

            // Embedding Model
            VStack(alignment: .leading, spacing: 8) {
                Text("Embedding Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedEmbeddingModel) {
                    ForEach(embeddingModels, id: \.self) { model in
                        Text(model)
                            .tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
    }
}

// MARK: - General Section

struct GeneralSection: View {
    @Binding var launchAtStartup: Bool
    @Binding var backendURL: String
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus?

    enum ConnectionStatus {
        case success
        case failure(String)
    }

    private var isValidURL: Bool {
        guard !backendURL.isEmpty,
              let url = URL(string: backendURL),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return false
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.system(size: 20, weight: .semibold))

            // Launch at Startup
            Toggle(isOn: $launchAtStartup) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch at Startup")
                        .font(.system(size: 14, weight: .medium))

                    Text("Automatically open the app when your computer starts")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            // Backend URL
            VStack(alignment: .leading, spacing: 8) {
                Text("Backend URL")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("http://localhost:8000", text: $backendURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                        .font(.system(size: 13, design: .monospaced))
                        .onChange(of: backendURL) { _, _ in
                            connectionStatus = nil
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(
                                    !backendURL.isEmpty && !isValidURL ? Color.red.opacity(0.5) : Color.clear,
                                    lineWidth: 1
                                )
                        )

                    Button(action: {
                        Task {
                            await testBackendConnection()
                        }
                    }) {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                            Text("Testing...")
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTestingConnection || !isValidURL)
                }

                // URL validation warning
                if !backendURL.isEmpty && !isValidURL {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Please enter a valid HTTP or HTTPS URL")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                // Connection status indicator
                if let status = connectionStatus {
                    HStack(spacing: 6) {
                        switch status {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connected successfully")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        case .failure(let message):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Connection failed: \(message)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func testBackendConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }

        // Validate URL format
        guard let url = URL(string: backendURL) else {
            connectionStatus = .failure("Invalid URL format")
            return
        }

        // Add /health endpoint for health check
        let healthURL = url.appendingPathComponent("health")

        do {
            var request = URLRequest(url: healthURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 5.0

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    connectionStatus = .success
                } else {
                    connectionStatus = .failure("Server returned status code \(httpResponse.statusCode)")
                }
            } else {
                connectionStatus = .failure("Invalid server response")
            }
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost:
                connectionStatus = .failure("Cannot reach server")
            case .timedOut:
                connectionStatus = .failure("Connection timed out")
            default:
                connectionStatus = .failure(error.localizedDescription)
            }
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Feedback Section

struct FeedbackSection: View {
    @State private var showingFeedbackSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Support")
                .font(.system(size: 20, weight: .semibold))

            Button(action: {
                showingFeedbackSheet = true
            }) {
                Label("Send Feedback", systemImage: "envelope")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .sheet(isPresented: $showingFeedbackSheet) {
            FeedbackSheetView()
        }
    }
}

// MARK: - Feedback Sheet

struct FeedbackSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""
    @State private var feedbackType: FeedbackType = .feature

    enum FeedbackType: String, CaseIterable, Identifiable {
        case bug = "Bug Report"
        case feature = "Feature Request"
        case general = "General Feedback"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Send Feedback")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Feedback Type
                Picker("Type", selection: $feedbackType) {
                    ForEach(FeedbackType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                // Feedback Text
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Feedback")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $feedbackText)
                        .font(.system(size: 13))
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        )
                }

                // Buttons
                HStack {
                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Send") {
                        sendFeedback()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(feedbackText.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private func sendFeedback() {
        // TODO: Implement feedback submission
        print("Feedback Type: \(feedbackType.rawValue)")
        print("Feedback: \(feedbackText)")
        dismiss()
    }
}

#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
}
