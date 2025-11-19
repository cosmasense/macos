//
//  SettingsView.swift
//  AI File Organizer
//
//  Settings view with Models and General configuration
//  Designed for easy data integration in the future
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("selectedEmbeddingModel") private var selectedEmbeddingModel = "text-embedding-3-small"
    @AppStorage("launchAtStartup") private var launchAtStartup = false
    @State var showingPanel = false
    @State private var searchText = ""

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Button("Present panel") {
                    showingPanel.toggle()
                }
                .floatingPanel(
                    isPresented: $showingPanel,
                    contentRect: {
                        let screen = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? CGRect.zero
                        let panelWidth: CGFloat = 750
                        let panelHeight: CGFloat = 60
                        
                        return CGRect(
                            x: screen.midX - (panelWidth / 2),  // Center horizontally
                            y: screen.minY + 10,                 // 20 points above the dock
                            width: panelWidth,
                            height: panelHeight
                        )
                    }(),
                    content: {
                        ZStack {
                            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                            
                            HStack(spacing: 12) {
                                // Search icon
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16, weight: .medium))
                                
                                // Search text field
                                TextField("Search files", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 16))
                                    .frame(maxWidth: .infinity)
                                
                                // Clear button (only shown when there's text)
                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Clear")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
  
                )
                // Models Section
                ModelsSection(
                    selectedEmbeddingModel: $selectedEmbeddingModel
                )

                Divider()
                    .padding(.horizontal, -32)

                // General Section
                GeneralSection(
                    launchAtStartup: $launchAtStartup,
                    backendURL: $model.backendURL
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
        .background(.ultraThinMaterial)
    }
}

// MARK: - Models Section

struct ModelsSection: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedEmbeddingModel: String

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 20) {
            Text("Models")
                .font(.system(size: 20, weight: .semibold))

            // LLM Summary Model (Deprecated - backend no longer supports this)
            // Commented out as the backend API has been removed
            /*
            VStack(alignment: .leading, spacing: 8) {
                Text("LLM Summary Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Model selection has been moved to backend configuration")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            */

            // Embedding Model
            VStack(alignment: .leading, spacing: 8) {
                Text("Embedding Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedEmbeddingModel) {
                    ForEach(["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"], id: \.self) { model in
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
    @Environment(AppModel.self) private var model
    @Binding var launchAtStartup: Bool
    @Binding var backendURL: String
    @State private var connectionTestState: ConnectionTestState = .idle
    
    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
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

                    Button("Test Connection") {
                        testBackendConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if connectionTestState == .testing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                switch connectionTestState {
                case .success(let message):
                    StatusText(message: message, color: .green, icon: "checkmark.circle.fill")
                case .failure(let message):
                    StatusText(message: message, color: .red, icon: "xmark.octagon.fill")
                case .idle, .testing:
                    EmptyView()
                }
            }
        }
    }

    private func testBackendConnection() {
        connectionTestState = .testing
        Task {
            let result = await model.testBackendConnection()
            await MainActor.run {
                connectionTestState = result.success ? .success(result.message) : .failure(result.message)
            }
        }
    }
}

private struct StatusText: View {
    let message: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(message)
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
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
