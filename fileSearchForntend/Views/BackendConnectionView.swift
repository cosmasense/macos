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
    let onConnected: () -> Void

    @State private var isChecking = false
    @State private var lastError: String?
    @State private var copied = false

    private let startCommand = "cosma serve"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            // Title
            Text("Backend Not Connected")
                .font(.system(size: 24, weight: .semibold))

            // Description
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

            // Note about startup time
            Text("Note: The backend may take up to 20 seconds to start.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            // Error message
            if let error = lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
            }

            // Retry button
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

            // Backend URL info
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

    private func copyCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(startCommand, forType: .string)
        copied = true

        // Reset after 2 seconds
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

#Preview {
    BackendConnectionView(onConnected: {})
        .frame(width: 500, height: 400)
}
