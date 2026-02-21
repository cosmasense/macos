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
    @Environment(CosmaManager.self) private var cosmaManager
    @Environment(\.presentQuickSearchOverlay) private var presentOverlay
    @AppStorage("launchAtStartup") private var launchAtStartup = false
    @AppStorage("overlayHotkey") private var overlayHotkey = ""

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Update banner
                if case .available(let installed, let latest) = cosmaManager.updateStatus {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cosma Update Available")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("v\(installed) → v\(latest)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Button("Update Now") {
                            Task { await cosmaManager.performUpdate() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .controlSize(.small)

                        Button("Dismiss") {
                            cosmaManager.dismissUpdate()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.8))
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.blue))
                }

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
        .environment(CosmaManager())
        .frame(width: 800, height: 600)
}
