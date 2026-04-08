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

    private static let managedKey = "cosmaManagerEnabled"
    private static let managedSetKey = "cosmaManagerEnabledHasBeenSet"

    var isManaged: Bool {
        get {
            // Default to true if the user has never explicitly set this
            if !UserDefaults.standard.bool(forKey: Self.managedSetKey) {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.managedKey)
        }
        set {
            UserDefaults.standard.set(true, forKey: Self.managedSetKey)
            UserDefaults.standard.set(newValue, forKey: Self.managedKey)
        }
    }

    var isRunning: Bool { setupStage == .running }

    var stageDescription: String {
        switch setupStage {
        case .idle: return "Idle"
        case .checkingUV: return "Checking for uv…"
        case .installingUV: return "Installing uv…"
        case .checkingCosma: return "Checking for cosma…"
        case .installingCosma: return "Installing cosma…"
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
    @ObservationIgnored private var dismissedVersion: String? {
        get { UserDefaults.standard.string(forKey: "cosmaDismissedUpdateVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "cosmaDismissedUpdateVersion") }
    }

    // MARK: - Main Entry Point

    func startManagedBackend() async {
        print("[CosmaManager] startManagedBackend called, isManaged=\(isManaged)")
        guard isManaged else { print("[CosmaManager] Not managed, skipping"); return }

        // First check if a backend is already reachable
        setupStage = .startingServer
        if await isBackendReachable() {
            ownsProcess = false
            setupStage = .running
            installedVersion = await getInstalledVersion()
            scheduleUpdateChecks()
            return
        }

        // Build a shell command that activates the venv and runs the backend.
        // Using /bin/sh -l -c gives us a login shell with full PATH resolution,
        // bypassing all sandbox container path issues.
        do {
            let home = realHomeDirectory()

            // Strategy 1: Local dev repo with venv
            let repoRoot = "\(home)/Documents/code/SAIL/cosma"
            let venvActivate = "\(repoRoot)/.venv/bin/activate"
            let backendInit = "\(repoRoot)/packages/cosma-backend/src/cosma_backend/__init__.py"

            if FileManager.default.fileExists(atPath: venvActivate) &&
               FileManager.default.fileExists(atPath: backendInit) {
                // Run the venv python directly — no source/activate needed.
                // The venv python binary automatically uses venv site-packages.
                let venvPython = "\(repoRoot)/.venv/bin/python"
                let cmd = "PYTHONPATH='\(repoRoot)/packages/cosma-backend/src' TOKENIZERS_PARALLELISM=false '\(venvPython)' -m cosma_backend"
                appendLog("[CosmaManager] Launching via shell: \(cmd)")
                try await launchShellCommand(cmd)
                scheduleUpdateChecks()
                return
            }
            appendLog("[CosmaManager] No local dev backend found at \(repoRoot)")

            // Strategy 2: cosma serve (installed via uv tool)
            let cosmaCmd = "cosma serve"
            appendLog("[CosmaManager] Trying: \(cosmaCmd)")
            try await launchShellCommand(cosmaCmd)
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

    // MARK: - Server Lifecycle

    /// Launch the backend via a login shell command.
    /// Using /bin/sh -l -c ensures full PATH, venv activation, and symlink
    /// resolution — completely bypassing sandbox container path issues.
    private func launchShellCommand(_ command: String) async throws {
        setupStage = .startingServer
        lastLaunchExe = "/bin/sh"
        lastLaunchArgs = ["-l", "-c", command]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]  // No -l: avoid login profile sourcing (sandbox blocks it)

        // Inherit the full process environment so PATH etc. are available
        // but override HOME to the real home directory
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = realHomeDirectory()
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
                } else {
                    self.setupStage = .stopped
                }
            }
        }

        try process.run()
        serverProcess = process
        ownsProcess = true

        // Wait a moment then verify the server is reachable
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(500))
            if await isBackendReachable() {
                setupStage = .running
                restartCount = 0
                return
            }
        }

        throw CosmaError.serverStartFailed("Server did not become reachable within 10 seconds")
    }

    private func relaunchLastProcess() async throws {
        guard lastLaunchArgs.count >= 3, lastLaunchArgs[0] == "-l", lastLaunchArgs[1] == "-c" else {
            throw CosmaError.serverStartFailed("No previous launch configuration")
        }
        try await launchShellCommand(lastLaunchArgs[2])
    }

    func stopServer() {
        guard ownsProcess, let process = serverProcess, process.isRunning else { return }

        process.interrupt() // SIGINT

        // Fall back to SIGTERM after 3s
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak process] in
            if let p = process, p.isRunning {
                p.terminate()
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

    // MARK: - Teardown

    func teardown() {
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
