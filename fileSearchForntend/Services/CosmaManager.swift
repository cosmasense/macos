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
        guard isManaged else { return }

        // First check if a backend is already reachable
        setupStage = .startingServer
        if await isBackendReachable() {
            ownsProcess = false
            setupStage = .running
            installedVersion = await getInstalledVersion()
            scheduleUpdateChecks()
            return
        }

        // Full pipeline: install uv → install cosma → launch server
        do {
            let uvPath = try await ensureUV()
            try await ensureCosma(uvPath: uvPath)
            try await launchCosmaServe()
            scheduleUpdateChecks()
        } catch {
            setupStage = .failed(error.localizedDescription)
        }
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

    private func launchCosmaServe() async throws {
        setupStage = .startingServer

        guard let cosmaPath = findExecutable(name: "cosma") else {
            throw CosmaError.installFailed("cosma executable not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cosmaPath)
        process.arguments = ["serve"]

        // Augment PATH for child process
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
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
                    try? await self.launchCosmaServe()
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
            try await launchCosmaServe()
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
                try await launchCosmaServe()
            }
        } catch {
            updateStatus = .failed(error.localizedDescription)
            if wasRunning {
                try? await launchCosmaServe()
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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: use which
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [name]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}

        return nil
    }

    @discardableResult
    private func runShellScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]

            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
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
            let home = FileManager.default.homeDirectoryForCurrentUser.path
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

    private func appendLog(_ text: String) {
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
