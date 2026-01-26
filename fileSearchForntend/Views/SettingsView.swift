//
//  SettingsView.swift
//  AI File Organizer
//
//  Settings view with Models and General configuration
//  Designed for easy data integration in the future
//

import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.presentQuickSearchOverlay) private var presentOverlay
    @AppStorage("selectedEmbeddingModel") private var selectedEmbeddingModel = "text-embedding-3-small"
    @AppStorage("launchAtStartup") private var launchAtStartup = false
    @AppStorage("overlayHotkey") private var overlayHotkey = ""

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HotkeySection(hotkey: $overlayHotkey)
                
                Button {
                    presentOverlay()
                } label: {
                    Label("Show Quick Search Overlay", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Divider()
                    .padding(.horizontal, -32)

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
    @State private var loginItemError: String?
    @State private var currentVisibilityMode: AppVisibilityMode = .dockOnly

    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.system(size: 20, weight: .semibold))

            // Launch at Startup
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { launchAtStartup },
                    set: { newValue in
                        setLaunchAtStartup(enabled: newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch at Startup")
                            .font(.system(size: 14, weight: .medium))

                        Text("Automatically open the app when your computer starts")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if let error = loginItemError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .onAppear {
                // Sync the toggle with actual login item status
                syncLaunchAtStartupStatus()
            }

            // File Filter Section
            FileFilterSection()

            // App Visibility Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Show Application In")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { currentVisibilityMode },
                    set: { newValue in
                        setVisibilityMode(newValue)
                    }
                )) {
                    ForEach(AppVisibilityMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 250, alignment: .leading)

                Text("Choose where the app appears. Menu Bar Only keeps the app running in background.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

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
                            .frame(width: 16, height: 16)
                            .controlSize(.small)
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

    private func setLaunchAtStartup(enabled: Bool) {
        loginItemError = nil

        do {
            let service = SMAppService.mainApp
            if enabled {
                try service.register()
                launchAtStartup = true
                print("✅ Registered as login item")
            } else {
                try service.unregister()
                launchAtStartup = false
                print("✅ Unregistered as login item")
            }
        } catch {
            loginItemError = "Failed to \(enabled ? "enable" : "disable"): \(error.localizedDescription)"
            print("❌ Login item error: \(error)")
        }
    }

    private func syncLaunchAtStartupStatus() {
        let status = SMAppService.mainApp.status
        let isEnabled = (status == .enabled)
        if launchAtStartup != isEnabled {
            launchAtStartup = isEnabled
        }

        // Also sync visibility mode
        syncVisibilityMode()
    }

    private func syncVisibilityMode() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            currentVisibilityMode = appDelegate.currentVisibilityMode
            print("🔄 SettingsView: Synced visibility mode to: \(currentVisibilityMode.rawValue)")
        } else {
            print("❌ SettingsView: Cannot sync - AppDelegate not found")
        }
    }

    private func setVisibilityMode(_ mode: AppVisibilityMode) {
        print("🎛️ SettingsView: setVisibilityMode called with: \(mode.rawValue)")
        currentVisibilityMode = mode
        if let appDelegate = NSApp.delegate as? AppDelegate {
            print("✅ SettingsView: AppDelegate found, setting mode")
            appDelegate.currentVisibilityMode = mode
        } else {
            print("❌ SettingsView: AppDelegate not found or wrong type!")
            print("   NSApp.delegate type: \(type(of: NSApp.delegate as Any))")
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

// MARK: - File Filter Section

struct FileFilterSection: View {
    @Environment(AppModel.self) private var model
    @State private var newPattern = ""
    @State private var showingHelp = false

    private var modeDescription: String {
        switch model.filterMode {
        case "blacklist":
            return "All files are indexed except those matching exclude patterns"
        case "whitelist":
            return "Only files matching include patterns are indexed"
        default:
            return "Configure file filtering patterns"
        }
    }

    private var excludeLabel: String {
        model.filterMode == "blacklist"
            ? "Exclude Patterns"
            : "Exclude Exceptions"
    }

    private var includeLabel: String {
        model.filterMode == "blacklist"
            ? "Include Exceptions"
            : "Include Patterns"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("File Filters")
                            .font(.system(size: 14, weight: .medium))

                        if model.hasUnsavedFilterChanges {
                            Text("• Unsaved Changes")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(modeDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isLoadingFilterConfig {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Error message if any
            if let error = model.filterConfigError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            }

            // Filter Mode Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Filter Mode")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { model.filterMode },
                    set: { model.updateFilterMode($0) }
                )) {
                    Text("Blacklist (exclude matching files)").tag("blacklist")
                    Text("Whitelist (only include matching files)").tag("whitelist")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 350, alignment: .leading)
            }

            // Pattern list
            VStack(alignment: .leading, spacing: 8) {
                Text(excludeLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                if model.excludePatterns.isEmpty {
                    Text(model.filterMode == "blacklist" ? "No exclude patterns configured" : "No exclude exceptions configured")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(model.excludePatterns, id: \.self) { pattern in
                        FilterPatternRowSimple(pattern: pattern, isNegation: false, mode: model.filterMode) {
                            model.removeFilterPattern(FileFilterPattern(pattern: pattern))
                        }
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            // Include patterns (negation)
            if !model.includePatterns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(includeLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach(model.includePatterns, id: \.self) { pattern in
                        FilterPatternRowSimple(pattern: pattern, isNegation: true, mode: model.filterMode) {
                            model.removeFilterPattern(FileFilterPattern(pattern: "!\(pattern)"))
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            // Add new pattern
            HStack(spacing: 8) {
                TextField("Add pattern (e.g., *.log, /node_modules/, !.gitignore)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit {
                        addPattern()
                    }

                Button(action: addPattern) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newPattern.isEmpty || model.isLoadingFilterConfig)

                Button(action: { showingHelp = true }) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            // Save/Discard buttons (shown when there are unsaved changes)
            if model.hasUnsavedFilterChanges {
                HStack(spacing: 12) {
                    Button("Discard Changes") {
                        model.discardFilterChanges()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(model.isLoadingFilterConfig)

                    Button("Save Changes") {
                        Task {
                            await model.saveFilterConfig()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(model.isLoadingFilterConfig)
                }
                .padding(.top, 8)
            }

            // Action buttons
            HStack {
                Button("Reset to Defaults") {
                    model.resetFilterPatternsToDefaults()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .disabled(model.isLoadingFilterConfig)

                Spacer()

                Button {
                    Task {
                        await model.refreshFilterConfig()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .disabled(model.isLoadingFilterConfig || model.hasUnsavedFilterChanges)
            }
        }
        .sheet(isPresented: $showingHelp) {
            FilterPatternHelpView()
        }
    }

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.addFilterPattern(trimmed)
        newPattern = ""
    }
}

private struct FilterPatternRowSimple: View {
    let pattern: String
    let isNegation: Bool
    let mode: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(pattern)
                    .font(.system(size: 13, design: .monospaced))

                Text(patternDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        if mode == "blacklist" {
            return isNegation ? "checkmark.circle.fill" : "xmark.circle.fill"
        } else {
            return isNegation ? "xmark.circle.fill" : "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        if mode == "blacklist" {
            return isNegation ? .green : .red
        } else {
            return isNegation ? .red : .green
        }
    }

    private var patternDescription: String {
        let action: String
        if mode == "blacklist" {
            action = isNegation ? "Show" : "Hide"
        } else {
            action = isNegation ? "Hide" : "Show"
        }

        if pattern == ".*" {
            return "\(action) hidden files (starting with .)"
        } else if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return "\(action) .\(ext) files"
        } else if pattern.hasPrefix("*") && pattern.hasSuffix("*") {
            let keyword = String(pattern.dropFirst().dropLast())
            return "\(action) files containing '\(keyword)'"
        } else if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            return "\(action) files ending with '\(suffix)'"
        } else if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return "\(action) files starting with '\(prefix)'"
        } else if pattern.contains("/") {
            let path = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "\(action) files in '\(path)' directories"
        } else {
            return "\(action) '\(pattern)'"
        }
    }
}

private struct FilterPatternHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Filter Pattern Syntax")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Introduction
                    Text("Use gitignore-like patterns to filter files from search results. Patterns are case-insensitive.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    // Pattern types
                    VStack(alignment: .leading, spacing: 16) {
                        PatternHelpRow(
                            pattern: ".*",
                            description: "Hidden files (starting with dot)",
                            examples: ".gitignore, .env, .DS_Store"
                        )

                        PatternHelpRow(
                            pattern: "*.ext",
                            description: "Files with specific extension",
                            examples: "*.log matches debug.log, error.log"
                        )

                        PatternHelpRow(
                            pattern: "prefix*",
                            description: "Files starting with prefix",
                            examples: "temp* matches temp.txt, temporary.doc"
                        )

                        PatternHelpRow(
                            pattern: "*suffix",
                            description: "Files ending with suffix",
                            examples: "*_backup matches file_backup"
                        )

                        PatternHelpRow(
                            pattern: "*keyword*",
                            description: "Files containing keyword",
                            examples: "*cache* matches mycache.db"
                        )

                        PatternHelpRow(
                            pattern: "exact.txt",
                            description: "Exact filename match",
                            examples: "Thumbs.db matches only Thumbs.db"
                        )

                        PatternHelpRow(
                            pattern: "/path/",
                            description: "Match directory in path",
                            examples: "/node_modules/ hides files in node_modules"
                        )

                        PatternHelpRow(
                            pattern: "!pattern",
                            description: "Negation (show file despite other filters)",
                            examples: "!.gitignore shows .gitignore even with .* filter"
                        )
                    }

                    Divider()

                    // Common patterns
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Common Patterns")
                            .font(.system(size: 14, weight: .semibold))

                        VStack(alignment: .leading, spacing: 4) {
                            PatternExample(pattern: ".*", note: "All hidden files")
                            PatternExample(pattern: "*.log", note: "Log files")
                            PatternExample(pattern: "*.tmp", note: "Temporary files")
                            PatternExample(pattern: "*~", note: "Backup files")
                            PatternExample(pattern: "/node_modules/", note: "Node.js dependencies")
                            PatternExample(pattern: "/__pycache__/", note: "Python cache")
                            PatternExample(pattern: "/.git/", note: "Git internals")
                            PatternExample(pattern: "/build/", note: "Build output")
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}

private struct PatternHelpRow: View {
    let pattern: String
    let description: String
    let examples: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pattern)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.blue)

                Text("—")
                    .foregroundStyle(.secondary)

                Text(description)
                    .font(.system(size: 13))
            }

            Text("Examples: \(examples)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PatternExample: View {
    let pattern: String
    let note: String

    var body: some View {
        HStack(spacing: 8) {
            Text(pattern)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)

            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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

// MARK: - Hotkey Recording

private struct HotkeySection: View {
    @Binding var hotkey: String
    @State private var isRecording = false
    @Environment(\.controlHotkeyMonitoring) private var controlHotkeys

    private var displayText: String {
        if isRecording { return "Press any key…" }
        return hotkeyDisplayString(hotkey) ?? "Not set"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Overlay Shortcut")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(displayText)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 200, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.12))
                    )

                Button(isRecording ? "Cancel" : "Record") {
                    isRecording.toggle()
                    controlHotkeys(!isRecording)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear") {
                    hotkey = ""
                    controlHotkeys(true)
                    isRecording = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(hotkey.isEmpty)
            }
            .background(
                HotkeyCaptureView(isRecording: $isRecording) { key in
                    hotkey = key.lowercased()
                    isRecording = false
                    controlHotkeys(true)
                }
                .allowsHitTesting(false)
            )

            Text("Click record, then press the key you'd like to use. Leave blank to disable the shortcut.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    openAccessibilityPreferences()
                } label: {
                    Label("Allow Accessibility (needed for global hotkey)", systemImage: "lock.open")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openFullDiskAccessPreferences()
                } label: {
                    Label("Allow Full Disk / Files access (for drag-and-drop)", systemImage: "externaldrive.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

private struct HotkeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (String) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onCapture = onCapture
    }

    final class CaptureView: NSView {
        var onCapture: ((String) -> Void)?
        var isRecording = false {
            didSet {
                if isRecording {
                    window?.makeFirstResponder(self)
                }
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            guard let chars = event.charactersIgnoringModifiers,
                  let first = chars.first else {
                return
            }
            let normalizedKey: String
            if first == " " {
                normalizedKey = "space"
            } else if first.isLetter || first.isNumber {
                normalizedKey = String(first).lowercased()
            } else {
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let components = normalizedModifiers(flags) + [normalizedKey]
            onCapture?(components.joined(separator: "+"))
        }
    }
}

private func openAccessibilityPreferences() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}

private func openFullDiskAccessPreferences() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Hotkey Helpers

private func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> [String] {
    var parts: [String] = []
    if flags.contains(.command) { parts.append("command") }
    if flags.contains(.option) { parts.append("option") }
    if flags.contains(.control) { parts.append("control") }
    if flags.contains(.shift) { parts.append("shift") }
    return parts
}

private func hotkeyDisplayString(_ raw: String) -> String? {
    guard !raw.isEmpty else { return nil }
    let parts = raw.split(separator: "+").map { String($0) }
    guard let key = parts.last else { return nil }
    let modifiers = parts.dropLast().map { modifierSymbol($0) }
    let keySymbol = key == "space" ? "Space" : key.uppercased()
    let symbols = modifiers + [keySymbol]
    return symbols.joined(separator: " ")
}

private func modifierSymbol(_ raw: String) -> String {
    switch raw {
    case "command":
        return "⌘"
    case "option":
        return "⌥"
    case "control":
        return "⌃"
    case "shift":
        return "⇧"
    default:
        return raw.uppercased()
    }
}

#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
}
