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
    @AppStorage("overlayTriggerMode") private var triggerMode = "hotkey"
    @State private var isRecording = false
    @State private var errorText: String?
    @Environment(\.controlHotkeyMonitoring) private var controlHotkeys

    private static let reservedShortcuts: Set<String> = [
        "command+q", "command+w", "command+c", "command+v", "command+x",
        "command+a", "command+z", "command+s", "command+n", "command+t",
        "command+f", "command+p", "command+h", "command+m", "command+o",
        "command+space", "command+tab", "command+shift+3", "command+shift+4",
        "command+shift+5", "command+shift+z", "command+option+esc"
    ]

    private func validate(_ raw: String) -> String? {
        let parts = raw.split(separator: "+").map(String.init)
        guard parts.count >= 2 else { return "Include at least one modifier (⌘, ⌥, ⌃, or ⇧)." }
        if Self.reservedShortcuts.contains(raw) { return "That shortcut is reserved by macOS. Try another." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set a keyboard shortcut to open the search overlay from anywhere.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if isRecording {
                    Text("Press keys then release…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.brandBlue)
                } else {
                    ShortcutKeyCapsView(parts: hotkey.isEmpty
                                        ? ["command", "command"]
                                        : hotkey.split(separator: "+").map(String.init))
                    Text(hotkey.isEmpty ? "Tap both Command keys" : "")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRecording {
                    Button("Cancel") {
                        isRecording = false
                        controlHotkeys(true)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                } else {
                    if !hotkey.isEmpty {
                        Button("Reset") { hotkey = "" }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Button("Change") {
                        errorText = nil
                        hotkey = ""
                        isRecording = true
                        controlHotkeys(false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .background(
                InlineHotkeyCapture(isRecording: $isRecording) { key in
                    if let err = validate(key) {
                        errorText = err
                    } else {
                        errorText = nil
                        hotkey = key
                    }
                    isRecording = false
                    controlHotkeys(true)
                }
                .allowsHitTesting(false)
            )

            if let errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(errorText).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            // Permissions Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                // Full Disk Access — required for indexing all files
                PermissionRow(
                    title: "Full Disk Access",
                    description: hasFullDiskAccess
                        ? "Can index files across all folders"
                        : "Required to index files and run the backend",
                    isGranted: hasFullDiskAccess,
                    action: { openFullDiskAccessPreferences() }
                )
            }
        }
        .onChange(of: hotkey) { _, newValue in
            triggerMode = newValue.isEmpty ? "dualCommand" : "hotkey"
        }
        .onAppear {
            checkPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
    }

    @State private var hasFullDiskAccess = false

    private func checkPermissions() {
        hasFullDiskAccess = checkFullDiskAccessPermission()
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

// MARK: - Shortcut Key Caps (matches setup wizard)

private struct ShortcutKeyCapsView: View {
    let parts: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { idx, part in
                if idx > 0 { Text("+").foregroundStyle(.secondary) }
                KeyCap(text: symbol(for: part))
            }
        }
    }
    private func symbol(for s: String) -> String {
        switch s {
        case "command": return "\u{2318}"
        case "option": return "\u{2325}"
        case "control": return "\u{2303}"
        case "shift": return "\u{21E7}"
        case "space": return "Space"
        default: return s.uppercased()
        }
    }
}

private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 44, minHeight: 22)
            .padding(.horizontal, 10)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: - Inline Hotkey Capture (captures on modifier release)

private struct InlineHotkeyCapture: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (String) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let v = CaptureView()
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onCapture = onCapture
        nsView.isRecording = isRecording
    }

    final class CaptureView: NSView {
        var onCapture: ((String) -> Void)?
        private var pending: String?
        var isRecording = false {
            didSet {
                if isRecording { window?.makeFirstResponder(self); pending = nil }
            }
        }
        override var acceptsFirstResponder: Bool { true }

        private func modParts(_ flags: NSEvent.ModifierFlags) -> [String] {
            var m: [String] = []
            if flags.contains(.command) { m.append("command") }
            if flags.contains(.option) { m.append("option") }
            if flags.contains(.control) { m.append("control") }
            if flags.contains(.shift) { m.append("shift") }
            return m
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { super.keyDown(with: event); return }
            guard let chars = event.charactersIgnoringModifiers, let first = chars.first else { return }
            let keyName: String
            if first == " " { keyName = "space" }
            else if first.isLetter || first.isNumber { keyName = String(first).lowercased() }
            else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            pending = (modParts(flags) + [keyName]).joined(separator: "+")
        }

        override func flagsChanged(with event: NSEvent) {
            guard isRecording else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.isEmpty, let p = pending {
                pending = nil
                onCapture?(p)
            }
        }

        override func keyUp(with event: NSEvent) {
            guard isRecording else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.isEmpty, let p = pending {
                pending = nil
                onCapture?(p)
            }
        }
    }
}

// MARK: - Permission Helpers

/// Check Full Disk Access by actually opening the TCC database (always exists, always protected).
/// FileManager.isReadableFile is unreliable for TCC-protected paths — use open() directly.
func checkFullDiskAccessPermission() -> Bool {
    let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
    if fd != -1 {
        close(fd)
        return true
    }
    return false
}

private func openFullDiskAccessPreferences() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
        NSWorkspace.shared.open(url)
    }
}
