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

                    Button("Test Connection") {
                        testBackendConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func testBackendConnection() {
        // TODO: Implement backend connection test
        print("Testing connection to: \(backendURL)")
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
