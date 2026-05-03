//
//  AppModel.swift
//  fileSearchForntend
//
//  Main app state management using @Observable.
//  Core state, initialization, and SSE event handling.
//
//  Extended by:
//  - AppModel+Search.swift   - Search functionality
//  - AppModel+Queue.swift    - Queue management
//  - AppModel+Folders.swift  - Watched folder operations
//  - AppModel+Settings.swift - Backend/filter settings
//

import Foundation
import Observation
import AppKit

// MARK: - Navigation

enum AppPage: Equatable {
    case home
    case folders
}

// MARK: - App Model

@MainActor
@Observable
class AppModel {

    // MARK: - Types

    enum BackendConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case error(String)

        var statusDescription: String {
            switch self {
            case .idle:
                return "Idle"
            case .connecting:
                return "Connecting"
            case .connected:
                return "Live updates"
            case .error(let message):
                return "Disconnected (\(message))"
            }
        }
    }

    enum BookmarkError: Error {
        case userCancelled
        case folderUnknown
    }

    // MARK: - Constants

    nonisolated static let backendURLDefaultsKey = "backendURL"
    nonisolated static let bookmarksDefaultsKey = "watchedFolderBookmarks"
    static let progressWindowSeconds: TimeInterval = 30 * 60 // 30 minutes

    // MARK: - Navigation State

    var currentPage: AppPage = .home

    /// Mirror of CosmaManager.bootstrapReady, updated from the app root
    /// whenever bootstrap status changes. We duplicate this onto AppModel
    /// so non-View code (search funcs, indexing triggers) can gate without
    /// pulling CosmaManager into the model layer. Defaults to true so
    /// pre-setup code paths (before the mirror is first set) don't block
    /// unrelated operations.
    var aiReadyForSearch: Bool = true

    // MARK: - Watched Folders State

    var watchedFolders: [WatchedFolder] = []
    var isLoadingWatchedFolders: Bool = false
    var missingWatchedEndpoint: Bool = false
    var jobsError: String?
    var fileStats: FileStatsResponse?

    // MARK: - Main Window Search State

    var searchText: String = ""
    var searchTokens: [SearchToken] = []
    var searchResults: [SearchResultItem] = []
    var isSearching: Bool = false
    var searchError: String?
    var isSearchFieldFocused: Bool = false
    var recentSearches: [RecentSearch] = []
    @ObservationIgnored var lastSearchQuery: String?
    @ObservationIgnored var activeSearchRequestID: UUID?

    /// In-memory cache of search results keyed on "query|directory|limit".
    /// Lets repeated identical queries return instantly while still firing a
    /// background refresh to keep results fresh.
    @ObservationIgnored var searchResultCache: [String: (results: [SearchResultItem], cachedAt: Date)] = [:]
    nonisolated static let searchCacheTTL: TimeInterval = 5 * 60  // 5 minutes
    nonisolated static let searchCacheMaxEntries: Int = 50

    /// Debounced /api/search/typing dispatcher. Each keystroke calls
    /// `notifySearchTyping()`, which (re)schedules a 200ms timer; when
    /// that timer fires we hit the backend so it pauses indexing and
    /// cancels in-flight tasks. Guarantees we don't burn an HTTP call
    /// per character, and guarantees the GPU/CPU is freed before the
    /// user hits Enter.
    @ObservationIgnored private var searchTypingNudgeTask: Task<Void, Never>?
    nonisolated static let searchTypingDebounceInterval: Duration = .milliseconds(200)

    /// Call from any onChange handler attached to a search field. Idempotent.
    func notifySearchTyping() {
        searchTypingNudgeTask?.cancel()
        searchTypingNudgeTask = Task { [apiClient] in
            try? await Task.sleep(for: Self.searchTypingDebounceInterval)
            if Task.isCancelled { return }
            await apiClient.searchTypingNudge()
        }
    }

    // MARK: - Popup Search State (Quick Search Overlay)

    var popupSearchText: String = ""
    var popupSearchTokens: [SearchToken] = []
    var popupSearchResults: [SearchResultItem] = []
    var popupIsSearching: Bool = false
    var popupSearchError: String?
    var popupOpenCount: Int = 0
    @ObservationIgnored var activePopupSearchRequestID: UUID?

    // MARK: - Backend Connection State

    var backendConnectionState: BackendConnectionState = .idle
    var backendURL: String {
        didSet {
            guard backendURL != oldValue else { return }
            UserDefaults.standard.set(backendURL, forKey: Self.backendURLDefaultsKey)
            reconfigureBackend()
        }
    }

    // MARK: - Filter Configuration State

    var fileFilterEnabled: Bool = true
    var filterMode: String = "blacklist"
    var blacklistExclude: [String] = []
    var blacklistInclude: [String] = []
    var whitelistInclude: [String] = []
    var whitelistExclude: [String] = []
    var savedFilterMode: String = "blacklist"
    var savedBlacklistExclude: [String] = []
    var savedBlacklistInclude: [String] = []
    var savedWhitelistInclude: [String] = []
    var savedWhitelistExclude: [String] = []
    var isLoadingFilterConfig: Bool = false
    var filterConfigError: String?

    /// Derived exclude patterns based on current mode
    var excludePatterns: [String] {
        filterMode == "blacklist" ? blacklistExclude : whitelistExclude
    }

    /// Derived include patterns based on current mode
    var includePatterns: [String] {
        filterMode == "blacklist" ? blacklistInclude : whitelistInclude
    }

    /// Whether there are unsaved filter changes
    var hasUnsavedFilterChanges: Bool {
        filterMode != savedFilterMode ||
        blacklistExclude != savedBlacklistExclude ||
        blacklistInclude != savedBlacklistInclude ||
        whitelistInclude != savedWhitelistInclude ||
        whitelistExclude != savedWhitelistExclude
    }

    /// Filter patterns for UI display
    var fileFilterPatterns: [FileFilterPattern] {
        get {
            var patterns: [FileFilterPattern] = []
            for pattern in excludePatterns {
                patterns.append(FileFilterPattern(pattern: pattern, isEnabled: true))
            }
            for pattern in includePatterns {
                patterns.append(FileFilterPattern(pattern: "!\(pattern)", isEnabled: true))
            }
            return patterns
        }
        set {
            var newExclude: [String] = []
            var newInclude: [String] = []

            for pattern in newValue where pattern.isEnabled {
                if pattern.isNegation {
                    newInclude.append(pattern.effectivePattern)
                } else {
                    newExclude.append(pattern.pattern)
                }
            }

            if filterMode == "blacklist" {
                blacklistExclude = newExclude
                blacklistInclude = newInclude
            } else {
                whitelistInclude = newInclude
                whitelistExclude = newExclude
            }
        }
    }

    /// Legacy property - derives from filter patterns
    var hideHiddenFiles: Bool {
        get {
            fileFilterEnabled && excludePatterns.contains(".*")
        }
        set {
            if newValue && !excludePatterns.contains(".*") {
                addFilterPattern(".*")
            } else if !newValue && excludePatterns.contains(".*") {
                removeFilterPattern(FileFilterPattern(pattern: ".*"))
            }
        }
    }

    // MARK: - Backend Settings State

    var backendSettings: BackendSettingsResponse?
    var processingSettings: BackendSettings?
    var isLoadingSettings: Bool = false
    var settingsError: String?
    var savingSettingPaths: Set<String> = []
    var savedSettingPaths: Set<String> = []

    // MARK: - Model Availability Notification

    /// Non-nil when the configured summarizer model has failed its availability check.
    /// Observed by ContentView to show an in-app banner.
    var modelAvailabilityWarning: ModelAvailabilityWarning?

    struct ModelAvailabilityWarning: Equatable {
        let provider: String
        let model: String
        let detail: String
    }

    // MARK: - Embedder Readiness
    //
    // `bootstrapReady` (on CosmaManager) only tells us the *files* needed
    // to run AI are present on disk. It does NOT guarantee the embedder
    // has been loaded into memory — that load happens lazily on first use
    // and can take ~2-5s on cold start. Searching during that window
    // returned 503 / no-results, which the user observed as "search just
    // doesn't work right after launch." Track the live readiness flag
    // from /api/status/ so views can disable the search bar until it's
    // actually safe to query.
    var embedderReady: Bool = false
    @ObservationIgnored private var embedderPollTask: Task<Void, Never>?

    // MARK: - Backend version handshake
    //
    // Populated once on connectToBackend() and on every reconnect. When
    // `backendIncompatibleMessage` is non-nil, the UI must refuse to issue
    // search/index/queue requests — they would either silently misbehave
    // or hit endpoints that don't exist on the running backend. See
    // BackendCompatibility.swift.
    var backendVersion: BackendVersionResponse?
    var backendIncompatibleMessage: String?

    // MARK: - Queue State

    var queueStatus: QueueStatusResponse?
    var queueItems: [QueueItemResponse] = []
    var queueTotalCount: Int = 0
    var isLoadingQueue: Bool = false
    var queueError: String?
    var schedulerConfig: SchedulerResponse?
    var failedFiles: [ProcessedFileItem] = []
    var recentFiles: [ProcessedFileItem] = []
    @ObservationIgnored var queueProgressItems: [String: (addedAt: Date, completed: Bool)] = [:]

    // MARK: - Services

    @ObservationIgnored let apiClient: APIClient
    @ObservationIgnored let updatesStream = UpdatesStream()
    @ObservationIgnored nonisolated(unsafe) var securityBookmarks: [String: Data] = [:]
    @ObservationIgnored let bookmarkQueue = DispatchQueue(label: "com.filesearch.bookmarks", attributes: .concurrent)

    // MARK: - Initialization

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient ?? APIClient.shared

        let storedURL = UserDefaults.standard.string(forKey: Self.backendURLDefaultsKey)
        self.backendURL = storedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? storedURL!.trimmingCharacters(in: .whitespacesAndNewlines)
            : self.apiClient.currentBaseURL().absoluteString

        // Only set up the URL — don't connect until backend is ready
        if let url = URL(string: backendURL) {
            apiClient?.updateBaseURL(url) ?? APIClient.shared.updateBaseURL(url)
        }
        loadSecurityBookmarks()
    }

    /// Call this AFTER the backend is confirmed reachable.
    /// Connects SSE stream and fetches initial data.
    func connectToBackend() {
        configureStreams()
        startEmbedderReadinessPolling()
        Task { [weak self] in
            // Run the version handshake first so a mismatch surfaces in
            // the UI before any feature work fires off requests against
            // an incompatible backend.
            await self?.refreshBackendVersion()
            await self?.refreshWatchedFolders()
            await self?.refreshFileStats()
            await self?.refreshFilterConfig()
            await self?.refreshBackendSettings()
        }
    }

    /// Probe `/api/status/version` and populate `backendVersion` /
    /// `backendIncompatibleMessage`. Idempotent. Called from
    /// `connectToBackend` and exposed for manual retry from a "Retry
    /// connection" button.
    func refreshBackendVersion() async {
        let result = await BackendCompatibility.check(using: apiClient)
        switch result {
        case let .compatible(version):
            self.backendVersion = version
            self.backendIncompatibleMessage = nil
        case .backendTooNew, .backendTooOld, .probeFailed:
            self.backendVersion = nil
            self.backendIncompatibleMessage = result.userFacingMessage
        }
    }

    /// Poll /api/status/ until the backend reports `embedder_ready=true`,
    /// then stop. Uses the fast 3s-timeout health session inside
    /// fetchStatus(), so each poll fails quickly rather than queueing
    /// 30s-deep behind a stalled backend.
    ///
    /// Backoff strategy: 2s after a successful (but not-yet-ready)
    /// response so we get prompt UI updates once the embedder finishes
    /// loading; 5s after a connection refused / timeout so we don't
    /// pile up requests against an unresponsive backend. Without the
    /// error backoff, a stuck event loop produced ~15 in-flight pollers
    /// (3s timeout + 2s sleep across 30+ seconds) which only made the
    /// stall worse.
    private func startEmbedderReadinessPolling() {
        embedderPollTask?.cancel()
        embedderPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                var delay: Duration = .seconds(2)
                do {
                    let status = try await self.apiClient.fetchStatus()
                    let ready = status.embedderReady ?? false
                    if ready != self.embedderReady {
                        self.embedderReady = ready
                    }
                    if ready { return }
                } catch {
                    // Connection refused (backend cold) or timeout
                    // (event loop blocked) — back off harder and don't
                    // spam logs. Connection-state machinery handles the
                    // user-facing "backend down" surfacing.
                    delay = .seconds(5)
                }
                try? await Task.sleep(for: delay)
            }
        }
    }

    deinit {
        updatesStream.disconnect()
        embedderPollTask?.cancel()
    }

    // MARK: - Backend Connection

    private func configureStreams() {
        updatesStream.onEvent = { [weak self] event in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.handleBackend(event: event)
            }
        }

        updatesStream.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleUpdatesState(state)
            }
        }

        if let url = URL(string: backendURL) {
            apiClient.updateBaseURL(url)
            updatesStream.connect(to: url)
        } else {
            backendConnectionState = .error("Invalid backend URL")
        }
    }

    private func reconfigureBackend() {
        guard let url = URL(string: backendURL) else {
            backendConnectionState = .error("Invalid backend URL")
            return
        }
        apiClient.updateBaseURL(url)
        updatesStream.connect(to: url)

        Task { [weak self] in
            await self?.refreshWatchedFolders()
            await self?.refreshFilterConfig()
            await self?.refreshBackendSettings()
        }
    }

    private func handleUpdatesState(_ state: UpdatesStream.State) {
        switch state {
        case .idle:
            backendConnectionState = .idle
        case .connecting:
            backendConnectionState = .connecting
        case .connected:
            backendConnectionState = .connected
        case .failed(let message):
            backendConnectionState = .error(message)
        }
    }

    // MARK: - SSE Event Handling

    private func handleBackend(event: BackendUpdateEvent) {
        let path = event.data.path

        switch event.opcode {

        // MARK: Watch Events

        case .watchStarted, .watchAdded:
            if let dirPath = path {
                upsertFolder(forDirectory: dirPath) { folder in
                    folder.status = .indexing
                    folder.progress = max(folder.progress, 0.05)
                    folder.lastModified = Date()
                    folder.lastIssueMessage = nil
                    folder.lastIssueDate = nil
                    folder.skippedFileCount = 0
                }
            }

        case .watchRemoved:
            if let dirPath = path {
                let normalized = (dirPath as NSString).standardizingPath
                watchedFolders.removeAll { $0.path == normalized }
            }

        // MARK: Directory Events

        case .directoryProcessingStarted:
            if let dirPath = path {
                upsertFolder(forDirectory: dirPath) { folder in
                    folder.status = .indexing
                    folder.progress = 0.05
                    folder.lastModified = Date()
                    folder.lastIssueMessage = nil
                    folder.lastIssueDate = nil
                    folder.skippedFileCount = 0
                    folder.indexedFileCount = 0
                    folder.totalFileCount = 0
                }
            }

        case .directoryProcessingCompleted:
            if let dirPath = path {
                let normalized = (dirPath as NSString).standardizingPath
                let hasActiveQueueItems = queueProgressItems.contains {
                    ($0.key as NSString).standardizingPath.hasPrefix(normalized) && !$0.value.completed
                }
                if !hasActiveQueueItems {
                    upsertFolder(forDirectory: dirPath) { folder in
                        folder.status = .complete
                        // Align counts so ring (which reads from counts) matches 100%
                        if folder.totalFileCount == 0 {
                            folder.totalFileCount = max(folder.indexedFileCount, 1)
                        }
                        folder.indexedFileCount = folder.totalFileCount
                        folder.progress = 1.0
                        folder.lastModified = Date()
                    }
                }
            }

        case .directoryDeleted:
            if let dirPath = path {
                let normalized = (dirPath as NSString).standardizingPath
                watchedFolders.removeAll { $0.path == normalized }
            }

        case .directoryMoved:
            break

        // MARK: File Processing Events

        case .fileParsing, .fileParsed, .fileSummarizing, .fileSummarized,
             .fileEmbedding, .fileEmbedded, .fileComplete:
            if let filePath = path {
                bumpProgress(forFilePath: filePath, completed: event.opcode == .fileComplete)
            }

        case .fileSkipped:
            if let filePath = path {
                updateFolder(forFilePath: filePath) { folder in
                    folder.progress = min(1.0, folder.progress + 0.02)
                    folder.lastModified = Date()
                }
            }

        case .fileFailed:
            if let filePath = path {
                updateFolder(forFilePath: filePath) { folder in
                    folder.status = .indexing
                    folder.lastModified = Date()
                    folder.skippedFileCount += 1
                    let message = event.errorMessage ??
                        "Unable to process \(URL(fileURLWithPath: filePath).lastPathComponent)"
                    folder.lastIssueMessage = message
                    folder.lastIssueDate = Date()
                }
            }

        case .fileCreated, .fileModified:
            if let filePath = path {
                updateFolder(forFilePath: filePath) { folder in
                    if folder.status == .complete {
                        folder.status = .indexing
                        folder.progress = 0.9
                    }
                    folder.lastModified = Date()
                }
            }

        case .fileDeleted:
            if let filePath = path {
                updateFolder(forFilePath: filePath) { folder in
                    folder.lastModified = Date()
                }
            }

        case .fileMoved:
            break

        // MARK: Queue Events

        case .queueItemAdded:
            if let fp = event.data.filePath {
                trackQueueItemAdded(filePath: fp)
            }

        case .queueBatchAdded:
            // Coalesced burst from the backend during bulk discovery —
            // see indexing_queue._added_flush_loop. One SSE event with
            // up to ~500 paths instead of 500 individual ADDED events.
            // Use the batch tracker so we mutate each watched folder's
            // counters exactly once instead of N times — the per-path
            // loop produced a 150 s main-thread hang during a fresh
            // discovery sweep (see temp/log.md).
            if let paths = event.data.paths {
                trackQueueItemsAddedBatch(filePaths: paths)
            }

        case .queueItemUpdated, .queueItemProcessing:
            break

        case .queueItemCompleted:
            if let fp = event.data.filePath {
                trackQueueItemCompleted(filePath: fp)
            }

        case .queueItemFailed:
            if let fp = event.data.filePath {
                trackQueueItemCompleted(filePath: fp)
            }

        case .queueItemRemoved:
            if let fp = event.data.filePath {
                trackQueueItemRemoved(filePath: fp)
            }

        case .queuePaused:
            for i in watchedFolders.indices where watchedFolders[i].status == .indexing {
                watchedFolders[i].status = .paused
            }

        case .queueResumed:
            // Only resume folders if the queue is truly unpaused (scheduler may still hold it)
            Task { await refreshQueueStatus() }
            if queueStatus?.schedulerPaused != true {
                for i in watchedFolders.indices where watchedFolders[i].status == .paused {
                    watchedFolders[i].status = .indexing
                }
            }

        case .schedulerPaused:
            for i in watchedFolders.indices where watchedFolders[i].status == .indexing {
                watchedFolders[i].status = .paused
            }

        case .schedulerResumed:
            // Only resume folders if the queue is truly unpaused (manual pause may still hold it)
            Task { await refreshQueueStatus() }
            if queueStatus?.manuallyPaused != true {
                for i in watchedFolders.indices where watchedFolders[i].status == .paused {
                    watchedFolders[i].status = .indexing
                }
            }

        // MARK: System Events

        case .error:
            if let message = event.message {
                jobsError = message
            }

        case .info, .statusUpdate:
            break

        case .shuttingDown:
            backendConnectionState = .error("Backend shutting down")

        case .unknown:
            #if DEBUG
            print("Unknown SSE opcode received")
            #endif
        }
    }
}
