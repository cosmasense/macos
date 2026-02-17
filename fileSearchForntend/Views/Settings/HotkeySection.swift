//
//  HotkeySection.swift
//  fileSearchForntend
//
//  Hotkey recording, permissions, and system preferences helpers
//

import SwiftUI
import AppKit

// MARK: - Hotkey Section

struct HotkeySection: View {
    @Environment(AppModel.self) private var model
    @Binding var hotkey: String
    @State private var isRecording = false
    @State private var hasAccessibilityPermission = false
    @Environment(\.controlHotkeyMonitoring) private var controlHotkeys

    private var displayText: String {
        if isRecording { return "Press any key..." }
        return hotkeyDisplayString(hotkey) ?? "Not set"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Overlay Shortcut")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(displayText)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 200, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.12))
                    )

                Button(isRecording ? "Cancel" : "Record") {
                    isRecording.toggle()
                    controlHotkeys(!isRecording)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear") {
                    hotkey = ""
                    controlHotkeys(true)
                    isRecording = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(hotkey.isEmpty)
            }
            .background(
                HotkeyCaptureView(isRecording: $isRecording) { key in
                    hotkey = key.lowercased()
                    isRecording = false
                    controlHotkeys(true)
                }
                .allowsHitTesting(false)
            )

            Text("Click record, then press the key you'd like to use. Leave blank to disable the shortcut.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // Permissions Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                // Input Monitoring Permission (for global hotkey in sandboxed apps)
                PermissionRow(
                    title: "Input Monitoring",
                    description: hasAccessibilityPermission
                        ? "Global hotkey works when app is not focused"
                        : "Grant to use the global hotkey when app is not focused",
                    isGranted: hasAccessibilityPermission,
                    action: {
                        if !hasAccessibilityPermission {
                            requestInputMonitoringPermission()
                        } else {
                            openInputMonitoringPreferences()
                        }
                    }
                )

                // Files and Folders — sandboxed app uses security-scoped bookmarks
                let bookmarkCount = model.securityBookmarks.count
                PermissionRow(
                    title: "Files and Folders",
                    description: bookmarkCount > 0
                        ? "Access granted to \(bookmarkCount) folder\(bookmarkCount == 1 ? "" : "s") via bookmarks"
                        : "Add a folder to watch to grant file access",
                    isGranted: bookmarkCount > 0,
                    action: { openFullDiskAccessPreferences() }
                )
            }
        }
        .onAppear {
            checkPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check permissions when app becomes active (user may have granted in System Settings)
            checkPermissions()
        }
    }

    private func checkPermissions() {
        // For sandboxed apps, use CGPreflightListenEventAccess for Input Monitoring
        // AXIsProcessTrusted always returns false in sandboxed apps
        hasAccessibilityPermission = checkInputMonitoringPermission()
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool?  // nil means we can't detect
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Group {
                if let granted = isGranted {
                    Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(granted ? .green : .red)
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 18))

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))

                    if let granted = isGranted {
                        Text(granted ? "Granted" : "Not Granted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(granted ? .green : .red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (granted ? Color.green : Color.red).opacity(0.15),
                                in: Capsule()
                            )
                    }
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action button
            Button {
                action()
            } label: {
                if let granted = isGranted, granted {
                    Text("Open Settings")
                } else {
                    Text("Grant Access")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Hotkey Capture View

private struct HotkeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (String) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onCapture = onCapture
    }

    final class CaptureView: NSView {
        var onCapture: ((String) -> Void)?
        var isRecording = false {
            didSet {
                if isRecording {
                    window?.makeFirstResponder(self)
                }
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            guard let chars = event.charactersIgnoringModifiers,
                  let first = chars.first else {
                return
            }
            let normalizedKey: String
            if first == " " {
                normalizedKey = "space"
            } else if first.isLetter || first.isNumber {
                normalizedKey = String(first).lowercased()
            } else {
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let components = normalizedModifiers(flags) + [normalizedKey]
            onCapture?(components.joined(separator: "+"))
        }
    }
}

// MARK: - Permission Helpers

/// Check Input Monitoring permission (works in sandboxed apps)
/// This is the recommended approach for sandboxed apps instead of AXIsProcessTrusted
private func checkInputMonitoringPermission() -> Bool {
    // CGPreflightListenEventAccess checks if we have Input Monitoring permission
    // This works in sandboxed apps, unlike AXIsProcessTrusted
    return CGPreflightListenEventAccess()
}

/// Request Input Monitoring permission
private func requestInputMonitoringPermission() {
    // CGRequestListenEventAccess shows the system dialog for Input Monitoring
    CGRequestListenEventAccess()
}

private func openAccessibilityPreferences() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}

private func openInputMonitoringPreferences() {
    // Open Input Monitoring settings (for sandboxed apps)
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
        NSWorkspace.shared.open(url)
    }
}

private func openFullDiskAccessPreferences() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Hotkey String Helpers

private func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> [String] {
    var parts: [String] = []
    if flags.contains(.command) { parts.append("command") }
    if flags.contains(.option) { parts.append("option") }
    if flags.contains(.control) { parts.append("control") }
    if flags.contains(.shift) { parts.append("shift") }
    return parts
}

private func hotkeyDisplayString(_ raw: String) -> String? {
    guard !raw.isEmpty else { return nil }
    let parts = raw.split(separator: "+").map { String($0) }
    guard let key = parts.last else { return nil }
    let modifiers = parts.dropLast().map { modifierSymbol($0) }
    let keySymbol = key == "space" ? "Space" : key.uppercased()
    let symbols = modifiers + [keySymbol]
    return symbols.joined(separator: " ")
}

private func modifierSymbol(_ raw: String) -> String {
    switch raw {
    case "command":
        return "\u{2318}"
    case "option":
        return "\u{2325}"
    case "control":
        return "\u{2303}"
    case "shift":
        return "\u{21E7}"
    default:
        return raw.uppercased()
    }
}
