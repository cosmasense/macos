//
//  GeneralSection.swift
//  fileSearchForntend
//
//  General settings: hotkey (top), launch at startup, app visibility,
//  app updates, managed backend. Power-user knobs (backend URL, log
//  viewer, update channel, dialogs, licenses, processing models,
//  queue/scheduler) live in the Advanced sheet, opened from the
//  button at the bottom.
//

import SwiftUI
import ServiceManagement

// MARK: - General Section

struct GeneralSection: View {
    @Environment(AppModel.self) private var model
    @Environment(CosmaManager.self) private var cosmaManager
    @Environment(SparkleUpdaterController.self) private var updater
    @Binding var launchAtStartup: Bool
    @Binding var backendURL: String
    @Binding var hotkey: String
    @State private var loginItemError: String?
    @State private var currentVisibilityMode: AppVisibilityMode = .dockOnly
    @State private var showingAdvanced = false

    /// True while a PyPI check (or a triggered download) is running.
    /// Used to swap the button label for a spinner + disable re-clicks.
    private var isCheckInFlight: Bool {
        switch cosmaManager.updateStatus {
        case .checking, .downloading:
            return true
        case .idle, .upToDate, .downloadedPendingRestart, .failed:
            return false
        }
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var updater = updater
        VStack(alignment: .leading, spacing: 24) {
            // Shortcut — top of the page so it's the first thing a
            // returning user sees. Was its own tab before; folded in
            // here because most users only set it once.
            VStack(alignment: .leading, spacing: 10) {
                Text("Shortcut")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                HotkeySection(hotkey: $hotkey)
            }

            Divider()

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
                .frame(maxWidth: 280, alignment: .leading)

                Text("Choose where the app appears. Menu Bar Only keeps the app running in background.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Prevent sleep during indexing. Overnight indexing runs on
            // big folders were getting cut off because the Mac fell
            // asleep after the system's user-idle timer. This toggle
            // holds an IOPMAssertion (PreventUserIdleSystemSleep) while
            // the queue is busy — lid-close / battery-critical still
            // sleep normally.
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $model.preventSleepDuringIndexing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prevent Sleep While Indexing")
                            .font(.system(size: 14, weight: .medium))

                        Text("Keeps your Mac awake while files are being indexed so long overnight runs finish. Doesn't override lid-close or low-battery sleep.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }

            // Hide the applications section that normally appears above
            // file results when a query matches both. Off by default —
            // app search is a discoverability feature most users want;
            // power users who only ever search docs can suppress it.
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $model.disableAppsSearch) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide Applications in Search")
                            .font(.system(size: 14, weight: .medium))

                        Text("Only show documents in search results. When off, matching apps appear above docs with a thin divider between them.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }

            // App Updates — auto-check toggle + status row only.
            // Channel picker and the manual "Check for Updates" button
            // moved into the Advanced sheet.
            VStack(alignment: .leading, spacing: 12) {
                Text("App Updates")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Toggle(isOn: $updater.automaticallyChecksForUpdates) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatically Check for Updates")
                            .font(.system(size: 14, weight: .medium))
                        Text("We'll check in the background and prompt before installing.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            // Managed Backend — toggle + status only. Logs, restart/
            // stop, and manual update check moved into Advanced.
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { cosmaManager.isManaged },
                    set: { newValue in
                        cosmaManager.isManaged = newValue
                        if newValue {
                            Task { await cosmaManager.startManagedBackend() }
                        } else {
                            cosmaManager.stopServer()
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Managed Backend")
                            .font(.system(size: 14, weight: .medium))

                        Text("Automatically install and run the cosma backend")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if cosmaManager.isManaged {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(cosmaManager.isRunning ? .green : .orange)
                            .frame(width: 8, height: 8)

                        Text(cosmaManager.stageDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if let version = cosmaManager.installedVersion {
                            Text("v\(version)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            // Advanced sheet trigger. Houses every knob a typical user
            // shouldn't have to look at: backend URL, update channel,
            // logs, restart/stop, dialog reset, licenses, processing
            // models, queue/scheduler.
            HStack {
                Spacer()
                Button {
                    showingAdvanced = true
                } label: {
                    Label("Advanced…", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .sheet(isPresented: $showingAdvanced) {
            GeneralAdvancedSheet(backendURL: $backendURL)
        }
    }

    private func setLaunchAtStartup(enabled: Bool) {
        loginItemError = nil

        do {
            let service = SMAppService.mainApp
            if enabled {
                try service.register()
                launchAtStartup = true
            } else {
                try service.unregister()
                launchAtStartup = false
            }
        } catch {
            loginItemError = "Failed to \(enabled ? "enable" : "disable"): \(error.localizedDescription)"
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
        let rawValue = UserDefaults.standard.string(forKey: "appVisibilityMode") ?? AppVisibilityMode.dockOnly.rawValue
        currentVisibilityMode = AppVisibilityMode(rawValue: rawValue) ?? .dockOnly
    }

    private func setVisibilityMode(_ mode: AppVisibilityMode) {
        currentVisibilityMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "appVisibilityMode")
        // Notify AppDelegate through notification since direct cast can fail
        NotificationCenter.default.post(name: .visibilityModeChanged, object: mode.rawValue)
    }
}

// MARK: - Backend Log View

struct BackendLogView: View {
    let cosmaManager: CosmaManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "terminal")
                Text("Backend Logs")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()

                Button {
                    cosmaManager.serverLog = ""
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear logs")

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            // Log content
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    if cosmaManager.serverLog.isEmpty {
                        Text("No log output yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                    } else {
                        Text(cosmaManager.serverLog)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .id("logBottom")
                    }
                }
                .onChange(of: cosmaManager.serverLog) {
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 600, height: 400)
    }
}

// MARK: - Status Text Helper

struct StatusText: View {
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

// MARK: - Update Check Status Row

/// Inline result line shown next to the "Check for Updates" button.
/// Reflects CosmaManager.updateStatus + lastCheckedAt so the user
/// can tell that a click actually did something — and what it found.
struct UpdateCheckStatusRow: View {
    let status: CosmaManager.UpdateStatus
    let installedVersion: String?
    let latestVersion: String?
    let lastCheckedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .foregroundStyle(.primary)
            if let stamp = checkedStamp {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(stamp)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }

    /// True when PyPI's latest is newer than what's installed — even
    /// if `updateStatus` says `.upToDate`. Surfaces the "uv tool
    /// upgrade returned 0 but didn't actually upgrade" edge case.
    private var pypiAheadOfInstalled: Bool {
        guard let installed = installedVersion,
              let latest = latestVersion,
              compareSemver(installed, latest) < 0 else { return false }
        return true
    }

    private var icon: String {
        switch status {
        case .checking, .downloading:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return pypiAheadOfInstalled ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        case .downloadedPendingRestart:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .checking, .downloading:
            return .secondary
        case .upToDate:
            return pypiAheadOfInstalled ? .orange : .green
        case .downloadedPendingRestart:
            return .blue
        case .failed:
            return .red
        case .idle:
            return .secondary
        }
    }

    private var message: String {
        switch status {
        case .checking:
            return "Contacting PyPI…"
        case let .downloading(_, target):
            return "Downloading v\(target)…"
        case .upToDate:
            if let installed = installedVersion,
               let latest = latestVersion,
               compareSemver(installed, latest) < 0 {
                return (
                    "PyPI has v\(latest), but auto-upgrade left you on " +
                    "v\(installed). Try `uv tool upgrade cosma --no-cache` " +
                    "in a terminal — it'll print why uv decided not to " +
                    "move forward."
                )
            }
            if let v = installedVersion {
                return "Up to date — v\(v) is the latest."
            }
            return "Up to date."
        case let .downloadedPendingRestart(running, downloaded):
            return "Update v\(downloaded) downloaded — restart to apply (currently running v\(running))."
        case let .failed(reason):
            return "Check failed: \(reason)"
        case .idle:
            if lastCheckedAt == nil {
                return "Click \"Check for Updates\" to look for a new release."
            }
            return "—"
        }
    }

    private func compareSemver(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".")
                .prefix(3)
                .map { component -> Int in
                    let digits = component.prefix { $0.isNumber }
                    return Int(digits) ?? 0
                }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<3 {
            let av = i < pa.count ? pa[i] : 0
            let bv = i < pb.count ? pb[i] : 0
            if av < bv { return -1 }
            if av > bv { return 1 }
        }
        return 0
    }

    private var checkedStamp: String? {
        guard let when = lastCheckedAt else { return nil }
        switch status {
        case .checking, .downloading:
            return nil
        default:
            break
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "checked \(f.localizedString(for: when, relativeTo: Date()))"
    }
}
