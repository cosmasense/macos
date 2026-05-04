//
//  ShutdownView.swift
//  fileSearchForntend
//
//  Views shown during quit confirmation and backend teardown.
//

import SwiftUI

// MARK: - Shutdown Progress

struct ShutdownView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)

            Text("Shutting down...")
                .font(.system(size: 14, weight: .medium))

            Text("Stopping backend and releasing GPU resources")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 300, height: 120)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

// MARK: - Restart-for-Update Prompt

/// Modal-feeling popup shown the first time we detect that a new
/// backend version has been downloaded and is waiting for a restart.
/// Replaces the previous "tiny banner inside Settings" surface so the
/// user actually sees the prompt instead of having to open Settings
/// to discover it.
struct RestartForUpdatePromptView: View {
    let runningVersion: String
    let downloadedVersion: String
    let onRestart: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.brandBlue)

                Text("Update Ready to Install")
                    .font(.system(size: 16, weight: .semibold))

                Text("A newer version of the search engine has been downloaded. Restart Cosma Sense to apply it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("v\(runningVersion) → v\(downloadedVersion)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.top, 24)
            .padding(.horizontal, 28)

            Spacer()

            HStack(spacing: 12) {
                Button("Later") {
                    onLater()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Restart Now") {
                    onRestart()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
                .controlSize(.regular)
            }
            .padding(.bottom, 20)
            .padding(.horizontal, 28)
        }
        .frame(width: 380, height: 220)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

// MARK: - Quit Confirmation

struct QuitConfirmationView: View {
    let onQuit: (_ suppressFutureDialogs: Bool) -> Void
    let onCancel: () -> Void

    @State private var dontAskAgain = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "power")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text("Quit Cosma Sense?")
                    .font(.system(size: 16, weight: .semibold))

                Text("The backend server will be stopped and AI models will be unloaded.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                Toggle("Don't ask again", isOn: $dontAskAgain)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button("Quit") {
                        onQuit(dontAskAgain)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandBlue)
                    .controlSize(.regular)
                }
            }
            .padding(.bottom, 20)
            .padding(.horizontal, 28)
        }
        .frame(width: 370, height: 190)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
