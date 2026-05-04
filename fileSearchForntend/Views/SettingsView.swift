//
//  SettingsView.swift
//  fileSearchForntend
//
//  Settings window with Finder-style toolbar tabs.
//  Opened via Cmd+, (macOS standard Settings scene)
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case shortcut = "Shortcut"
    case general = "General"
    case permissions = "Permissions"
    case fileFilters = "File Filters"
    case feedback = "Feedback"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .shortcut: return "command.square"
        case .general: return "gearshape"
        case .permissions: return "lock.shield"
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
            settingsPage(title: "Shortcut") {
                HotkeySection(hotkey: $overlayHotkey)
            }
            .tabItem { Label(SettingsSection.shortcut.rawValue, systemImage: SettingsSection.shortcut.icon) }

            settingsPage(title: "General") {
                GeneralSection(
                    launchAtStartup: $launchAtStartup,
                    backendURL: $model.backendURL
                )
            }
            .tabItem { Label(SettingsSection.general.rawValue, systemImage: SettingsSection.general.icon) }

            settingsPage(title: "Permissions") {
                PermissionsSettingsView()
            }
            .tabItem { Label(SettingsSection.permissions.rawValue, systemImage: SettingsSection.permissions.icon) }

            settingsPage(title: "File Filters") {
                FileFilterSection()
            }
            .tabItem { Label(SettingsSection.fileFilters.rawValue, systemImage: SettingsSection.fileFilters.icon) }

            settingsPage(title: "Feedback") {
                FeedbackSection()
            }
            .tabItem { Label(SettingsSection.feedback.rawValue, systemImage: SettingsSection.feedback.icon) }

            settingsPage(title: nil) {
                AdvancedSettingsView()
            }
            .tabItem { Label(SettingsSection.advanced.rawValue, systemImage: SettingsSection.advanced.icon) }
        }
        // Match the main window's footprint (720 x 560 default) so
        // jumping between Settings ↔ main UI doesn't reflow the user's
        // attention to a differently-sized rectangle. The window is
        // also recentered on the active screen each time it opens.
        .frame(minWidth: 720, idealWidth: 720)
        .frame(minHeight: 560, idealHeight: 560)
        .background(SettingsWindowConfigurator())
    }

    @ViewBuilder
    private func settingsPage<Content: View>(title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                switch cosmaManager.updateStatus {
                case .downloadedPendingRestart(let running, let downloaded):
                    UpdateBanner(running: running, downloaded: downloaded, downloading: false, cosmaManager: cosmaManager)
                case .downloading(let running, let target):
                    UpdateBanner(running: running, downloaded: target, downloading: true, cosmaManager: cosmaManager)
                default:
                    EmptyView()
                }
                if let title {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.bottom, 2)
                }
                content()
                Spacer(minLength: 0)
            }
            .padding(24)
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
    let running: String
    let downloaded: String
    let downloading: Bool
    let cosmaManager: CosmaManager

    var body: some View {
        HStack {
            if downloading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(downloading ? "Downloading Cosma Update" : "Cosma Update Ready")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("v\(running) \u{2192} v\(downloaded)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            if !downloading {
                Button("Restart") {
                    cosmaManager.relaunchApp()
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
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.brandBlue))
    }
}

// MARK: - Window Configurator

/// Walks up to the hosting NSWindow and forces it to a 720x560 frame
/// centered on whichever screen currently shows it. SwiftUI's Settings
/// scene otherwise restores the user's last-dragged geometry, which
/// can leave the window awkwardly small or off-center after a display
/// change — and the app deliberately wants the same footprint as the
/// main window so the two surfaces feel like one app.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let target = NSSize(width: 720, height: 560)
            // Anchor to the screen the window currently overlaps, so a
            // multi-monitor user opening Settings on a side display
            // doesn't get yanked back to the primary screen.
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
            guard let visibleFrame = screen?.visibleFrame else { return }
            let origin = NSPoint(
                x: visibleFrame.midX - target.width / 2,
                y: visibleFrame.midY - target.height / 2
            )
            let frame = NSRect(origin: origin, size: target)
            if window.frame != frame {
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .environment(CosmaManager())
}
