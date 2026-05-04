//
//  CosmaManager.swift
//  fileSearchForntend
//
//  Manages the cosma backend lifecycle: auto-install, run, update.
//

import AppKit
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
        /// A newer version was found and is being downloaded in the background.
        case downloading(running: String, target: String)
        /// A newer version has been installed on disk; the running backend is
        /// still on the old version. The user must relaunch the app to pick
        /// up the new bits.
        case downloadedPendingRestart(running: String, downloaded: String)
        case upToDate
        case failed(String)
    }

    // MARK: - Published State

    var setupStage: SetupStage = .idle
    var updateStatus: UpdateStatus = .idle
    var installedVersion: String?
    var latestVersion: String?
    /// Wall-clock timestamp of the most recent completed update check
    /// (success or failure). Drives the "checked just now / 2m ago"
    /// hint shown next to the Settings → Check for Updates button so
    /// the user can confirm the click actually did something.
    var lastUpdateCheckAt: Date?
    /// Version the *currently running* backend was launched with. Snapshotted
    /// at the moment the server transitions to `.running`, so even if
    /// `installedVersion` is later updated by a background `uv tool upgrade`,
    /// we still know what's actually executing in-process. Differs from
    /// `installedVersion` only between an upgrade landing on disk and the
    /// user relaunching the app.
    var runningVersion: String?
    var serverLog: String = ""

    // Bootstrap (llama.cpp + whisper.cpp model download) state.
    // Populated by CosmaManager+Bootstrap once the backend is reachable. Split
    // from `setupStage` because bootstrap runs *after* the server is up —
    // the server starts serving the API immediately, then streams install
    // progress back so the wizard can show per-component bars without
    // blocking server startup behind ~2 GB of downloads.
    var bootstrapComponents: [BootstrapComponent] = []
    var bootstrapRunning: Bool = false
    var bootstrapReady: Bool = false
    var bootstrapError: String?

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
    @ObservationIgnored var shutdownCompleteSeen: Bool = false
    @ObservationIgnored private var stderrPipe: Pipe?
    @ObservationIgnored private var updateTimer: Timer?
    @ObservationIgnored private var restartCount = 0
    @ObservationIgnored private let maxRestarts = 3
    @ObservationIgnored private var recoveryPollTask: Task<Void, Never>?
    /// True while `stopServer` (or any caller routed through it, like the
    /// catch-up upgrade restart) is intentionally killing the backend.
    /// The terminationHandler installed in `launchBackendProcess` checks
    /// this and skips its auto-restart branch when it's set — otherwise
    /// SIGTERM (exit code 15) looks like a crash to the reaper, which
    /// then races our own relaunch and fights for port 60534. Cleared
    /// once the relaunch is in flight (or if no relaunch is coming).
    @ObservationIgnored private var intentionalStop: Bool = false

    /// Observable: true while we're performing an in-process backend
    /// restart that the frontend should NOT react to (e.g. the catch-up
    /// upgrade restart). The setupStage observer in fileSearchForntendApp
    /// uses this to keep `isBackendConnected = true` across the brief
    /// .running → .stopped → .running cycle, so the user doesn't see
    /// ContentView tear down to BackendConnectionView for a few seconds
    /// while we relaunch with the new binary. Only the BACKEND restarts
    /// — the frontend stays put.
    var isInternalRestartInFlight: Bool = false
    /// Single-instance guard. Set true on entry to `startManagedBackend`,
    /// cleared on exit. Prevents two concurrent calls (e.g. an Xcode
    /// hot-reload firing while a previous launch attempt is still
    /// running) from racing and spawning two backends. Without this,
    /// both calls could pass the warm-attach probe (port not yet
    /// bound), both could call the reaper (no PIDs to kill), and both
    /// could `launchBackendProcess` — the second EADDRINUSE silently
    /// crashes the second python child while the first runs fine.
    @ObservationIgnored private var startupInFlight: Bool = false
    @ObservationIgnored private var dismissedVersion: String? {
        get { UserDefaults.standard.string(forKey: "cosmaDismissedUpdateVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "cosmaDismissedUpdateVersion") }
    }

    // MARK: - Main Entry Point

    func startManagedBackend() async {
        print("[CosmaManager] startManagedBackend called")
        // Re-entrance guard: if a previous startup is still running,
        // bail out. The original call will reach `setupStage = .running`
        // and the UI's bootstrap-onChange will pick it up. Note that
        // CosmaManager is @MainActor-isolated so this read/write is
        // race-free without a lock.
        if startupInFlight {
            print("[CosmaManager] startManagedBackend already in flight — skipping duplicate call")
            return
        }
        startupInFlight = true
        defer { startupInFlight = false }
        stopRecoveryPolling()

        // Step 1: Quick attach if backend is already running (no setup needed).
        //
        // Warm-attach fast path: we intentionally skip ensureOllamaAndModel()
        // here. If the backend is reachable, it has already run its own
        // probe against Ollama at startup and will reconcile the summarizer
        // state on first use. Having the frontend *also* shell out to
        // `ollama list` + ping :11434 adds ~500ms to every launch for zero
        // new information. The model-availability banner (if something is
        // actually missing) is driven by AppModel.checkModelAvailability(),
        // which runs after the UI shows — so the launch feels instant.
        if await isBackendReachable() {
            ownsProcess = false
            setupStage = .running
            installedVersion = await getInstalledVersion()
            runningVersion = installedVersion
            scheduleUpdateChecks()
            return
        }

        // Step 1b: A previous run may have left a stale backend process
        // bound to :60534 (e.g., the app was force-quit, a Python crash
        // left a zombie holding the port, or a previous launch ran a
        // different binary). The warm-attach probe above only succeeds
        // when /api/status/ responds — a process that bound the port
        // but is wedged on something synchronous would fail that probe
        // AND fail our subsequent bind, leaving the user stuck on the
        // setup wizard with no signal as to why. Reap stale owners
        // before we try to launch.
        await reapStaleBackendProcesses()

        // Step 2: Check prerequisites and launch the server.
        // Three strategies, tried in order:
        //   1. Local dev venv (only when COSMA_DEV=1 is set in the environment)
        //   2. `cosma` already installed via uv tool
        //   3. Auto-install: ensure uv → ensure cosma → launch
        do {
            let home = realHomeDirectory()

            // --- Strategy 1: Local dev repo with venv (opt-in via COSMA_DEV=1) ---
            // Production builds must never accidentally fall into this path just
            // because a path happens to exist on disk. Gate it explicitly on an
            // env var. For Xcode development, set COSMA_DEV=1 in the scheme's
            // "Run > Arguments > Environment Variables". COSMA_DEV_REPO can
            // override the default repo path.
            setupStage = .checkingUV
            await Task.yield()

            let env = ProcessInfo.processInfo.environment
            if env["COSMA_DEV"] == "1" {
                let repoRoot = env["COSMA_DEV_REPO"] ?? "\(home)/Documents/code/SAIL/cosma"
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
                    appendLog("[CosmaManager] COSMA_DEV=1 — launching local source: \(venvPython) -m cosma_backend (repo: \(repoRoot))")
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
                appendLog("[CosmaManager] COSMA_DEV=1 but dev repo not found at \(repoRoot) — falling back to installed cosma")
            }

            // --- Strategy 2: cosma already on PATH ---
            setupStage = .checkingCosma
            await Task.yield()

            if let cosmaPath = await findExecutable(name: "cosma") {
                // Launch the *currently installed* cosma immediately — no
                // PyPI check, no upgrade — so the user sees a working
                // backend in <1s instead of waiting on a possibly-slow
                // network round trip. The upgrade still happens, just
                // off the launch hot path: scheduleUpdateChecks() at the
                // end fires a background `checkForUpdates`, and
                // `upgradeCosmaInBackground()` runs `uv tool upgrade
                // cosma` if a newer version exists. The new bits land on
                // the user's next quit + relaunch (which kills our
                // backend; the reaper guarantees only one is running).
                await ensureOllamaAndModel()
                setupStage = .startingServer
                appendLog("[CosmaManager] Launching cosma directly: \(cosmaPath) serve")
                try await launchBackendProcess(
                    executable: cosmaPath,
                    arguments: ["serve"],
                    extraEnv: [:]
                )
                scheduleUpdateChecks()
                Task { await self.upgradeCosmaInBackground() }
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
            guard let cosmaPath = await findExecutable(name: "cosma") else {
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

        if let path = await findExecutable(name: "uv") {
            return path
        }

        setupStage = .installingUV
        try await runShellScript("curl -LsSf https://astral.sh/uv/install.sh | sh")

        // Re-check after install
        if let path = await findExecutable(name: "uv") {
            return path
        }

        throw CosmaError.installFailed("uv not found after installation")
    }

    // MARK: - Cosma Installation

    /// URL of the cosmasense Metal fork wheel of llama-cpp-python. We
    /// install this alongside cosma via `--with` because upstream
    /// abetlen/llama-cpp-python on PyPI does not yet ship
    /// `Qwen3VLChatHandler` (open feature request — see
    /// github.com/abetlen/llama-cpp-python/issues/2080). Without the
    /// fork wheel in cosma's tool venv, the backend's vision summarizer
    /// has no handler class for Qwen3-VL and image summaries fall back
    /// to the parser-metadata placeholder (the "JPEG image file: WxH
    /// pixels…" string).
    ///
    /// `[tool.uv.sources]` in cosma-backend's pyproject.toml pins the
    /// same wheel for local dev, but that section is uv-only metadata
    /// and is stripped when the package is published to PyPI — so end
    /// users on `uv tool install cosma` need the URL passed in
    /// explicitly via `--with`.
    private static let cosmaSenseForkWheelURL = "https://github.com/cosmasense/llama-cpp-python/releases/download/v0.3.32-metal/llama_cpp_python-0.3.32-cp313-cp313-macosx_11_0_arm64.whl"

    /// Pin the tool venv to Python 3.13 so the cp313 wheel above
    /// matches. uv defaults to the latest installed Python anyway, but
    /// being explicit avoids a stock-PyPI fallback if the user happens
    /// to have only 3.12 around.
    private static let cosmaToolPythonVersion = "3.13"

    private func ensureCosma(uvPath: String) async throws {
        setupStage = .checkingCosma

        if await findExecutable(name: "cosma") != nil {
            installedVersion = await getInstalledVersion()
            return
        }

        setupStage = .installingCosma
        try await runProcess(
            executablePath: uvPath,
            arguments: [
                "tool", "install", "cosma",
                "--python", Self.cosmaToolPythonVersion,
                "--with", Self.cosmaSenseForkWheelURL,
            ]
        )

        guard await findExecutable(name: "cosma") != nil else {
            throw CosmaError.installFailed("cosma not found after installation")
        }

        installedVersion = await getInstalledVersion()
    }

    // MARK: - Ollama + Summarizer Model

    /// Default summarizer model (matches backend default in ModelsSection).
    private let defaultOllamaModel = "qwen3-vl:2b-instruct"

    /// Ensures Ollama is installed and the summarizer model is pulled.
    /// Best-effort: logs and returns on failure rather than aborting backend launch.
    ///
    /// Provider-gated: does nothing unless the user actually picked Ollama
    /// as their summarizer backend. Previously this ran on every launch
    /// regardless of provider, costing ~1–2 s shelling out to `ollama list`
    /// for users who will never use Ollama (llama.cpp or online).
    private func ensureOllamaAndModel() async {
        let provider = UserDefaults.standard.string(forKey: "aiProvider") ?? "llamacpp"
        guard provider == "ollama" else {
            appendLog("[CosmaManager] skipping Ollama check (provider=\(provider))")
            return
        }
        do {
            setupStage = .checkingOllama
            let ollamaPath: String
            if let existing = await findExecutable(name: "ollama") {
                ollamaPath = existing
                appendLog("[CosmaManager] ollama found at \(existing)")
            } else {
                setupStage = .installingOllama
                appendLog("[CosmaManager] ollama not found — attempting install")
                try await installOllama()
                guard let installed = await findExecutable(name: "ollama") else {
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
        if let brew = await findExecutable(name: "brew") {
            _ = try await runProcess(executablePath: brew, arguments: ["install", "--cask", "ollama"])
            return
        }
        // No brew → install Homebrew first, then Ollama.
        appendLog("[CosmaManager] brew not found — installing Homebrew")
        try await runShellScript(
            "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        )
        guard let brew = await findExecutable(name: "brew") else {
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

        // Crash detection with auto-restart. Skipped entirely when the
        // exit was an intentional stop (stopServer set the flag) — the
        // caller is already managing the lifecycle, and racing them
        // here spawns a duplicate backend that fights for port 60534.
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self = self, self.ownsProcess else { return }
                if self.intentionalStop {
                    self.appendLog("[CosmaManager] Process exited (intentional stop) — not restarting from terminationHandler")
                    return
                }
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
                // Reset the intentional-stop guard now that the next
                // generation backend is live. Future crashes from THIS
                // process should be auto-restarted by the reaper.
                intentionalStop = false
                // Snapshot the on-disk version we just spawned. Used later to
                // detect when a background `uv tool upgrade` has installed a
                // newer version that the running process hasn't picked up.
                // We re-query installedVersion here (not just on first launch)
                // because a catch-up restart after an upgrade needs the
                // fresh on-disk version, not the stale one from the
                // previous launch's snapshot.
                installedVersion = await getInstalledVersion()
                runningVersion = installedVersion
                // Recompute updateStatus now that running == installed
                // again. Without this, .downloadedPendingRestart from
                // the upgrade we just applied lingers, and the friendly
                // "Update downloaded — restarting…" banner never goes
                // away even though the restart already happened.
                refreshUpdateStatus()
                // Vision self-heal: kick off in the background so we
                // don't block the .running transition. If the user is
                // on stock-PyPI llama-cpp-python (no Qwen3VLChatHandler),
                // this will reinstall cosma with --with <fork-wheel>
                // and restart the backend. Idempotent + per-version
                // marker so it only ever runs once per release.
                Task { await self.runVisionSelfHealIfNeeded() }
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
    ///   1. SIGTERM → give Quart's `after_serving` hook up to 5 s to run
    ///      (Ollama models are unloaded via keep_alive=0, SSE streams are
    ///      torn down, joblib workers are killed). 5 s tracks uvicorn's
    ///      `timeout_graceful_shutdown` plus a small safety buffer.
    ///   2. SIGKILL if still alive → wait up to 0.5 s.
    ///
    /// Wall-clock optimization: we drive the wait off `RunLoop.current.run`
    /// instead of `usleep`. Critical because `readPipeAsync` parses the
    /// backend's "Shutdown complete" log line on a background queue, then
    /// dispatches `Task { @MainActor in shutdownCompleteSeen = true }` to
    /// set the short-circuit flag. With `usleep`, the MainActor is busy-
    /// spinning and that dispatched task can never run — so the loop
    /// always burns the full timeout regardless of how fast the backend
    /// actually exits. `RunLoop.run(until:)` ticks the main run loop each
    /// iteration, which lets the pipe-handler's MainActor hop fire and
    /// shortcuts us out of the wait the moment the backend says it's done.
    func stopServer() {
        guard ownsProcess, let process = serverProcess else { return }

        // Mark this as an intentional kill so the terminationHandler
        // installed in launchBackendProcess doesn't see the SIGTERM
        // (exit code 15), think the process crashed, and race our own
        // relaunch (or the caller's). Cleared by the next launch
        // (launchBackendProcess) or, in dead-end paths where no
        // relaunch is coming, by the calling site.
        intentionalStop = true

        if process.isRunning {
            let pid = process.processIdentifier
            appendLog("[CosmaManager] Stopping backend (pid \(pid))…")

            // Step 1: SIGTERM (graceful) — gives backend time to unload
            // Ollama and tear down SSE streams + loky workers.
            shutdownCompleteSeen = false
            process.terminate()

            // Window is 5 s (matches uvicorn's reduced 3 s graceful-
            // shutdown budget + ~2 s safety for after_serving teardown).
            // We short-circuit as soon as we see "Shutdown complete" on
            // stdout — anything after that is wasted wall-clock time.
            let softDeadline = Date().addingTimeInterval(5.0)
            let stopStart = Date()
            while process.isRunning && Date() < softDeadline {
                if shutdownCompleteSeen {
                    // Give the process one more tick to actually exit after
                    // it printed the line, then stop waiting.
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                    break
                }
                // 50 ms tick. RunLoop.run drains pending dispatched blocks
                // (including the pipe handler's Task that sets
                // shutdownCompleteSeen), so the short-circuit actually fires.
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            }

            let elapsed = Date().timeIntervalSince(stopStart)

            // Step 2: SIGKILL (force) if still alive
            if process.isRunning {
                appendLog("[CosmaManager] Backend did not exit in 5s, sending SIGKILL")
                kill(pid, SIGKILL)
                let hardDeadline = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < hardDeadline {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                }
            }

            if process.isRunning {
                appendLog("[CosmaManager] Backend pid \(pid) still running after SIGKILL")
            } else {
                appendLog(String(format: "[CosmaManager] Backend pid %d terminated cleanly in %.2fs", pid, elapsed))
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

    /// Single in-flight upgrade guard. Both the launch-time background
    /// upgrade and the periodic 6h check funnel through `upgradeCosmaIfNeeded`;
    /// without this guard the two paths could race and run two `uv tool
    /// upgrade` invocations concurrently against the same tool dir.
    @ObservationIgnored private var upgradeInFlight: Bool = false

    /// Check PyPI for a newer cosma release and, if found, download/install
    /// it via `uv tool upgrade`. The currently-running backend keeps using
    /// the previous version until the user relaunches the app — at that
    /// point `runningVersion` < `installedVersion` and we surface a
    /// "Restart to apply update" banner.
    ///
    /// Non-fatal: PyPI failures, network issues, or upgrade errors only
    /// log and leave existing state intact.
    private func upgradeCosmaIfNeeded() async {
        guard !upgradeInFlight else { return }
        upgradeInFlight = true
        defer { upgradeInFlight = false }

        guard let uvPath = await findExecutable(name: "uv") else { return }
        let installed = await getInstalledVersion()
        installedVersion = installed

        let latest: String?
        do {
            latest = try await withTimeout(seconds: 3) { try await self.fetchLatestPyPIVersion() }
        } catch {
            appendLog("[CosmaManager] PyPI version check failed — skipping auto-upgrade: \(error.localizedDescription)")
            return
        }
        guard let latest else { return }
        latestVersion = latest

        if let installed, installed == latest {
            appendLog("[CosmaManager] cosma is up to date (v\(installed))")
            refreshUpdateStatus()
            return
        }

        // The user previously dismissed this exact version — respect that
        // and don't redownload until something newer ships.
        if dismissedVersion == latest {
            appendLog("[CosmaManager] cosma v\(latest) available but dismissed by user")
            return
        }

        // Compatibility clamp. The backend's `api_version` is bumped only
        // on breaking wire-format changes (see cosma_backend/__init__.py),
        // and this Swift build is pinned against a specific
        // `kRequiredBackendApiVersion`. PyPI doesn't expose api_version
        // directly, so we use a conservative proxy: only auto-upgrade
        // within the same MAJOR.MINOR series as what's running. A
        // major-or-minor bump must come with a coordinated frontend
        // release; we refuse to auto-pull forward past it. Without this,
        // an `uv tool upgrade --no-cache` could land the backend on an
        // api_version this app can't decode and the user sees the dreaded
        // "API issue" mid-session. The user explicitly asked for this gate
        // when the auto-upgrade caused issues with new ProcessingStatus
        // enum values.
        let baseline = installed ?? runningVersion
        if !BackendCompatibility.shouldAutoUpgrade(
            runningVersion: baseline, latestVersion: latest,
        ) {
            appendLog("""
            [CosmaManager] Auto-upgrade clamped: cosma v\(latest) is \
            outside the compatible range for this app build (running \
            \(baseline ?? "unknown")). Bundle a matching frontend release \
            to upgrade past this point.
            """)
            return
        }

        let runningAtUpgradeStart = runningVersion ?? installed
        appendLog("[CosmaManager] Upgrading cosma: \(installed ?? "?") → \(latest)")
        if let running = runningAtUpgradeStart {
            updateStatus = .downloading(running: running, target: latest)
        }
        do {
            // Capture uv's own output so a silent no-op ("nothing
            // changed because resolver picked the same version") leaves
            // a paper trail in the log instead of looking like a
            // success. The upgradeCosmaIfNeeded tail used to discard
            // this output, which made it impossible to debug "PyPI has
            // 1.0.2, my install stays on 1.0.1" reports.
            let uvOutput = try await withTimeout(seconds: 120) {
                try await self.runProcess(
                    executablePath: uvPath,
                    arguments: ["tool", "upgrade", "cosma", "--no-cache"]
                )
            }
            // Trim — uv's output ends with a stray newline which makes
            // the log noisier than it needs to be.
            let trimmedOutput = uvOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedOutput.isEmpty {
                appendLog("[CosmaManager] uv tool upgrade output: \(trimmedOutput)")
            } else {
                appendLog("[CosmaManager] uv tool upgrade returned with no output (resolver was a no-op?)")
            }
            installedVersion = await getInstalledVersion()
            appendLog("[CosmaManager] Upgrade complete (now v\(installedVersion ?? "?"))")
            // Sanity: the resolver no-op case. uv exited 0 + said
            // nothing, and the on-disk version didn't move. The user's
            // "PyPI shows 1.0.2 but I'm on 1.0.1" report — there's
            // nothing more we can do automatically; flag it so the
            // user knows to investigate manually.
            if let target = latestVersion,
               let landed = installedVersion,
               BackendCompatibility.compareSemver(landed, target) < 0 {
                appendLog("""
                [CosmaManager] WARNING: uv tool upgrade exited 0 but \
                installed version stayed at v\(landed) while PyPI's \
                latest is v\(target). This is a uv resolver edge case \
                (cached index, pinned constraint, marker mismatch). \
                Try: `uv tool upgrade cosma --no-cache --reinstall` \
                in a terminal — the --reinstall flag forces uv to \
                rebuild the env from scratch instead of asking the \
                resolver politely.
                """)
            }
            refreshUpdateStatus()

            // Catch-up restart: if the running backend is older than this
            // frontend's paired baseline, the version handshake will have
            // already failed (404 if older than the version that added
            // /api/status/version) and the user is staring at a "Backend
            // incompatible" banner. Don't make them quit + reopen — kill
            // the old backend and relaunch from the new install in the
            // same session. Only triggers when the upgrade actually
            // crossed the baseline, so we don't churn-restart for normal
            // patch updates (those keep the "Restart to apply" semantics).
            if let installedNow = installedVersion,
               let runningNow = runningVersion,
               BackendCompatibility.compareSemver(runningNow, BackendCompatibility.kPairedBackendVersion) < 0,
               BackendCompatibility.compareSemver(installedNow, BackendCompatibility.kPairedBackendVersion) >= 0,
               BackendCompatibility.compareSemver(installedNow, runningNow) > 0,
               ownsProcess {
                appendLog("""
                [CosmaManager] Catch-up restart: running v\(runningNow) is below \
                paired baseline v\(BackendCompatibility.kPairedBackendVersion); \
                relaunching with v\(installedNow) so the version handshake stops failing.
                """)
                // Tell the frontend to ignore the upcoming
                // .running → .stopped → .running cycle. Only the
                // backend is restarting; users keep seeing ContentView
                // (which already shows the friendly "Update downloaded
                // — restarting backend automatically…" banner). Without
                // this, the observer in fileSearchForntendApp tears
                // ContentView down for ~5s and shows
                // BackendConnectionView, which feels like the whole app
                // crashed.
                isInternalRestartInFlight = true
                await restartServer()
                isInternalRestartInFlight = false
            }
        } catch {
            appendLog("[CosmaManager] Auto-upgrade failed — continuing with old version: \(error.localizedDescription)")
            updateStatus = .failed(error.localizedDescription)
        }
    }

    /// Recompute `updateStatus` from the latest `runningVersion` /
    /// `installedVersion` pair. Idempotent — call after any version-related
    /// change.
    private func refreshUpdateStatus() {
        let previousStatus = updateStatus
        guard let installed = installedVersion else {
            updateStatus = .idle
            return
        }
        guard let running = runningVersion else {
            // No backend running yet (early launch). Nothing to compare —
            // when the backend comes up it will use `installed` directly.
            updateStatus = .upToDate
            return
        }
        if running == installed {
            updateStatus = .upToDate
            return
        }
        if dismissedVersion == installed {
            updateStatus = .upToDate
            return
        }
        updateStatus = .downloadedPendingRestart(running: running, downloaded: installed)
        // First entry into the pending-restart state — surface a system
        // notification so the user finds out about the restart prompt
        // even when the app is in the background. Idempotent: only
        // fires when we cross the boundary, not on every refresh.
        if !Self.isPendingRestart(previousStatus) {
            NotificationManager.shared.notifyBackendUpdateReady(downloadedVersion: installed)
        }
    }

    private static func isPendingRestart(_ status: UpdateStatus) -> Bool {
        if case .downloadedPendingRestart = status { return true }
        return false
    }

    /// Background variant of `upgradeCosmaIfNeeded` that runs *after* the
    /// backend has launched. Same effect (running `uv tool upgrade cosma`
    /// when PyPI has a newer version), but the launch path no longer
    /// awaits it — so a slow PyPI fetch or a multi-minute wheel install
    /// can't keep the user staring at the setup wizard.
    ///
    /// Updated bits don't apply to the *currently running* process; they
    /// take effect on the next quit + relaunch. The reaper in
    /// `startManagedBackend` guarantees the old process gets killed
    /// before the new one is spawned, so there's no chance of two
    /// backends overlapping after an upgrade lands.
    private func upgradeCosmaInBackground() async {
        // No artificial delay. The PyPI check and `uv tool upgrade`
        // are network-bound (HTTPS + wheel download), so they don't
        // contend with the just-launched backend's local model load.
        // Starting immediately means a stale-frontend user sees the
        // friendly "Updating…" banner replace the red "Backend
        // incompatible" banner within a second instead of staring at
        // the red one for a few seconds while we did nothing.
        await upgradeCosmaIfNeeded()
    }

    /// Generic async timeout wrapper. `operation` is cancelled if it doesn't
    /// finish within `seconds`.
    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CosmaError.updateCheckFailed("timeout after \(seconds)s")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Check PyPI for a newer release and, if found, download it. If a new
    /// version is already on disk but pending restart, this is a no-op
    /// re-render. Safe to call manually from the "Check for Updates"
    /// button or from the periodic timer.
    func checkForUpdates() async {
        // Already pending restart — no need to recheck; the user just
        // needs to relaunch.
        if case .downloadedPendingRestart = updateStatus {
            lastUpdateCheckAt = Date()
            return
        }
        if case .downloading = updateStatus {
            lastUpdateCheckAt = Date()
            return
        }

        updateStatus = .checking

        do {
            let latest = try await fetchLatestPyPIVersion()
            latestVersion = latest
            await upgradeCosmaIfNeeded()
            // upgradeCosmaIfNeeded sets updateStatus on its own (downloading
            // / pendingRestart / upToDate / failed), so nothing more to do.
            _ = latest
        } catch {
            updateStatus = .failed(error.localizedDescription)
        }
        // Stamp completion regardless of outcome so the UI can show
        // "checked just now" even on a failed check.
        lastUpdateCheckAt = Date()
    }

    /// User hit "Dismiss" on the restart banner. Suppress notifications for
    /// this specific downloaded version until something newer ships.
    func dismissUpdate() {
        if case .downloadedPendingRestart(_, let downloaded) = updateStatus {
            dismissedVersion = downloaded
        }
        updateStatus = .upToDate
    }

    /// Relaunch the .app bundle and exit the current process. Called from
    /// the "Restart" banner button after a new backend version has been
    /// downloaded — the next launch's `getInstalledVersion()` picks up the
    /// new bits and the backend spawns against the new version.
    ///
    /// Sets `AppDelegate.bypassQuitConfirmationOnce` so the user isn't
    /// prompted with "are you sure?" for a quit they just programmatically
    /// initiated themselves by clicking "Restart."
    ///
    /// Robust against the rare case where `Bundle.main.bundleURL` points
    /// at a non-bundle (Xcode test runners) by falling back to a plain
    /// terminate so the user at least quits cleanly.
    func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let isAppBundle = bundleURL.pathExtension == "app"

        if isAppBundle {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.appendLog("[CosmaManager] Relaunch failed: \(error.localizedDescription)")
                        self?.updateStatus = .failed("Relaunch failed: \(error.localizedDescription)")
                        return
                    }
                    // Give the new instance a beat to start its CosmaManager
                    // and reap our soon-to-be-orphaned backend before we
                    // terminate. The reaper in startManagedBackend handles
                    // the overlap, but the small delay smooths the UX.
                    try? await Task.sleep(for: .milliseconds(400))
                    AppDelegate.bypassQuitConfirmationOnce = true
                    NSApp.terminate(nil)
                }
            }
        } else {
            appendLog("[CosmaManager] Not running from a .app bundle — terminating without relaunch")
            AppDelegate.bypassQuitConfirmationOnce = true
            NSApp.terminate(nil)
        }
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
                    self.installedVersion = await self.getInstalledVersion()
                    self.runningVersion = self.installedVersion
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

    /// Locate an executable. The fast path (stat-ing a handful of known
    /// install dirs) stays synchronous; the login-shell `which` fallback
    /// used to run with a synchronous `waitUntilExit` on the main actor,
    /// freezing the UI for up to several hundred ms while `.zshrc` loaded.
    /// Now it runs on a detached task so the main actor stays responsive.
    private func findExecutable(name: String) async -> String? {
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

        // Fallback: use /bin/sh -l -c which (login shell to get full PATH).
        // Offloaded to a detached task — a login shell can take hundreds of
        // ms to source .zshrc and blocking the main actor caused visible UI
        // hangs during bootstrap / update checks.
        let shellResult = await Task.detached(priority: .userInitiated) { () -> String? in
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
                        return path
                    }
                }
            } catch {}
            return nil
        }.value

        if let path = shellResult {
            appendLog("[CosmaManager] Found \(name) via shell at \(path)")
            return path
        }

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

    /// Find and terminate any process holding TCP port 60534 OR running a
    /// cosma-backend Python entrypoint. Called from `startManagedBackend`
    /// once the warm-attach probe has confirmed nothing healthy is on
    /// :60534, so any owner of that port is, by definition, stale.
    ///
    /// Strategy:
    ///   1. `lsof -nP -iTCP:60534 -sTCP:LISTEN -t` for PIDs holding the port.
    ///   2. `pgrep -f "cosma_backend|cosma serve"` to also catch backends
    ///      that crashed mid-boot (port not yet bound, but Python still up).
    ///   3. SIGTERM all collected PIDs, give them ~1.5s to exit cleanly,
    ///      then SIGKILL anything that didn't.
    ///   4. Wait up to ~2s for the port to become free before returning.
    ///
    /// We deliberately avoid killing arbitrary processes (no broad pkill);
    /// the union of "port holder" and "matches our Python entrypoint" is
    /// narrow enough that a false positive would have to be using our
    /// dedicated port AND running our module.
    private func reapStaleBackendProcesses() async {
        let pids = await collectStaleBackendPIDs()
        guard !pids.isEmpty else { return }
        appendLog("[CosmaManager] Reaping stale backend PIDs: \(pids)")

        // SIGTERM round — give the backend a chance to run its own
        // after_serving cleanup (Ollama unload, DB close).
        for pid in pids {
            kill(pid, SIGTERM)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        // SIGKILL anything still alive after the grace window.
        let stillAlive = pids.filter { isProcessAlive($0) }
        if !stillAlive.isEmpty {
            appendLog("[CosmaManager] SIGTERM didn't suffice for \(stillAlive); SIGKILL")
            for pid in stillAlive {
                kill(pid, SIGKILL)
            }
        }

        // Wait for the port to actually free up — the launch will fail
        // with EADDRINUSE if we race ahead. Bounded so we never block
        // the UI more than ~2s on this path.
        for _ in 0..<10 {
            if await !isPortBound(60534) { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Union of (a) PIDs listening on :60534 and (b) PIDs whose argv
    /// matches a cosma-backend entrypoint. Returns deduplicated, excludes
    /// our own pid out of paranoia.
    private func collectStaleBackendPIDs() async -> [pid_t] {
        var collected: Set<pid_t> = []

        // (a) Port holders. lsof's `-t` flag prints just PIDs, one per line.
        if let lsofPath = await findExecutable(name: "lsof") {
            if let out = try? await runProcess(
                executablePath: lsofPath,
                arguments: ["-nP", "-iTCP:60534", "-sTCP:LISTEN", "-t"]
            ) {
                for line in out.split(whereSeparator: { $0 == "\n" || $0 == " " }) {
                    if let pid = pid_t(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        collected.insert(pid)
                    }
                }
            }
        }

        // (b) Anything matching our Python entrypoint, in case the port
        // isn't bound yet (e.g., crashed mid-startup before listen()).
        if let pgrepPath = await findExecutable(name: "pgrep") {
            if let out = try? await runProcess(
                executablePath: pgrepPath,
                arguments: ["-f", "cosma_backend|cosma serve"]
            ) {
                for line in out.split(whereSeparator: { $0 == "\n" }) {
                    if let pid = pid_t(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        collected.insert(pid)
                    }
                }
            }
        }

        let mypid = ProcessInfo.processInfo.processIdentifier
        collected.remove(mypid)
        return Array(collected)
    }

    /// `kill -0` semantics: signal 0 doesn't deliver, just tests permission.
    /// Returns true iff the process exists and we can signal it.
    private func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    /// Quick TCP probe — bind would fail, so connect-then-close is the
    /// cheapest way to ask "is *something* listening here?". 100 ms timeout
    /// because either the port is bound and accepts immediately, or it's
    /// free and we get ECONNREFUSED instantly.
    private func isPortBound(_ port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue.global(qos: .utility)
            queue.async {
                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                defer { close(sock) }

                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

                let result = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                        Darwin.connect(sock, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                continuation.resume(returning: result == 0)
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

    // MARK: - Vision Self-Heal

    /// Last cosma version we ran the vision self-heal reinstall against.
    /// We only do the (heavy) reinstall once per version; if a future
    /// release happens to also have vision broken on the user's Python
    /// for some other reason, the marker advances and we try again.
    /// Stored as a string in UserDefaults for cross-launch persistence.
    private var visionSelfHealLastVersion: String? {
        get { UserDefaults.standard.string(forKey: "cosmaVisionSelfHealVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "cosmaVisionSelfHealVersion") }
    }

    /// Probe `/api/status/vision`, and if the backend reports the
    /// Qwen3-VL chat handler isn't loaded — meaning the cosma tool
    /// venv has stock-PyPI llama-cpp-python instead of the cosmasense
    /// fork — run a one-shot `uv tool install --reinstall cosma --with
    /// <fork-wheel>` to pull the fork wheel in, then restart the
    /// backend so the new venv contents take effect.
    ///
    /// Idempotent: tracks the cosma version we last self-healed for
    /// in UserDefaults and skips if we've already tried this release.
    /// If the endpoint is missing (older backend without the route)
    /// or any probe step throws, we silently bail — a missing endpoint
    /// is the same shape as "frontend was newer than backend during a
    /// rollout" and we shouldn't loop-reinstall on that.
    func runVisionSelfHealIfNeeded() async {
        // Bail early if we don't own the process — the user is on the
        // dev backend or attached to an external one and the reinstall
        // wouldn't apply to what's actually running.
        guard ownsProcess else { return }
        guard let installedNow = installedVersion else { return }
        if visionSelfHealLastVersion == installedNow {
            return
        }

        let visionAvailable: Bool?
        do {
            visionAvailable = try await APIClient.shared.fetchVisionAvailable()
        } catch {
            // Older backend without /api/status/vision returns 404 →
            // surfaces as a decoding/HTTP error here. Don't self-heal
            // on a missing endpoint.
            appendLog("[CosmaManager] Vision probe skipped: \(error.localizedDescription)")
            return
        }

        guard let available = visionAvailable else { return }
        if available {
            // Mark this version as healthy so the next launch doesn't
            // re-probe — `fetchVisionAvailable` is cheap, but writing
            // the marker keeps the log clean across restarts.
            visionSelfHealLastVersion = installedNow
            return
        }

        appendLog("""
        [CosmaManager] Vision self-heal: backend reports vision unavailable for \
        cosma v\(installedNow). Reinstalling with the cosmasense fork wheel \
        so Qwen3VLChatHandler is in the venv. This takes ~30 s and only runs once.
        """)

        guard let uvPath = await findExecutable(name: "uv") else {
            appendLog("[CosmaManager] Vision self-heal aborted: uv not on PATH")
            return
        }

        do {
            let output = try await runProcess(
                executablePath: uvPath,
                arguments: [
                    "tool", "install", "--reinstall", "cosma",
                    "--python", Self.cosmaToolPythonVersion,
                    "--with", Self.cosmaSenseForkWheelURL,
                ]
            )
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                appendLog("[CosmaManager] Vision self-heal install output: \(trimmed)")
            }
        } catch {
            appendLog("[CosmaManager] Vision self-heal install FAILED: \(error.localizedDescription). Vision will stay off until the user reinstalls manually.")
            return
        }

        // Mark BEFORE the restart — if the restart races us, we still
        // don't want to loop-reinstall on the next launch.
        visionSelfHealLastVersion = installedNow

        appendLog("[CosmaManager] Vision self-heal: restarting backend to load the fork.")
        isInternalRestartInFlight = true
        await restartServer()
        isInternalRestartInFlight = false
    }

    private func getInstalledVersion() async -> String? {
        guard let cosmaPath = await findExecutable(name: "cosma") else { return nil }
        do {
            let output = try await runProcess(executablePath: cosmaPath, arguments: ["--version"])
            // Recent cosma builds print a multi-line block:
            //   cosma version info:
            //     cosma: 0.8.1
            //     cosma-backend: 0.8.1
            //     cosma-tui: 0.4.0
            //     cosma-client: 0.2.0
            // The previous `split(" ").last` path grabbed the *last* token on
            // the last line — cosma-client's version — so the upgrade log
            // read "0.2.0 → 0.8.1" even when the real cosma was already
            // current. Match the top-level `cosma:` line first, then fall
            // back to the legacy single-line format for older builds.
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("cosma:") {
                    let value = trimmed.dropFirst("cosma:".count).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return value }
                }
            }
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
        // Bypass URLSession's default URL cache. PyPI's JSON endpoint
        // serves a `Cache-Control` header that lets URLSession reuse
        // a stale response for hours — without this, the first launch
        // after a `v*` tag push keeps seeing the previous version
        // ("cosma is up to date (vN-1)") long after PyPI itself has
        // already published vN, so the auto-upgrade silently misses
        // the release.
        var request = URLRequest(url: URL(string: "https://pypi.org/pypi/cosma/json")!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
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
            // Watch for the backend's final log line so stopServer() can
            // exit its SIGTERM wait immediately instead of always burning
            // the full timeout. The backend prints this from after_serving
            // once every teardown step has completed.
            let seenShutdown = str.contains("Shutdown complete")
            Task { @MainActor [weak self] in
                self?.appendLog(str)
                if seenShutdown { self?.shutdownCompleteSeen = true }
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
        Self.writeFrontendLog(text)
    }

    /// Append a line to ~/Library/Logs/cosma/cosma-frontend.log so startup,
    /// auto-install, and launch-strategy history survives app restarts. The
    /// in-memory `serverLog` is cleared whenever the process exits, which
    /// makes post-mortem debugging of a bad launch impossible.
    nonisolated private static func writeFrontendLog(_ text: String) {
        guard let logURL = frontendLogURL() else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(text)\n"
        guard let data = line.data(using: .utf8) else { return }

        let fm = FileManager.default
        _ = try? fm.createDirectory(at: logURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    nonisolated private static func frontendLogURL() -> URL? {
        guard let pw = getpwuid(getuid()), let homeC = pw.pointee.pw_dir else {
            return nil
        }
        let home = String(cString: homeC)
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Logs/cosma/cosma-frontend.log")
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
