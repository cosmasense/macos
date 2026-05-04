//
//  GeneralSection.swift
//  fileSearchForntend
//
//  General settings: launch at startup, app visibility, backend URL
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
    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var loginItemError: String?
    @State private var currentVisibilityMode: AppVisibilityMode = .dockOnly
    @State private var showingLogs = false
    @State private var dialogsReset = false
    @State private var showingLicenses = false

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

    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 24) {
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

            // App Updates (Sparkle)
            AppUpdatesSection(updater: updater)

            // Managed Backend
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

                    if cosmaManager.isRunning {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                if cosmaManager.ownsProcess {
                                    Button("Restart") {
                                        Task { await cosmaManager.restartServer() }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Stop") {
                                        cosmaManager.stopServer()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                Button {
                                    Task { await cosmaManager.checkForUpdates() }
                                } label: {
                                    if isCheckInFlight {
                                        HStack(spacing: 6) {
                                            ProgressView().controlSize(.mini)
                                            Text("Checking…")
                                        }
                                    } else {
                                        Text("Check for Updates")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                // Block rapid re-clicks while a check
                                // (or its triggered download) is in
                                // flight — without this the user can
                                // queue four PyPI hits in a row.
                                .disabled(isCheckInFlight)
                            }

                            // Inline result for the check, so the user
                            // can tell whether the click did anything.
                            // Was previously silent — `updateStatus`
                            // mutated but nothing on the page reflected
                            // it, so the button felt broken.
                            UpdateCheckStatusRow(
                                status: cosmaManager.updateStatus,
                                installedVersion: cosmaManager.installedVersion,
                                latestVersion: cosmaManager.latestVersion,
                                lastCheckedAt: cosmaManager.lastUpdateCheckAt
                            )
                        }
                    }

                    Button {
                        showingLogs = true
                    } label: {
                        Label("View Logs", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Reset Suppressed Dialogs
            VStack(alignment: .leading, spacing: 8) {
                Text("Dialogs")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        UserDefaults.standard.removeObject(forKey: AppDelegate.suppressQuitConfirmationKey)
                        dialogsReset = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            dialogsReset = false
                        }
                    } label: {
                        Label("Reset All Dialogs", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if dialogsReset {
                        Text("Done")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }

                Text("Re-enable confirmation dialogs that were dismissed with \"Don't ask again\".")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Open-source licenses
            VStack(alignment: .leading, spacing: 8) {
                Text("Open Source Licenses")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Button {
                    showingLicenses = true
                } label: {
                    Label("View Acknowledgements", systemImage: "doc.text.below.ecg")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("Cosma Sense is built on a number of open-source libraries. View their licenses to verify compliance.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Backend URL
            VStack(alignment: .leading, spacing: 8) {
                Text("Backend URL")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(cosmaManager.isManaged ? .tertiary : .secondary)

                HStack(spacing: 8) {
                    TextField("http://localhost:8000", text: $backendURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(cosmaManager.isManaged)
                        .opacity(cosmaManager.isManaged ? 0.5 : 1.0)
                        .layoutPriority(1)

                    Button("Test") {
                        testBackendConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(cosmaManager.isManaged)

                    if connectionTestState == .testing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: 480)

                if cosmaManager.isManaged {
                    Text("URL is managed automatically when Managed Backend is enabled.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
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
        .sheet(isPresented: $showingLogs) {
            BackendLogView(cosmaManager: cosmaManager)
        }
        .sheet(isPresented: $showingLicenses) {
            LicensesView()
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
private struct UpdateCheckStatusRow: View {
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
    /// if `updateStatus` says `.upToDate`. This is the smoking gun for
    /// "uv tool upgrade returned 0 but didn't actually upgrade", which
    /// happens occasionally with version-resolution edge cases. We
    /// surface it so the user sees the real situation instead of a
    /// green "you're on the latest" lie.
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
            // Green only when truly current. PyPI ahead → orange so
            // the user can tell something's off at a glance.
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
            // The runtime says we're up to date, but cross-check
            // against latestVersion before claiming it. Otherwise we
            // print "v1.0.1 is the latest" while PyPI is serving
            // v1.0.2 because uv tool upgrade silently no-op'd.
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
            // Pre-first-click state. Only happens before the user has
            // clicked the button at all — once they have, the status
            // moves to .checking and stays in a populated state from
            // then on.
            if lastCheckedAt == nil {
                return "Click \"Check for Updates\" to look for a new release."
            }
            return "—"
        }
    }

    /// Element-wise semver comparison up to three components.
    /// Returns -1 / 0 / 1 like strcmp; missing components count as 0
    /// and any non-numeric tail is stripped. Mirrors
    /// BackendCompatibility.compareSemver but we keep a private copy
    /// here rather than depending on that file's internals from a
    /// view.
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

    /// "checked just now" / "checked 3m ago". Shown next to terminal
    /// states (upToDate, downloadedPendingRestart, failed) so the user
    /// can tell the click went through and how fresh the result is.
    private var checkedStamp: String? {
        guard let when = lastCheckedAt else { return nil }
        // Don't bother stamping while a check is mid-flight — the
        // spinner already conveys "happening right now".
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
