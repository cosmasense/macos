//
//  SettingsView.swift
//  fileSearchForntend
//
//  Settings window with Finder-style toolbar tabs.
//  Opened via Cmd+, (macOS standard Settings scene)
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case permissions = "Permissions"
    case general = "General"
    case fileFilters = "File Filters"
    case feedback = "Feedback"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .permissions: return "lock.shield"
        case .general: return "gearshape"
        case .fileFilters: return "line.3.horizontal.decrease.circle"
        case .feedback: return "bubble.left.and.bubble.right"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CosmaManager.self) private var cosmaManager
    @AppStorage("launchAtStartup") private var launchAtStartup = false
    @AppStorage("overlayHotkey") private var overlayHotkey = ""

    var body: some View {
        @Bindable var model = model

        TabView {
            settingsPage {
                HotkeySection(hotkey: $overlayHotkey)
            }
            .tabItem { Label(SettingsSection.permissions.rawValue, systemImage: SettingsSection.permissions.icon) }

            settingsPage {
                GeneralSection(
                    launchAtStartup: $launchAtStartup,
                    backendURL: $model.backendURL
                )
            }
            .tabItem { Label(SettingsSection.general.rawValue, systemImage: SettingsSection.general.icon) }

            settingsPage {
                FileFilterSection()
            }
            .tabItem { Label(SettingsSection.fileFilters.rawValue, systemImage: SettingsSection.fileFilters.icon) }

            settingsPage {
                FeedbackSection()
            }
            .tabItem { Label(SettingsSection.feedback.rawValue, systemImage: SettingsSection.feedback.icon) }

            settingsPage {
                AdvancedSettingsView()
            }
            .tabItem { Label(SettingsSection.advanced.rawValue, systemImage: SettingsSection.advanced.icon) }
        }
        .frame(width: 520)
        .frame(minHeight: 420)
    }

    @ViewBuilder
    private func settingsPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if case .available(let installed, let latest) = cosmaManager.updateStatus {
                    UpdateBanner(installed: installed, latest: latest, cosmaManager: cosmaManager)
                }
                content()
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.brandBlue))
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .environment(CosmaManager())
}
