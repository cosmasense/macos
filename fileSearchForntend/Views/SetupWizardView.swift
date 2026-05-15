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
    case welcome = 0
    case fullDiskAccess = 1
    case shortcut = 2
    case chooseBackend = 3
    case settingUp = 4

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .fullDiskAccess: return "Full Disk Access"
        case .shortcut: return "Quick Search Shortcut"
        case .chooseBackend: return "Choose AI Backend"
        case .settingUp: return "Setting Up"
        }
    }

    /// Whether this step contributes to the visual step indicator.
    /// Welcome is pre-flight onboarding chrome and intentionally
    /// excluded so the dots show a meaningful 4-step progression.
    var showsInIndicator: Bool { self != .welcome }
}

struct SetupWizardView: View {
    @Environment(CosmaManager.self) private var cosmaManager
    @AppStorage("overlayHotkey") private var overlayHotkey = ""
    @AppStorage("overlayTriggerMode") private var overlayTriggerMode = "hotkey"

    // Provider + per-provider model choices. Persisted across launches
    // so re-running the wizard (after a model purge or first-launch
    // crash) remembers what the user picked. Names are kept aligned
    // with the backend setting paths in CosmaManager+Bootstrap.
    @AppStorage("aiProvider") private var provider: String = "llamacpp"
    @AppStorage("wizardLlamacppMode") private var llamacppMode: String = "default"
    @AppStorage("wizardLlamacppRepo") private var llamacppRepo: String = "unsloth/Qwen3-VL-2B-Instruct-GGUF"
    @AppStorage("wizardLlamacppFilename") private var llamacppFilename: String = "*Q4_K_M.gguf"
    @AppStorage("wizardOllamaModel") private var ollamaModel: String = "qwen3-vl:2b-instruct"
    @AppStorage("wizardOnlineEndpoint") private var onlineEndpoint: String = "https://api.openai.com/v1"
    @AppStorage("wizardOnlineModel") private var onlineModel: String = "gpt-4.1-nano"
    @AppStorage("wizardOnlineApiKey") private var onlineApiKey: String = ""

    @State private var step: SetupStep = .welcome
    @State private var hasFullDiskAccess: Bool = false
    @State private var didStartBackend = false

    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if step.showsInIndicator {
                StepIndicator(current: step)
                    .padding(.top, 28)
                    .padding(.bottom, 10)

                Divider().opacity(0.35)
            }

