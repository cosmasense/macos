//
//  SettingsView.swift
//  fileSearchForntend
//
//  Settings view container with section components
//
//  Section files in Views/Settings/:
//  - HotkeySection.swift          - Search overlay shortcut and permissions
//  - GeneralSection.swift         - Launch at startup, visibility, backend URL
//  - ModelsSection.swift          - Processing config (Embedding, Summarizer, Whisper, Advanced)
//  - FileFilterSection.swift      - File filtering patterns with FlowLayout
//  - IndexingSettingsSection.swift - Queue config, scheduler, metrics
//  - FeedbackSection.swift        - Support and feedback submission
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.presentQuickSearchOverlay) private var presentOverlay
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

                // Backend Settings Section
                BackendSettingsSection()

                Divider()
                    .padding(.horizontal, -32)

                // General Section
                GeneralSection(
                    launchAtStartup: $launchAtStartup,
                    backendURL: $model.backendURL
                )

                Divider()
                    .padding(.horizontal, -32)

                IndexingSettingsSection()

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

#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
}
