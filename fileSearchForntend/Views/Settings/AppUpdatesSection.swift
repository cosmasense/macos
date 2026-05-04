//
//  AppUpdatesSection.swift
//  fileSearchForntend
//
//  Settings chunk for the Sparkle-driven frontend auto-update.
//  Sits next to the Managed-Backend section in General settings so
//  users can see both update channels (app shell vs. backend tool)
//  in the same place. The two are independent: a Sparkle update
//  swaps the .app on disk; the backend keeps updating itself via
//  `uv tool upgrade cosma` against PyPI.
//

import SwiftUI

struct AppUpdatesSection: View {
    @Bindable var updater: SparkleUpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Updates")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            // Auto-check toggle
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

            // Channel picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Release Channel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: $updater.channel) {
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

            // Check Now button + status row
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

                Spacer(minLength: 0)
            }

            AppUpdateStatusRow(
                state: updater.checkState,
                currentVersion: updater.currentVersion,
                lastCheckedAt: updater.lastCheckedAt
            )
        }
    }
}

/// Inline result line — mirrors the backend `UpdateCheckStatusRow`
/// pattern in GeneralSection.swift so the two update widgets read
/// the same at a glance.
private struct AppUpdateStatusRow: View {
    let state: SparkleUpdaterController.CheckState
    let currentVersion: String
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

    private var icon: String {
        switch state {
        case .checking, .downloading:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return "checkmark.circle.fill"
        case .updateFound, .readyToInstall:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .checking, .downloading:
            return .secondary
        case .upToDate:
            return .green
        case .updateFound, .readyToInstall:
            return .blue
        case .failed:
            return .red
        case .idle:
            return .secondary
        }
    }

    private var message: String {
        switch state {
        case .checking:
            return "Contacting update server…"
        case let .downloading(v):
            return "Downloading v\(v)…"
        case .upToDate:
            return "Up to date — v\(currentVersion) is the latest."
        case let .updateFound(v):
            return "Update available: v\(v) (currently v\(currentVersion))."
        case let .readyToInstall(v):
            return "v\(v) downloaded — relaunch to install."
        case let .failed(reason):
            return "Check failed: \(reason)"
        case .idle:
            if lastCheckedAt == nil {
                return "Click \"Check for Updates\" to look for a new release."
            }
            return "Currently running v\(currentVersion)."
        }
    }

    private var checkedStamp: String? {
        guard let when = lastCheckedAt else { return nil }
        switch state {
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
