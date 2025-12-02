//
//  SettingsView.swift
//  AI File Organizer
//
//  Settings view with Models and General configuration
//  Designed for easy data integration in the future
//

import SwiftUI
import AppKit

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

            Toggle(isOn: $model.hideHiddenFiles) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hide files starting with “.”")
                        .font(.system(size: 14, weight: .medium))

                    Text("When enabled, search results skip dotfiles. Turn off to include them.")
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
