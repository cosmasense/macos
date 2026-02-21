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
    @Binding var launchAtStartup: Bool
    @Binding var backendURL: String
    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var loginItemError: String?
    @State private var currentVisibilityMode: AppVisibilityMode = .dockOnly
    @State private var showingLogs = false

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

                            Button("Check for Updates") {
                                Task { await cosmaManager.checkForUpdates() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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

            // Backend URL
            VStack(alignment: .leading, spacing: 8) {
                Text("Backend URL")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(cosmaManager.isManaged ? .tertiary : .secondary)

                HStack(spacing: 12) {
                    TextField("http://localhost:8000", text: $backendURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(cosmaManager.isManaged)
                        .opacity(cosmaManager.isManaged ? 0.5 : 1.0)

                    Button("Test Connection") {
                        testBackendConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(cosmaManager.isManaged)

                    if connectionTestState == .testing {
                        ProgressView()
                            .frame(width: 16, height: 16)
                            .controlSize(.small)
                    }
                }

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
                ScrollView {
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
