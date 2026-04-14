//
//  SetupWizardView.swift
//  fileSearchForntend
//
//  First-launch onboarding wizard.
//  Four steps: Full Disk Access → Shortcut → AI Model → Backend.
//

import SwiftUI
import AppKit

enum SetupStep: Int, CaseIterable {
    case fullDiskAccess = 0
    case shortcut = 1
    case aiModel = 2
    case backend = 3

    var title: String {
        switch self {
        case .fullDiskAccess: return "Full Disk Access"
        case .shortcut: return "Quick Search Shortcut"
        case .aiModel: return "AI Model"
        case .backend: return "Finishing Setup"
        }
    }
}

struct SetupWizardView: View {
    @Environment(CosmaManager.self) private var cosmaManager
    @AppStorage("overlayHotkey") private var overlayHotkey = ""
    @AppStorage("overlayTriggerMode") private var overlayTriggerMode = "hotkey"

    @State private var step: SetupStep = .fullDiskAccess
    @State private var hasFullDiskAccess: Bool = false
    @State private var didStartBackend = false

    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(current: step)
                .padding(.top, 28)
                .padding(.bottom, 10)

            Divider().opacity(0.35)

            Group {
                switch step {
                case .fullDiskAccess:
                    FullDiskAccessStep(
                        hasAccess: $hasFullDiskAccess,
                        onContinue: advance
                    )
                case .shortcut:
                    ShortcutStep(
                        hotkey: $overlayHotkey,
                        triggerMode: $overlayTriggerMode,
                        onContinue: advance
                    )
                case .aiModel:
                    AIModelStep(
                        stage: cosmaManager.setupStage,
                        onContinue: advance,
                        onAppearAction: startBackendIfNeeded
                    )
                case .backend:
                    BackendStep(
                        stage: cosmaManager.setupStage,
                        onContinue: onFinished,
                        onAppearAction: startBackendIfNeeded
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color.white.opacity(0.4))
                .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.25), value: step)
        .onAppear {
            hasFullDiskAccess = checkFullDiskAccessPermission()
            if hasFullDiskAccess && step == .fullDiskAccess {
                // Allow user to still see the step; don't auto-skip.
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = checkFullDiskAccessPermission()
        }
    }

    private func advance() {
        guard let next = SetupStep(rawValue: step.rawValue + 1) else {
            onFinished()
            return
        }
        step = next
    }

    private func startBackendIfNeeded() {
        guard !didStartBackend else { return }
        didStartBackend = true
        Task { await cosmaManager.startManagedBackend() }
    }
}

// MARK: - Step Indicator

private struct StepIndicator: View {
    let current: SetupStep

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SetupStep.allCases, id: \.rawValue) { s in
                HStack(spacing: 10) {
                    dot(for: s)
                    if s != SetupStep.allCases.last {
                        Rectangle()
                            .fill(s.rawValue < current.rawValue ? Color.brandBlue : Color.secondary.opacity(0.25))
                            .frame(width: 36, height: 2)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
    }

    @ViewBuilder
    private func dot(for s: SetupStep) -> some View {
        let isDone = s.rawValue < current.rawValue
        let isCurrent = s == current
        ZStack {
            Circle()
                .fill(isDone ? Color.brandBlue : (isCurrent ? Color.brandBlue.opacity(0.18) : Color.secondary.opacity(0.15)))
                .frame(width: 28, height: 28)
            Circle()
                .strokeBorder(isCurrent ? Color.brandBlue : .clear, lineWidth: 2)
                .frame(width: 28, height: 28)

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(s.rawValue + 1)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.brandBlue : .secondary)
            }
        }
    }
}

// MARK: - Step Shell

private struct StepShell<Content: View, Footer: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Color.brandBlue)
                .padding(.top, 32)

            Text(title)
                .font(.system(size: 22, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            content()
                .padding(.horizontal, 40)

            Spacer(minLength: 8)

            footer()
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 56)
    }
}

// MARK: - Step 1: Full Disk Access

private struct FullDiskAccessStep: View {
    @Binding var hasAccess: Bool
    let onContinue: () -> Void
    @State private var isChecking = false

    var body: some View {
        StepShell(
            icon: "lock.shield.fill",
            title: "Full Disk Access",
            subtitle: "Cosma Sense searches your whole Mac to find files by name, content, and meaning — powered by local semantic search. To do that, it needs permission to read your files."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "Click \"Open System Settings\" below")
                StepRow(number: 2, text: "Find Cosma Sense in the list and enable it")
                StepRow(number: 3, text: "Come back and click \"Continue\"")

                if !hasAccess {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Access not granted yet — Continue will unlock once enabled.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        } footer: {
            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open System Settings", systemImage: "gear").frame(minWidth: 180)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Task {
                        isChecking = true
                        try? await Task.sleep(for: .milliseconds(300))
                        hasAccess = checkFullDiskAccessPermission()
                        isChecking = false
                        if hasAccess { onContinue() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isChecking { ProgressView().controlSize(.small) }
                        Text("Continue")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
                .controlSize(.large)
                .disabled(!hasAccess)
            }
        }
    }
}

