//
//  PermissionsSettingsView.swift
//  fileSearchForntend
//
//  Top-level Settings tab consolidating every macOS-level permission
//  the app may need. Lives in its own tab (not buried inside General
//  or Hotkey) so the user has a single, obvious place to confirm
//  permission state.
//

import SwiftUI
import AppKit
import UserNotifications

struct PermissionsSettingsView: View {
    @State private var fdaGranted: Bool = false
    @State private var notificationsState: UNAuthorizationStatus = .notDetermined
    @State private var accessibilityGranted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cosma Sense uses these macOS permissions. Each row shows the current state and a button to manage it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                PermissionRow(
                    icon: "lock.shield",
                    title: "Full Disk Access",
                    description: "Required to scan and index files outside Documents.",
                    granted: fdaGranted,
                    openButtonTitle: fdaGranted ? "Manage" : "Open System Settings",
                    openAction: openFullDiskAccessSettings
                )

                PermissionRow(
                    icon: "bell.badge",
                    title: "Notifications",
                    description: notificationDescriptionText,
                    granted: notificationsState == .authorized || notificationsState == .provisional,
                    openButtonTitle: notificationsState == .notDetermined ? "Request" : "Open System Settings",
                    openAction: handleNotificationButton
                )

                PermissionRow(
                    icon: "command.square",
                    title: "Accessibility",
                    description: "Used for the global hotkey monitor and dual-⌘ trigger.",
                    granted: accessibilityGranted,
                    openButtonTitle: accessibilityGranted ? "Manage" : "Open System Settings",
                    openAction: openAccessibilitySettings
                )
            }
        }
        .onAppear { refreshAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAll()
        }
    }

    private var notificationDescriptionText: String {
        switch notificationsState {
        case .authorized, .provisional:
            return "Banner alerts for indexing milestones and updates."
        case .denied:
            return "Currently denied — re-enable in System Settings to receive indexing and update alerts."
        case .ephemeral:
            return "Temporarily authorized."
        case .notDetermined:
            return "Click Request to allow banner alerts for indexing milestones and updates."
        @unknown default:
            return "Banner alerts for indexing milestones and updates."
        }
    }

    private func refreshAll() {
        fdaGranted = checkFullDiskAccessPermission()
        accessibilityGranted = detectAccessibilityCapability()
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.notificationsState = settings.authorizationStatus
            }
        }
    }

    /// AXIsProcessTrusted is the canonical accessibility check, but it
    /// can lie in two situations a user actually hits:
    ///   1. The TCC entry was created against a previous build's code
    ///      signature (rebuilds in Xcode shuffle the dev signature).
    ///      The toggle in System Settings stays ON, but for a *different
    ///      identity* than the running process, so AXIsProcessTrusted
    ///      keeps returning false.
    ///   2. macOS occasionally lags before flipping the value after the
    ///      user toggles the switch — fixed by a relaunch, but really
    ///      annoying to be told "Needed" while the switch reads ON.
    ///
    /// Workaround: also probe the actual capability the dual-⌘ trigger
    /// relies on by trying to create a passive CGEventTap. If we can
    /// install the tap, we have effective hotkey permission regardless
    /// of what the AX bit says. We invalidate immediately — this is a
    /// permission probe, not the real listener.
    private func detectAccessibilityCapability() -> Bool {
        return AXIsProcessTrusted() || canCreateGlobalEventTap()
    }

    private func canCreateGlobalEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    private func handleNotificationButton() {
        if notificationsState == .notDetermined {
            Task {
                await NotificationManager.shared.requestAuthorizationIfNeeded()
                refreshAll()
            }
            return
        }
        // No API for re-prompting after .denied — deep link into the
        // System Settings notifications pane and let the user toggle
        // the OS switch themselves.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let granted: Bool
    let openButtonTitle: String
    let openAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(granted ? Color.green : Color.brandBlue)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(granted ? Color.green : Color.orange)
                    Text(granted ? "Granted" : "Needed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(granted ? Color.green : Color.orange)
                }
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(openButtonTitle, action: openAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
