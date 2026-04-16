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

    /// Simulated progress bar that *feels* real even though the backend
    /// can't stream true percentages during cold start.
    ///
    /// How it works:
    ///   - Each SetupStage maps to a target range [min, max] of the bar.
    ///   - A timer creeps the bar upward within the current stage's range
    ///     toward `max - 0.02`, so it keeps moving during long steps.
    ///   - When the real SetupStage advances, the bar snaps forward (with
    ///     animation) to the new stage's floor, giving the user a visible
    ///     "something just happened" cue even when the underlying work
    ///     is silent (e.g. pip install).
    ///
    /// The percentage is therefore honest about *which stage we're in*
    /// while being fake about *how far through that stage*. That's the
    /// best we can do without per-stage progress streaming from the
    /// backend/installer.
    @State private var simulatedProgress: Double = 0.0
    @State private var progressTimer: Timer?

    /// How long the fake fill-within-a-stage takes (seconds) before it caps.
    /// Kept short so a stage that finishes quickly doesn't hold the bar back.
    private let withinStageFillDuration: Double = 6.0

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

            // Simulated progress bar — gives the user visual feedback during silent setup
            VStack(spacing: 6) {
                ProgressView(value: simulatedProgress)
                    .progressViewStyle(.linear)
                    .tint(Color.brandBlue)
                    .frame(maxWidth: 320)
                Text(simulatedProgressLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.identity)   // Stop SwiftUI from crossfading the text
                    .animation(nil, value: simulatedProgress)  // Detach text from progress animation
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
        .onAppear { startSimulatedProgress() }
        .onDisappear { stopSimulatedProgress() }
        .onChange(of: cosmaManager.setupStage) { _, stage in
            // Snap the bar to the new stage's floor so the jump is visible.
            handleStageChange(stage)
            if case .running = stage {
                completeSimulatedProgress()
                onConnected()
            }
        }
        .task {
            // Fallback: poll the state variable (not the backend) in case
            // onChange misses the .idle → .running transition on fast paths.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if case .running = cosmaManager.setupStage {
                    onConnected()
                    return
                }
            }
        }
    }

    // MARK: - Simulated Progress

    /// The bar's target range for each real stage. Values were picked to
    /// roughly reflect wall-clock cost on a cold first install:
    /// pip-installing `cosma` + its deps is the slow middle hump,
    /// pulling the Ollama model is the long tail, server start is fast.
    /// These don't need to be precise — they just need to feel monotonic.
    private func stageRange(_ stage: CosmaManager.SetupStage) -> (min: Double, max: Double) {
        switch stage {
        case .idle:              return (0.00, 0.05)
        case .checkingUV:        return (0.05, 0.10)
        case .installingUV:      return (0.10, 0.20)
        case .checkingCosma:     return (0.20, 0.25)
        case .installingCosma:   return (0.25, 0.50)  // slow: pip compile
        case .checkingOllama:    return (0.50, 0.55)
        case .installingOllama:  return (0.55, 0.65)
        case .pullingOllamaModel:return (0.65, 0.88)  // slow: GB download
        case .startingServer:    return (0.88, 0.97)
        case .running:           return (1.00, 1.00)
        case .stopped, .failed:  return (simulatedProgress, simulatedProgress)
        }
    }

    /// Text under the bar — always reflects the real current stage so the
    /// user can see *what* is actually happening, even though the numeric
    /// progress within that stage is interpolated.
    private var simulatedProgressLabel: String {
        if simulatedProgress >= 1.0 {
            return "Almost ready…"
        }
        let pct = Int(simulatedProgress * 100)
        return "\(cosmaManager.stageDescription) \(pct)%"
    }

    /// Nudge the bar upward within the current stage's range. Capped just
    /// below the stage ceiling so the next real stage transition still has
    /// room to produce a visible jump.
    private func startSimulatedProgress() {
        stopSimulatedProgress()
        simulatedProgress = 0.0
        let stepInterval: TimeInterval = 0.25
        progressTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                let range = stageRange(cosmaManager.setupStage)
                let ceiling = max(range.min, range.max - 0.02)
                if simulatedProgress >= ceiling { return }
                // Fill the span in `withinStageFillDuration` seconds regardless
                // of how long the real stage lasts — longer real stages just
                // mean the bar sits at ~ceiling until the next transition.
                let span = range.max - range.min
                let increment = (span / withinStageFillDuration) * stepInterval
                withAnimation(.linear(duration: stepInterval)) {
                    simulatedProgress = min(ceiling, simulatedProgress + increment)
                }
            }
        }
    }

    /// Called from onChange(of: setupStage) — jumps the bar forward (with
    /// a short ease) to the new stage's floor so the user sees a clear
    /// "step done" cue.
    private func handleStageChange(_ stage: CosmaManager.SetupStage) {
        let range = stageRange(stage)
        if simulatedProgress < range.min {
            withAnimation(.easeOut(duration: 0.35)) {
                simulatedProgress = range.min
            }
        }
    }

    private func stopSimulatedProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func completeSimulatedProgress() {
        stopSimulatedProgress()
        withAnimation(.easeOut(duration: 0.4)) {
            simulatedProgress = 1.0
        }
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
        case .checkingOllama: return 5
        case .installingOllama: return 6
        case .pullingOllamaModel: return 7
        case .startingServer: return 8
        case .running: return 9
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