            Group {
                switch step {
                case .welcome:
                    WelcomeStep(onContinue: advance)
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
                case .chooseBackend:
                    ChooseBackendStep(
                        provider: $provider,
                        llamacppMode: $llamacppMode,
                        llamacppRepo: $llamacppRepo,
                        llamacppFilename: $llamacppFilename,
                        ollamaModel: $ollamaModel,
                        onlineEndpoint: $onlineEndpoint,
                        onlineModel: $onlineModel,
                        onlineApiKey: $onlineApiKey,
                        onContinue: advance,
                        onAppearAction: startBackendIfNeeded
                    )
                case .settingUp:
                    SettingUpStep(
                        provider: provider,
                        llamacppMode: llamacppMode,
                        llamacppRepo: llamacppRepo,
                        llamacppFilename: llamacppFilename,
                        ollamaModel: ollamaModel,
                        onlineEndpoint: onlineEndpoint,
                        onlineModel: onlineModel,
                        onlineApiKey: onlineApiKey,
                        onContinue: onFinished,
                        onGoBack: { step = .chooseBackend },
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

    /// Steps shown in the indicator. Welcome is excluded so the dots
    /// reflect the four "real" setup steps and number them 1..4.
    private var visibleSteps: [SetupStep] {
        SetupStep.allCases.filter { $0.showsInIndicator }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(visibleSteps.enumerated()), id: \.offset) { idx, s in
                HStack(spacing: 10) {
                    dot(for: s, displayNumber: idx + 1)
                    if idx < visibleSteps.count - 1 {
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
    private func dot(for s: SetupStep, displayNumber: Int) -> some View {
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
                Text("\(displayNumber)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.brandBlue : .secondary)
            }
        }
    }
}

// MARK: - Step 0: Welcome

/// First-launch landing screen. Logo + name + one-sentence pitch +
/// Get Started. Skipped from the step indicator so it feels like a
/// hello rather than the first chore.
private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            // App icon. NSApplication.applicationIconImage returns the
            // bundle's icon at the largest available rep, which we
            // size up to 128. NSImage → SwiftUI Image keeps Retina
            // scaling correct (no mushy upscale of the 32pt rep).
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)

            VStack(spacing: 10) {
                Text("Cosma Sense")
                    .font(.system(size: 28, weight: .semibold))
                Text("Vector search for your Mac — find files by meaning, not just by name.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 60)
            }

            Spacer()

            Button(action: onContinue) {
                HStack(spacing: 6) {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
                .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandBlue)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // Header (icon + title + subtitle) and footer (action button) are
        // pinned; middle content scrolls if it overflows. Without this
        // the AI Model step's provider picker pushed the Confirm button
        // off the bottom of the 620×560 wizard window.
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.brandBlue)
                    .padding(.top, 20)
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .padding(.horizontal, 40)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            footer()
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 40)
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
        // lineLimit(1) + fixedSize keeps the cap one line wide regardless
        // of parent width. Without this, multi-char labels like "Space"
        // hit the HStack's width budget and wrap mid-word ("Spa/ce").
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            // Wider caps so "Space" and two-char labels breathe without
            // looking cramped next to the "+" separators.
            .frame(minWidth: 44, minHeight: 22)
            .padding(.horizontal, 10)
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

// MARK: - Step 3: Choose AI Backend

/// Selection-only AI step. The user picks a provider and (where the
/// provider has knobs) the specific model details. No download fires
/// here — that's deferred to SettingUpStep so this screen stays a
/// pure "I am committing to this configuration" surface.
///
/// Per-provider sub-forms:
///   * llama.cpp: Default (recommended Qwen3-VL Q4_K_M GGUF) or
///     Custom (HuggingFace repo + filename, validated downstream by
///     the bootstrap install).
///   * Ollama: model name + Test Connection button (pings local
///     Ollama daemon, reports daemon/model status).
///   * Online: OpenAI-compatible endpoint + model + API key. Three
///     fields because users use Together/Groq/LM Studio/etc., not
///     just OpenAI proper.
///
/// Ollama row only appears if the binary is installed locally — no
/// point offering an option that can't possibly succeed.
private struct ChooseBackendStep: View {
    @Binding var provider: String
    @Binding var llamacppMode: String          // "default" | "custom"
    @Binding var llamacppRepo: String
    @Binding var llamacppFilename: String
    @Binding var ollamaModel: String
    @Binding var onlineEndpoint: String
    @Binding var onlineModel: String
    @Binding var onlineApiKey: String
    let onContinue: () -> Void
    let onAppearAction: () -> Void

    @State private var ollamaInstalled: Bool = ollamaIsInstalled()
    @State private var ollamaTestResult: TestResult = .untested
    @State private var ollamaTesting: Bool = false

    enum TestResult: Equatable {
        case untested
        case success(String)
        case warning(String)
        case failure(String)
    }

    var body: some View {
        StepShell(
            icon: "brain.head.profile",
            title: "Choose AI Backend",
            subtitle: "Pick how Cosma Sense will run its AI. You can change this later in Settings."
        ) {
            VStack(spacing: 10) {
                ProviderRow(
                    key: "llamacpp",
                    title: "llama.cpp built-in (recommended)",
                    description: "Fully local. Self-contained. No setup required.",
                    selected: provider == "llamacpp",
                    onSelect: { provider = "llamacpp" }
                )
                if provider == "llamacpp" { llamacppSubForm }

                if ollamaInstalled {
                    ProviderRow(
                        key: "ollama",
                        title: "Ollama",
                        description: "Local, uses the external Ollama daemon.",
                        selected: provider == "ollama",
                        onSelect: { provider = "ollama" }
                    )
                    if provider == "ollama" { ollamaSubForm }
                }

                ProviderRow(
                    key: "online",
                    title: "Online (OpenAI-compatible)",
                    description: "Fastest setup. Sends file content to the configured endpoint.",
                    selected: provider == "online",
                    onSelect: { provider = "online" }
                )
                if provider == "online" { onlineSubForm }
            }
        } footer: {
            Button(action: onContinue) {
                HStack(spacing: 6) {
                    Text("Confirm")
                    Image(systemName: "arrow.right")
                }
                .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandBlue)
            .controlSize(.large)
            .disabled(!isReady)
        }
        .onAppear {
            // Re-check installed state (user may have just installed
            // Ollama via Homebrew while the wizard was open) and let
            // the parent kick off the backend startup so it's warming
            // up while the user reads this screen.
            ollamaInstalled = Self.ollamaIsInstalled()
            // Sanity: if the persisted provider is .ollama but Ollama
            // disappeared since last launch, drop back to the default.
            if provider == "ollama" && !ollamaInstalled {
                provider = "llamacpp"
            }
            onAppearAction()
        }
    }

    /// Whether the user has filled in enough info to proceed.
    /// Empty fields would PUT empty strings to the backend, which
    /// `setProviderConfigAndBootstrap` already filters out — but
    /// surfacing the gate as a disabled button is a clearer signal.
    private var isReady: Bool {
        switch provider {
        case "llamacpp":
            if llamacppMode == "default" { return true }
            return !llamacppRepo.trimmingCharacters(in: .whitespaces).isEmpty
                && !llamacppFilename.trimmingCharacters(in: .whitespaces).isEmpty
        case "ollama":
            return !ollamaModel.trimmingCharacters(in: .whitespaces).isEmpty
        case "online":
            return !onlineEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
                && !onlineModel.trimmingCharacters(in: .whitespaces).isEmpty
                && !onlineApiKey.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return false
        }
    }

    // MARK: - llama.cpp sub-form

    private var llamacppSubForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Model", selection: $llamacppMode) {
                Text("Default — Qwen3-VL-2B-Instruct Q4_K_M (~2.1 GB)").tag("default")
                Text("Custom (advanced)").tag("custom")
            }
            .pickerStyle(.radioGroup)

            if llamacppMode == "custom" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HuggingFace Repo ID")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. unsloth/Qwen3-VL-2B-Instruct-GGUF", text: $llamacppRepo)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    Text("Filename pattern")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. *Q4_K_M.gguf", text: $llamacppFilename)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    Text("If the repo or filename can't be downloaded, you'll see the error in the next step and can come back to fix it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Ollama sub-form

    private var ollamaSubForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("qwen3-vl:2b-instruct", text: $ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button {
                    runOllamaTest()
                } label: {
                    HStack(spacing: 4) {
                        if ollamaTesting { ProgressView().controlSize(.mini) }
                        Text("Test Connection")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(ollamaTesting || ollamaModel.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            switch ollamaTestResult {
            case .untested:
                Text("Click Test Connection to verify the daemon is running and the model is available.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .success(let msg):
                Label(msg, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            case .warning(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            case .failure(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Online sub-form

    private var onlineSubForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Endpoint URL")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("https://api.openai.com/v1", text: $onlineEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Model name")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("gpt-4.1-nano", text: $onlineModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API key")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("sk-…", text: $onlineApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            Text("Works with any OpenAI-compatible API — OpenAI, Together, Groq, LM Studio, vLLM, etc. The key is stored in the backend's settings file (chmod 600).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Ollama detection + test

    /// Quick install probe — checks the two paths Homebrew installs
    /// Ollama into. We don't try to launch `ollama` because that would
    /// pop up a permission prompt or silently fail; just check
    /// presence on disk.
    static func ollamaIsInstalled() -> Bool {
        let candidates = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Hits Ollama's tag-listing endpoint to verify the daemon is
    /// running and the requested model is pulled. Distinguishes
    /// three failure modes so we can guide the user accordingly:
    ///   * daemon unreachable → tell them to start Ollama
    ///   * daemon up, model missing → harmless warning, model will
    ///     be auto-pulled on first use (we still let them proceed)
    ///   * 200 with model present → green check
    private func runOllamaTest() {
        ollamaTesting = true
        ollamaTestResult = .untested
        let model = ollamaModel.trimmingCharacters(in: .whitespaces)
        Task {
            let result = await Self.probeOllama(model: model)
            await MainActor.run {
                ollamaTestResult = result
                ollamaTesting = false
            }
        }
    }

    private static func probeOllama(model: String) async -> TestResult {
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            return .failure("Could not build request URL.")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure("Daemon responded with an unexpected status.")
            }
            // {"models":[{"name":"qwen3-vl:2b-instruct", ...}, ...]}
            struct Tags: Decodable { struct Model: Decodable { let name: String }; let models: [Model]? }
            let parsed = (try? JSONDecoder().decode(Tags.self, from: data)) ?? Tags(models: nil)
            let names = parsed.models?.map(\.name) ?? []
            if names.contains(model) {
                return .success("Daemon reachable; model \"\(model)\" is installed.")
            }
            return .warning("Daemon reachable but model \"\(model)\" isn't pulled yet — it will be downloaded on first use.")
        } catch {
            return .failure("Could not reach Ollama at localhost:11434. Make sure the daemon is running.")
        }
    }
}

// MARK: - Step 4: Setting Up

/// Combined "downloading models" + "starting backend" screen. Replaces
/// the previous two separate AI-download and backend-startup steps so
/// the user sees one progress surface for the whole post-confirm
/// install flow. Triggers `setProviderConfigAndBootstrap` on appear
/// with whatever the user picked in ChooseBackendStep.
private struct SettingUpStep: View {
    @Environment(CosmaManager.self) private var cosmaManager

    let provider: String
    let llamacppMode: String
    let llamacppRepo: String
    let llamacppFilename: String
    let ollamaModel: String
    let onlineEndpoint: String
    let onlineModel: String
    let onlineApiKey: String
    let onContinue: () -> Void
    let onGoBack: () -> Void
    let onAppearAction: () -> Void

    @State private var didKickInstall = false

    private var backendReady: Bool {
        if case .running = cosmaManager.setupStage { return true }
        return false
    }

    private var bootstrapDone: Bool { cosmaManager.bootstrapReady }
    private var allDone: Bool { backendReady && bootstrapDone }

    private var backendStatusText: String {
        switch cosmaManager.setupStage {
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
            icon: "gearshape.2.fill",
            title: "Setting Up",
            subtitle: "Downloading models and starting the background service. This can take a few minutes on the first run."
        ) {
            VStack(spacing: 14) {
                // Backend startup row.
                HStack(spacing: 10) {
                    Image(systemName: backendReady ? "checkmark.circle.fill" : "gearshape.2")
                        .font(.system(size: 16))
                        .foregroundStyle(backendReady ? .green : Color.brandBlue)
                    Text(backendStatusText)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if !backendReady { ProgressView().controlSize(.small) }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                // Bootstrap component progress (model downloads).
                if !cosmaManager.bootstrapComponents.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(cosmaManager.bootstrapComponents) { c in
                            BootstrapRow(component: c)
                        }
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                if let err = cosmaManager.bootstrapError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Download error", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Go Back & Edit") { onGoBack() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.red.opacity(0.4))
                    )
                }
            }
        } footer: {
            Button(action: onContinue) {
                Text(allDone ? "Start Cosma Sense" : "Please wait…")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandBlue)
            .controlSize(.large)
            .disabled(!allDone)
        }
        .onAppear {
            onAppearAction()
            kickInstallOnce()
        }
    }

    /// Wait for the backend to be reachable, then PUT the user's
    /// chosen settings and kick off (or join) a bootstrap install.
    /// Idempotent — guarded by didKickInstall so window resizes /
    /// view re-mounts don't re-fire the install.
    private func kickInstallOnce() {
        guard !didKickInstall else { return }
        didKickInstall = true
        Task {
            // Wait up to ~30s for the backend's HTTP listener.
            for _ in 0..<60 {
                if cosmaManager.isRunning { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            await cosmaManager.refreshBootstrapStatus()
            if cosmaManager.bootstrapReady {
                // Already installed — nothing to download. Settings
                // still get written so a subsequent restart picks up
                // the user's most recent choice.
            }
            // For the default llama.cpp path we deliberately pass
            // nil for repo+filename so we don't blow away the user's
            // (or backend's) defaults. Custom mode passes through
            // exactly what the user typed.
            let llamaRepoArg: String? = (provider == "llamacpp" && llamacppMode == "custom") ? llamacppRepo : nil
            let llamaFileArg: String? = (provider == "llamacpp" && llamacppMode == "custom") ? llamacppFilename : nil
            await cosmaManager.setProviderConfigAndBootstrap(
                summarizer: provider,
                whisper: provider == "online" ? "online" : "local",
                llamacppRepo: llamaRepoArg,
                llamacppFilename: llamaFileArg,
                ollamaModel: provider == "ollama" ? ollamaModel : nil,
                onlineModel: provider == "online" ? onlineModel : nil,
                onlineBaseURL: provider == "online" ? onlineEndpoint : nil,
                onlineApiKey: provider == "online" ? onlineApiKey : nil
            )
        }
    }
}

/// Radio-style row for the provider picker.
private struct ProviderRow: View {
    let key: String
    let title: String
    let description: String
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color.brandBlue : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.brandBlue.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.brandBlue : Color.secondary.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
    }
}

/// One row in the bootstrap list.
///
/// Layout: fixed-width label on the left, then a VStack(bar, percent text)
/// taking the remaining width. Earlier versions put the percent text in a
/// ZStack overlay with a negative y-offset; that pushed it out of the
/// row's clipping bounds on macOS so the text was invisible even though
/// it was rendered. A plain VStack is reliable across SwiftUI versions.
private struct BootstrapRow: View {
    let component: BootstrapComponent

    private var done: Bool { component.present || component.done }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundStyle(done ? .green : Color.brandBlue)

            Text(component.displayLabel)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            if done {
                Spacer()
                Text("Ready").font(.caption2).foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: component.fraction)
                        .progressViewStyle(.linear)
                    Text(component.inlineProgressText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: done ? 22 : 34)
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