// MARK: - Step 2: Shortcut

private struct ShortcutStep: View {
    @Binding var hotkey: String
    @Binding var triggerMode: String
    let onContinue: () -> Void
    @State private var isRecording = false
    @State private var errorText: String?

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
        StepShell(
            icon: "keyboard",
            title: "Set Up Shortcut",
            subtitle: "Use a shortcut to open Quick Search from anywhere — no need to switch apps."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Shortcut")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

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
                        Button("Cancel") { isRecording = false }
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
                            isRecording = false
                        } else {
                            errorText = nil
                            hotkey = key
                            isRecording = false
                        }
                    }
                    .allowsHitTesting(false)
                )

                if let errorText {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(errorText).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: hotkey) { _, newValue in
                triggerMode = newValue.isEmpty ? "dualCommand" : "hotkey"
            }
        } footer: {
            Button(action: onContinue) {
                Text("Continue").frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandBlue)
            .controlSize(.large)
        }
    }
}

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
            .font(.system(size: 14, weight: .semibold))
            .frame(minWidth: 28, minHeight: 26)
            .padding(.horizontal, 6)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5))
    }
}

private func hotkeyDisplay(_ raw: String) -> String {
    guard !raw.isEmpty else { return "Not set" }
    let parts = raw.split(separator: "+").map(String.init)
    guard let key = parts.last else { return raw.uppercased() }
    let mods = parts.dropLast().map { s -> String in
        switch s {
        case "command": return "\u{2318}"
        case "option": return "\u{2325}"
        case "control": return "\u{2303}"
        case "shift": return "\u{21E7}"
        default: return s.uppercased()
        }
    }
    let keySym = key == "space" ? "Space" : key.uppercased()
    return (mods + [keySym]).joined(separator: " ")
}

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

// MARK: - Step 3: AI Model

private struct AIModelStep: View {
    let stage: CosmaManager.SetupStage
    let onContinue: () -> Void
    let onAppearAction: () -> Void

    private var status: (icon: String, text: String, done: Bool) {
        switch stage {
        case .pullingOllamaModel:
            return ("arrow.down.circle", "Downloading AI model…", false)
        case .installingOllama:
            return ("square.and.arrow.down", "Installing Ollama…", false)
        case .checkingOllama:
            return ("magnifyingglass", "Checking for Ollama…", false)
        case .startingServer, .running:
            return ("checkmark.circle.fill", "AI model ready", true)
        default:
            return ("hourglass", "Preparing…", false)
        }
    }

    var body: some View {
        StepShell(
            icon: "brain.head.profile",
            title: "Download AI Model",
            subtitle: "Cosma Sense uses a local AI model for smart file summaries. This downloads automatically — about 2 GB."
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: status.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(status.done ? .green : Color.brandBlue)
                    Text(status.text)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    if !status.done { ProgressView().controlSize(.small) }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        } footer: {
            Button(action: onContinue) {
                Text(status.done ? "Continue" : "Continue Anyway").frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandBlue)
            .controlSize(.large)
        }
        .onAppear(perform: onAppearAction)
    }
}

// MARK: - Step 4: Backend

private struct BackendStep: View {
    let stage: CosmaManager.SetupStage
    let onContinue: () -> Void
    let onAppearAction: () -> Void

    private var isReady: Bool {
        if case .running = stage { return true }
        return false
    }

    private var statusText: String {
        switch stage {
        case .running: return "Backend running"
        case .startingServer: return "Starting server…"
        case .installingCosma: return "Installing cosma…"
        case .checkingCosma: return "Checking for cosma…"
        case .installingUV: return "Installing package manager…"
        case .checkingUV: return "Checking for package manager…"
        case .failed(let msg): return "Failed: \(msg)"
        default: return "Preparing…"
        }
    }

    var body: some View {
        StepShell(
            icon: "server.rack",
            title: "Finishing Setup",
            subtitle: "Starting the background service that indexes your files."
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: isReady ? "checkmark.circle.fill" : "gearshape.2")
                        .font(.system(size: 18))
                        .foregroundStyle(isReady ? .green : Color.brandBlue)
                    Text(statusText)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    if !isReady { ProgressView().controlSize(.small) }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        } footer: {
            Button(action: onContinue) {
                Text(isReady ? "Start Cosma Sense" : "Please wait…").frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandBlue)
            .controlSize(.large)
            .disabled(!isReady)
        }
        .onAppear(perform: onAppearAction)
    }
}

// MARK: - Step Row (shared with Full Disk view)

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.brandBlue))

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}
