//
//  CosmaManager.swift
//  fileSearchForntend
//
//  Manages the cosma backend lifecycle: auto-install, run, update.
//

import Foundation

@MainActor
@Observable
class CosmaManager {

    // MARK: - Types

    enum SetupStage: Equatable {
        case idle
        case checkingUV
        case installingUV
        case checkingCosma
        case installingCosma
        case checkingOllama
        case installingOllama
        case pullingOllamaModel
        case startingServer
        case running
        case stopped
        case failed(String)
    }

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case available(installed: String, latest: String)
        case updating
        case upToDate
        case failed(String)
    }

    // MARK: - Published State

    var setupStage: SetupStage = .idle
    var updateStatus: UpdateStatus = .idle
    var installedVersion: String?
    var latestVersion: String?
    var serverLog: String = ""

    /// Whether this manager spawned the process (vs attaching to an existing one)
    var ownsProcess: Bool = false

    /// Saved launch config for crash-restart
    private var lastLaunchExe: String?
    private var lastLaunchArgs: [String] = []

    /// Always managed — backend starts and stops with the frontend app.
    var isManaged: Bool = true

    var isRunning: Bool { setupStage == .running }

    var stageDescription: String {
        switch setupStage {
        case .idle: return "Idle"
        case .checkingUV: return "Checking for uv…"
        case .installingUV: return "Installing uv…"
        case .checkingCosma: return "Checking for cosma…"
        case .installingCosma: return "Installing cosma…"
        case .checkingOllama: return "Checking for Ollama…"
        case .installingOllama: return "Installing Ollama…"
        case .pullingOllamaModel: return "Downloading AI model…"
        case .startingServer: return "Starting server…"
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    // MARK: - Private State

    @ObservationIgnored private var serverProcess: Process?
    @ObservationIgnored private var stdoutPipe: Pipe?
    @ObservationIgnored private var stderrPipe: Pipe?
    @ObservationIgnored private var updateTimer: Timer?
    @ObservationIgnored private var restartCount = 0
    @ObservationIgnored private let maxRestarts = 3
    @ObservationIgnored private var recoveryPollTask: Task<Void, Never>?
    @ObservationIgnored private var dismissedVersion: String? {
        get { UserDefaults.standard.string(forKey: "cosmaDismissedUpdateVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "cosmaDismissedUpdateVersion") }
    }

    // MARK: - Main Entry Point

    func startManagedBackend() async {
        print("[CosmaManager] startManagedBackend called")
        stopRecoveryPolling()

        // Step 1: Quick attach if backend is already running (no setup needed)
        if await isBackendReachable() {
            ownsProcess = false
            // Still ensure Ollama + summarizer model are ready, even when
            // attaching to an existing backend — otherwise the summarizer
            // endpoint fails and the "model unavailable" banner shows.
            await ensureOllamaAndModel()
            setupStage = .running
            installedVersion = await getInstalledVersion()
            scheduleUpdateChecks()
            return
        }

        // Step 2: Check prerequisites and launch the server.
        // Three strategies, tried in order:
        //   1. Local dev venv (for developers working in the repo)
        //   2. `cosma` already installed via uv tool
        //   3. Auto-install: ensure uv → ensure cosma → launch
        do {
            let home = realHomeDirectory()

            // --- Strategy 1: Local dev repo with venv ---
            setupStage = .checkingUV
            await Task.yield()

            let repoRoot = "\(home)/Documents/code/SAIL/cosma"
            let venvActivate = "\(repoRoot)/.venv/bin/activate"
            let backendInit = "\(repoRoot)/packages/cosma-backend/src/cosma_backend/__init__.py"

            if FileManager.default.fileExists(atPath: venvActivate) &&
               FileManager.default.fileExists(atPath: backendInit) {
                setupStage = .checkingCosma
                await Task.yield()
                await ensureOllamaAndModel()
                setupStage = .startingServer

                let venvPython = "\(repoRoot)/.venv/bin/python"
                let pythonPath = "\(repoRoot)/packages/cosma-backend/src"
                appendLog("[CosmaManager] Launching python directly: \(venvPython) -m cosma_backend")
                try await launchBackendProcess(
                    executable: venvPython,
                    arguments: ["-m", "cosma_backend"],
                    extraEnv: [
                        "PYTHONPATH": pythonPath,
                        "TOKENIZERS_PARALLELISM": "false",
                    ]
                )
                scheduleUpdateChecks()
                return
            }
            appendLog("[CosmaManager] No local dev backend found at \(repoRoot)")

            // --- Strategy 2: cosma already on PATH ---
            setupStage = .checkingCosma
            await Task.yield()

            if let cosmaPath = findExecutable(name: "cosma") {
                await ensureOllamaAndModel()
                setupStage = .startingServer
                appendLog("[CosmaManager] Launching cosma directly: \(cosmaPath) serve")
                try await launchBackendProcess(
                    executable: cosmaPath,
                    arguments: ["serve"],
                    extraEnv: [:]
                )
                scheduleUpdateChecks()
                return
            }
            appendLog("[CosmaManager] cosma not found — starting auto-install")

            // --- Strategy 3: Auto-install uv + cosma, then launch ---
            let uvPath = try await ensureUV()
            try await ensureCosma(uvPath: uvPath)

            // Ensure Ollama + summarizer model are ready. Non-fatal if it fails:
            // the backend can still run for search, and the banner is suppressed.
            await ensureOllamaAndModel()

            setupStage = .startingServer
            guard let cosmaPath = findExecutable(name: "cosma") else {
                throw CosmaError.installFailed("cosma not found after installation")
            }
            appendLog("[CosmaManager] Launching freshly installed cosma: \(cosmaPath) serve")
            try await launchBackendProcess(
                executable: cosmaPath,
                arguments: ["serve"],
                extraEnv: [:]
            )
            scheduleUpdateChecks()
        } catch {
            setupStage = .failed(error.localizedDescription)
        }
    }

    /// Find the Python venv that has cosma_backend installed (local dev setup)
    private func findPythonWithBackend() -> String? {
        let home = realHomeDirectory()
        // Check known cosma repo locations
        let repoRoots = [
            "\(home)/Documents/code/SAIL/cosma",
            "\(home)/code/SAIL/cosma",
        ]
        for repo in repoRoots {
            let python = "\(repo)/.venv/bin/python"
            let backendInit = "\(repo)/packages/cosma-backend/src/cosma_backend/__init__.py"
            let pythonExists = FileManager.default.fileExists(atPath: python)
            let backendExists = FileManager.default.fileExists(atPath: backendInit)
            appendLog("[CosmaManager] Checking \(repo): python=\(pythonExists) backend=\(backendExists)")
            if pythonExists && backendExists {
                appendLog("[CosmaManager] Found local dev backend at \(repo)")
                return python  // Don't resolve symlinks — use venv path directly
            }
        }
        return nil
    }

    // MARK: - UV Installation

    private func ensureUV() async throws -> String {
        setupStage = .checkingUV

        if let path = findExecutable(name: "uv") {
            return path
        }

        setupStage = .installingUV
        try await runShellScript("curl -LsSf https://astral.sh/uv/install.sh | sh")

        // Re-check after install
        if let path = findExecutable(name: "uv") {
            return path
        }

        throw CosmaError.installFailed("uv not found after installation")
    }

    // MARK: - Cosma Installation

    private func ensureCosma(uvPath: String) async throws {
        setupStage = .checkingCosma

        if findExecutable(name: "cosma") != nil {
            installedVersion = await getInstalledVersion()
            return
        }

        setupStage = .installingCosma
        try await runProcess(executablePath: uvPath, arguments: ["tool", "install", "cosma"])

        guard findExecutable(name: "cosma") != nil else {
            throw CosmaError.installFailed("cosma not found after installation")
        }

        installedVersion = await getInstalledVersion()
    }

    // MARK: - Ollama + Summarizer Model

    /// Default summarizer model (matches backend default in ModelsSection).
    private let defaultOllamaModel = "qwen3-vl:2b-instruct"

    /// Ensures Ollama is installed and the summarizer model is pulled.
    /// Best-effort: logs and returns on failure rather than aborting backend launch.
    private func ensureOllamaAndModel() async {
        do {
            setupStage = .checkingOllama
            let ollamaPath: String
            if let existing = findExecutable(name: "ollama") {
                ollamaPath = existing
                appendLog("[CosmaManager] ollama found at \(existing)")
            } else {
                setupStage = .installingOllama
                appendLog("[CosmaManager] ollama not found — attempting install")
                try await installOllama()
                guard let installed = findExecutable(name: "ollama") else {
                    appendLog("[CosmaManager] ollama still not found after install — skipping model pull")
                    return
                }
                ollamaPath = installed
            }

            // Make sure `ollama serve` is running so `ollama pull` can reach the daemon.
            await startOllamaServeIfNeeded(ollamaPath: ollamaPath)

            // Pull the summarizer model if it's not already present.
            if try await ollamaHasModel(ollamaPath: ollamaPath, model: defaultOllamaModel) {
                appendLog("[CosmaManager] ollama model \(defaultOllamaModel) already present")
                return
            }

            setupStage = .pullingOllamaModel
            appendLog("[CosmaManager] pulling ollama model \(defaultOllamaModel)")
            _ = try await runProcess(executablePath: ollamaPath, arguments: ["pull", defaultOllamaModel])
            appendLog("[CosmaManager] ollama model ready")
        } catch {
            appendLog("[CosmaManager] ollama setup failed: \(error.localizedDescription) — continuing without summarizer")
        }
    }

    /// Install Ollama via Homebrew cask if available; otherwise throw.
    private func installOllama() async throws {
        if let brew = findExecutable(name: "brew") {
            _ = try await runProcess(executablePath: brew, arguments: ["install", "--cask", "ollama"])
            return
        }
        // No brew → install Homebrew first, then Ollama.
        appendLog("[CosmaManager] brew not found — installing Homebrew")
        try await runShellScript(
            "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        )
        guard let brew = findExecutable(name: "brew") else {
            throw CosmaError.installFailed("Homebrew not found after installation")
        }
        _ = try await runProcess(executablePath: brew, arguments: ["install", "--cask", "ollama"])
    }

    /// Probe the Ollama HTTP API; if not reachable, spawn `ollama serve` in the background.
    private func startOllamaServeIfNeeded(ollamaPath: String) async {
        if await isOllamaReachable() { return }
        appendLog("[CosmaManager] starting ollama serve")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ollamaPath)
        process.arguments = ["serve"]
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = realHomeDirectory()
        process.environment = env
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            appendLog("[CosmaManager] failed to start ollama serve: \(error.localizedDescription)")
            return
        }
        // Wait briefly for the daemon to come up.
        for _ in 0..<20 {
            if await isOllamaReachable() { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func isOllamaReachable() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Returns true if the given model tag is already present in the local Ollama store.
    private func ollamaHasModel(ollamaPath: String, model: String) async throws -> Bool {
        let output = try await runProcess(executablePath: ollamaPath, arguments: ["list"])
        // `ollama list` prints rows like "qwen3-vl:2b-instruct  abc123  1.5 GB  2 days ago"
        return output.split(separator: "\n").contains { line in
            line.split(separator: " ").first.map(String.init) == model
        }
    }

    // MARK: - Server Lifecycle

    /// Launch the backend as a direct child process (no shell wrapper).
    /// This is important because:
    ///   1. The pid we track IS the backend — killing it actually kills it,
    ///      rather than leaving an orphaned Python child behind a dead shell.
    ///   2. No sandbox profile sourcing issues.
    @ObservationIgnored private var lastLaunchEnv: [String: String] = [:]

    private func launchBackendProcess(
        executable: String,
        arguments: [String],
        extraEnv: [String: String]
    ) async throws {
        setupStage = .startingServer
        lastLaunchExe = executable
        lastLaunchArgs = arguments
        lastLaunchEnv = extraEnv

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        // Inherit the full process environment so PATH etc. are available,
        // override HOME to the real home directory, and merge in caller extras.
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = realHomeDirectory()
        for (k, v) in extraEnv {
            env[k] = v
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        stdoutPipe = stdout
        stderrPipe = stderr

        // Read output asynchronously
        readPipeAsync(stdout)
        readPipeAsync(stderr)

        // Crash detection with auto-restart
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self = self, self.ownsProcess else { return }
                let code = proc.terminationStatus
                if code != 0 && self.restartCount < self.maxRestarts {
                    self.restartCount += 1
                    self.appendLog("[CosmaManager] Process exited with code \(code), restarting (\(self.restartCount)/\(self.maxRestarts))…")
                    try? await Task.sleep(for: .seconds(1))
                    try? await self.relaunchLastProcess()
                } else if code != 0 {
                    self.setupStage = .failed("Server crashed \(self.maxRestarts) times")
                    self.startRecoveryPolling()
                } else {
                    self.setupStage = .stopped
                }
            }
        }

        try process.run()
        serverProcess = process
        ownsProcess = true

        // Poll for backend reachability. Cold-start can be slow: Python interpreter
        // + torch imports + Phase 2 model loading can take 15-30s. Poll for up to
        // 60s so we don't give up too early and leave the UI stuck.
        let maxAttempts = 120  // 120 x 500ms = 60 seconds
        for _ in 0..<maxAttempts {
            try await Task.sleep(for: .milliseconds(500))
            if await isBackendReachable() {
                setupStage = .running
                restartCount = 0
                return
            }
        }

        throw CosmaError.serverStartFailed("Server did not become reachable within 60 seconds")
    }

    private func relaunchLastProcess() async throws {
        guard let exe = lastLaunchExe, !lastLaunchArgs.isEmpty else {
            throw CosmaError.serverStartFailed("No previous launch configuration")
        }
        try await launchBackendProcess(executable: exe, arguments: lastLaunchArgs, extraEnv: lastLaunchEnv)
    }

    /// Stop the backend process. Synchronous with bounded waits so it
    /// reliably completes inside `applicationWillTerminate` before the app
    /// exits.
    ///
    /// Sequence:
    ///   1. SIGTERM → give Quart's `after_serving` hook up to 6 s to run
    ///      (needed so Ollama models are unloaded via keep_alive=0 and GPU is
    ///      released — otherwise Ollama's model stays pinned in GPU after
    ///      quit, making the machine laggy).
    ///   2. SIGKILL if still alive → wait up to 0.5 s.
    func stopServer() {
        guard ownsProcess, let process = serverProcess else { return }

        if process.isRunning {
            let pid = process.processIdentifier
            appendLog("[CosmaManager] Stopping backend (pid \(pid))…")

            // Step 1: SIGTERM (graceful) — gives backend time to unload Ollama
            process.terminate()

            // Busy-wait up to 6s for the backend's after_serving to finish.
            // This is the window where Ollama models get unloaded.
            let softDeadline = Date().addingTimeInterval(6.0)
            while process.isRunning && Date() < softDeadline {
                usleep(50_000)  // 50 ms
            }

            // Step 2: SIGKILL (force) if still alive
            if process.isRunning {
                appendLog("[CosmaManager] Backend did not exit in 6s, sending SIGKILL")
                kill(pid, SIGKILL)
                let hardDeadline = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < hardDeadline {
                    usleep(50_000)
                }
            }

            if process.isRunning {
                appendLog("[CosmaManager] Backend pid \(pid) still running after SIGKILL")
            } else {
                appendLog("[CosmaManager] Backend pid \(pid) terminated cleanly")
            }
        }

        serverProcess = nil
        setupStage = .stopped
    }

    func restartServer() async {
        guard ownsProcess else { return }
        stopServer()
        try? await Task.sleep(for: .seconds(1))
        do {
            try await relaunchLastProcess()
        } catch {
            setupStage = .failed(error.localizedDescription)
        }
    }

    // MARK: - Update Checks

    func checkForUpdates() async {
        updateStatus = .checking

        do {
            let latest = try await fetchLatestPyPIVersion()
            latestVersion = latest
            let installed = installedVersion ?? "unknown"

            if installed != "unknown" && installed != latest {
                if dismissedVersion == latest {
                    updateStatus = .upToDate
                } else {
                    updateStatus = .available(installed: installed, latest: latest)
                }
            } else {
                updateStatus = .upToDate
            }
        } catch {
            updateStatus = .failed(error.localizedDescription)
        }
    }

    func performUpdate() async {
        guard let uvPath = findExecutable(name: "uv") else {
            updateStatus = .failed("uv not found")
            return
        }

        updateStatus = .updating

        let wasRunning = ownsProcess && (serverProcess?.isRunning == true)
        if wasRunning {
            stopServer()
            try? await Task.sleep(for: .seconds(1))
        }

        do {
            try await runProcess(executablePath: uvPath, arguments: ["tool", "upgrade", "cosma", "--no-cache"])
            installedVersion = await getInstalledVersion()
            updateStatus = .upToDate
            dismissedVersion = nil

            if wasRunning {
                try await relaunchLastProcess()
            }
        } catch {
            updateStatus = .failed(error.localizedDescription)
            if wasRunning {
                try? await relaunchLastProcess()
            }
        }
    }

    func dismissUpdate() {
        if case .available(_, let latest) = updateStatus {
            dismissedVersion = latest
        }
        updateStatus = .upToDate
    }

    private func scheduleUpdateChecks() {
        updateTimer?.invalidate()
        // Check immediately, then every 6 hours
        Task { await checkForUpdates() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates()
            }
        }
    }

    // MARK: - Recovery Polling

    /// Polls the backend in the background after all restart attempts are
    /// exhausted. If the backend was started externally (e.g. from the
    /// terminal) or recovers on its own, we pick it up and transition
    /// straight to `.running` — no need to close/reopen the window.
    private func startRecoveryPolling() {
        recoveryPollTask?.cancel()
        recoveryPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                if let self, await self.isBackendReachable() {
                    self.setupStage = .running
                    self.restartCount = 0
                    self.ownsProcess = false  // we didn't start it
                    self.appendLog("[CosmaManager] Backend recovered externally — attached")
                    self.scheduleUpdateChecks()
                    return
                }
            }
        }
    }

    private func stopRecoveryPolling() {
        recoveryPollTask?.cancel()
        recoveryPollTask = nil
    }

    // MARK: - Teardown

    func teardown() {
        stopRecoveryPolling()
        updateTimer?.invalidate()
        updateTimer = nil
        if ownsProcess {
            stopServer()
        }
    }

    // MARK: - Helpers

    private func findExecutable(name: String) -> String? {
        let home = realHomeDirectory()
        let commonPaths = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.cargo/bin/\(name)",
        ]

        for path in commonPaths {
            // Resolve symlinks before checking (isExecutableFile may not follow them)
            let resolved = (path as NSString).resolvingSymlinksInPath
            if FileManager.default.isExecutableFile(atPath: resolved) {
                appendLog("[CosmaManager] Found \(name) at \(path)")
                return resolved
            }
            // Also check original path in case resolution fails
            if FileManager.default.isExecutableFile(atPath: path) {
                appendLog("[CosmaManager] Found \(name) at \(path) (unresolved)")
                return path
            }
        }

        // Fallback: use /bin/sh -l -c which (login shell to get full PATH)
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        whichProcess.arguments = ["-l", "-c", "which \(name)"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                    appendLog("[CosmaManager] Found \(name) via shell at \(path)")
                    return path
                }
            }
        } catch {}

        appendLog("[CosmaManager] \(name) not found in any known location")
        return nil
    }

    @discardableResult
    private func runShellScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]

            var env = ProcessInfo.processInfo.environment
            let home = realHomeDirectory()
            let extraPaths = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin"
            env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            process.environment = env

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let errOutput = String(data: errData, encoding: .utf8) ?? ""

                if proc.terminationStatus != 0 {
                    continuation.resume(throwing: CosmaError.shellFailed(
                        "Exit code \(proc.terminationStatus): \(errOutput.isEmpty ? output : errOutput)"
                    ))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    @discardableResult
    private func runProcess(executablePath: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            var env = ProcessInfo.processInfo.environment
            let home = realHomeDirectory()
            let extraPaths = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin"
            env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            process.environment = env

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let errOutput = String(data: errData, encoding: .utf8) ?? ""

                if proc.terminationStatus != 0 {
                    continuation.resume(throwing: CosmaError.shellFailed(
                        "\(executablePath) failed (\(proc.terminationStatus)): \(errOutput.isEmpty ? output : errOutput)"
                    ))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func isBackendReachable() async -> Bool {
        do {
            let _ = try await APIClient.shared.fetchStatus()
            return true
        } catch {
            return false
        }
    }

    private func getInstalledVersion() async -> String? {
        guard let cosmaPath = findExecutable(name: "cosma") else { return nil }
        do {
            let output = try await runProcess(executablePath: cosmaPath, arguments: ["--version"])
            // Expect something like "cosma 0.5.0" — extract version
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lastWord = trimmed.split(separator: " ").last {
                return String(lastWord)
            }
            return trimmed
        } catch {
            return nil
        }
    }

    private func fetchLatestPyPIVersion() async throws -> String {
        let url = URL(string: "https://pypi.org/pypi/cosma/json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let info = json?["info"] as? [String: Any],
              let version = info["version"] as? String else {
            throw CosmaError.updateCheckFailed("Invalid PyPI response")
        }
        return version
    }

    private func readPipeAsync(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendLog(str)
            }
        }
    }

    /// Get the real home directory, bypassing sandbox container redirection.
    /// Uses getpwuid which always returns the actual /Users/username path.
    private func realHomeDirectory() -> String {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return String(cString: home)
        }
        return NSHomeDirectory() // fallback
    }

    private func appendLog(_ text: String) {
        print(text)  // Also output to Xcode console
        serverLog += text
        // Cap log size to prevent unbounded growth
        if serverLog.count > 50_000 {
            serverLog = String(serverLog.suffix(25_000))
        }
    }
}

// MARK: - Errors

enum CosmaError: LocalizedError {
    case installFailed(String)
    case shellFailed(String)
    case serverStartFailed(String)
    case updateCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .installFailed(let msg): return msg
        case .shellFailed(let msg): return msg
        case .serverStartFailed(let msg): return msg
        case .updateCheckFailed(let msg): return msg
        }
    }
}
