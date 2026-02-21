//
//  BackendConnectionView.swift
//  fileSearchForntend
//
//  Startup view that checks backend connection before proceeding to main UI.
//

import SwiftUI
import AppKit

struct BackendConnectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(CosmaManager.self) private var cosmaManager
    let onConnected: () -> Void

    @State private var isChecking = false
    @State private var lastError: String?
    @State private var copied = false

    private let startCommand = "cosma serve"

    var body: some View {
        if cosmaManager.isManaged {
            managedModeContent
        } else {
            manualModeContent
        }
    }

    // MARK: - Managed Mode

    private var managedModeContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Setting Up Backend")
                .font(.system(size: 24, weight: .semibold))

            Text("Automatically installing and starting the COSMA backend…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            // Step-by-step progress
            VStack(alignment: .leading, spacing: 12) {
                SetupStepRow(
                    label: "uv package manager",
                    state: stepState(
                        checking: .checkingUV,
                        installing: .installingUV,
                        stage: cosmaManager.setupStage
                    )
                )
                SetupStepRow(
                    label: "cosma backend",
                    state: stepState(
                        checking: .checkingCosma,
                        installing: .installingCosma,
                        stage: cosmaManager.setupStage
                    )
                )
                SetupStepRow(
                    label: "Starting server",
                    state: serverStepState(cosmaManager.setupStage)
                )
            }
            .padding(.horizontal, 40)

            if case .failed(let message) = cosmaManager.setupStage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)

                Button {
                    Task {
                        await cosmaManager.startManagedBackend()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Manual Mode (existing UI)

    private var manualModeContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Backend Not Connected")
                .font(.system(size: 24, weight: .semibold))

            VStack(spacing: 8) {
                Text("The COSMA backend server is not running.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text("Start the backend with the following command:")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // Command box
            HStack(spacing: 12) {
                Text(startCommand)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)

                Button {
                    copyCommand()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy command")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )

            Text("Note: The backend may take up to 20 seconds to start.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            if let error = lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
            }

            Button {
                checkConnection()
            } label: {
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isChecking ? "Checking..." : "Retry Connection")
                }
                .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChecking)

            Spacer()

            HStack(spacing: 4) {
                Text("Backend URL:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(APIClient.shared.currentBaseURL().absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            checkConnection()
        }
    }

    // MARK: - Step State Helpers

    private func stepState(
        checking: CosmaManager.SetupStage,
        installing: CosmaManager.SetupStage,
        stage: CosmaManager.SetupStage
    ) -> SetupStepState {
        let order = stageOrder(stage)
        let checkOrder = stageOrder(checking)
        let installOrder = stageOrder(installing)

        if order > installOrder {
            return .complete
        } else if stage == checking || stage == installing {
            return .inProgress
        } else if case .failed = stage, order >= checkOrder {
            return .failed
        } else {
            return .pending
        }
    }

    private func serverStepState(_ stage: CosmaManager.SetupStage) -> SetupStepState {
        switch stage {
        case .startingServer: return .inProgress
        case .running: return .complete
        case .failed: return .failed
        case .idle, .stopped: return .pending
        default:
            return stageOrder(stage) < stageOrder(.startingServer) ? .pending : .complete
        }
    }

    private func stageOrder(_ stage: CosmaManager.SetupStage) -> Int {
        switch stage {
        case .idle: return 0
        case .checkingUV: return 1
        case .installingUV: return 2
        case .checkingCosma: return 3
        case .installingCosma: return 4
        case .startingServer: return 5
        case .running: return 6
        case .stopped: return -1
        case .failed: return -1
        }
    }

    // MARK: - Actions

    private func copyCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(startCommand, forType: .string)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func checkConnection() {
        isChecking = true
        lastError = nil

        Task {
            do {
                let _ = try await APIClient.shared.fetchStatus()
                await MainActor.run {
                    isChecking = false
                    onConnected()
                }
            } catch {
                await MainActor.run {
                    isChecking = false
                    lastError = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Setup Step Views

enum SetupStepState {
    case pending
    case inProgress
    case complete
    case failed
}

struct SetupStepRow: View {
    let label: String
    let state: SetupStepState

    var body: some View {
        HStack(spacing: 12) {
            switch state {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 16))
            case .inProgress:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 16))
            }

            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(state == .pending ? .tertiary : .primary)
        }
    }
}

#Preview {
    BackendConnectionView(onConnected: {})
        .environment(CosmaManager())
        .frame(width: 500, height: 400)
}
