//
//  AdvancedSettingsView.swift
//  fileSearchForntend
//
//  Sheet opened from General → "Advanced…". Houses every knob a
//  typical user shouldn't need: update channel, backend URL, log
//  viewer, manual update check, restart/stop, dialog reset,
//  open-source licenses, processing model config, and the
//  queue/scheduler editor.
//

import SwiftUI

struct GeneralAdvancedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(CosmaManager.self) private var cosmaManager
    @Environment(SparkleUpdaterController.self) private var updater
    @Environment(\.dismiss) private var dismiss
    @Binding var backendURL: String

    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var showingLogs = false
    @State private var dialogsReset = false
    @State private var showingLicenses = false

    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    private var isCheckInFlight: Bool {
        switch cosmaManager.updateStatus {
        case .checking, .downloading:
            return true
        case .idle, .upToDate, .downloadedPendingRestart, .failed:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sheet title bar
            HStack {
                Text("Advanced")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 28) {
                    appUpdatesAdvancedBlock
                    Divider()
                    backendBlock
                    Divider()
                    miscBlock
                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Processing Models", icon: "cpu")
                        BackendSettingsSection()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        SettingsSectionHeader(title: "Queue & Scheduler", icon: "clock.arrow.2.circlepath")
                        IndexingSettingsSection()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 720, height: 640)
        .sheet(isPresented: $showingLogs) {
            BackendLogView(cosmaManager: cosmaManager)
        }
        .sheet(isPresented: $showingLicenses) {
            LicensesView()
        }
    }

    // MARK: - Sub-blocks

    private var appUpdatesAdvancedBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "App Updates", icon: "arrow.down.app")

            VStack(alignment: .leading, spacing: 6) {
                Text("Release Channel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { updater.channel },
                    set: { updater.channel = $0 }
                )) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 280, alignment: .leading)

                Text(updater.channel.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    updater.checkForUpdates(userInitiated: true)
                } label: {
                    if updater.isCheckInFlight {
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
                .disabled(updater.isCheckInFlight)
            }

            AppUpdateStatusRow(
                state: updater.checkState,
                currentVersion: updater.currentVersion,
                lastCheckedAt: updater.lastCheckedAt
            )
        }
    }

    private var backendBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Backend", icon: "server.rack")

            if cosmaManager.isManaged && cosmaManager.isRunning {
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
                    .disabled(isCheckInFlight)

                    Button {
                        showingLogs = true
                    } label: {
                        Label("View Logs", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                UpdateCheckStatusRow(
                    status: cosmaManager.updateStatus,
                    installedVersion: cosmaManager.installedVersion,
                    latestVersion: cosmaManager.latestVersion,
                    lastCheckedAt: cosmaManager.lastUpdateCheckAt
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Backend URL")
                    .font(.system(size: 13, weight: .medium))
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
    }

    private var miscBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "Other", icon: "ellipsis.circle")

            VStack(alignment: .leading, spacing: 8) {
                Text("Dialogs")
                    .font(.system(size: 13, weight: .medium))
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Open Source Licenses")
                    .font(.system(size: 13, weight: .medium))
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
