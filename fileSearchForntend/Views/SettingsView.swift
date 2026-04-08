//
//  SettingsView.swift
//  fileSearchForntend
//
//  Settings window with two layers:
//  Layer 1 (Main): Non-technical settings (permissions, hotkey, general, filters)
//  Layer 2 (Advanced): Technical/AI settings (models, queue, scheduler, metrics)
//
//  Opened via Cmd+, (macOS standard Settings scene)
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CosmaManager.self) private var cosmaManager
    @AppStorage("launchAtStartup") private var launchAtStartup = false
    @AppStorage("overlayHotkey") private var overlayHotkey = ""
    @AppStorage("backgroundStyle") private var backgroundStyle: String = BackgroundStyle.glass.rawValue
    @State private var showAdvanced = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Update banner
                if case .available(let installed, let latest) = cosmaManager.updateStatus {
                    UpdateBanner(installed: installed, latest: latest, cosmaManager: cosmaManager)
                }

                // --- Layer 1: Basic Settings ---

                // Permissions
                SettingsSectionHeader(title: "Permissions", icon: "lock.shield")
                HotkeySection(hotkey: $overlayHotkey)

                Divider()

                // Appearance
                SettingsSectionHeader(title: "Appearance", icon: "paintbrush")
                Picker("Background", selection: $backgroundStyle) {
                    ForEach(BackgroundStyle.allCases, id: \.rawValue) { style in
                        Text(style.rawValue).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Divider()

                // General
                SettingsSectionHeader(title: "General", icon: "gearshape")
                GeneralSection(
                    launchAtStartup: $launchAtStartup,
                    backendURL: $model.backendURL
                )

                Divider()

                // File Filters
                SettingsSectionHeader(title: "File Filters", icon: "line.3.horizontal.decrease.circle")
                FileFilterSection()

                Divider()

                // Feedback
                FeedbackSection()

                Divider()

                // Advanced Settings button
                Button {
                    showAdvanced = true
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                        Text("Advanced Settings...")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showAdvanced) {
            AdvancedSettingsView()
                .environment(model)
                .environment(cosmaManager)
                .frame(minWidth: 550, minHeight: 500)
        }
    }
}

// MARK: - Section Header

struct SettingsSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 16, weight: .bold))
        }
    }
}

// MARK: - Update Banner

private struct UpdateBanner: View {
    let installed: String
    let latest: String
    let cosmaManager: CosmaManager

    var body: some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cosma Update Available")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("v\(installed) \u{2192} v\(latest)")
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
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .environment(CosmaManager())
        .frame(width: 600, height: 700)
}
