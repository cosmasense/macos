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
    var recentSearches: [RecentSearch] = []
    @ObservationIgnored var lastSearchQuery: String?
    @ObservationIgnored var activeSearchRequestID: UUID?

    /// In-memory cache of search results keyed on "query|directory|limit".
    /// Lets repeated identical queries return instantly while still firing a
    /// background refresh to keep results fresh.
    @ObservationIgnored var searchResultCache: [String: (results: [SearchResultItem], cachedAt: Date)] = [:]
    nonisolated static let searchCacheTTL: TimeInterval = 5 * 60  // 5 minutes
    nonisolated static let searchCacheMaxEntries: Int = 50

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

    // MARK: - Embedder Readiness

    /// Whether the backend's embedding model has finished loading.
    /// While false, search requests are held and a loading indicator is shown.
    var isEmbedderReady: Bool = false
    /// Backend Phase 2 initialization progress (0.0 → 1.0).
    var embedderLoadProgress: Double = 0
    @ObservationIgnored private var embedderPollTask: Task<Void, Never>?

    // MARK: - Model Availability Notification

    /// Non-nil when the configured summarizer model has failed its availability check.
    /// Observed by ContentView to show an in-app banner.
    var modelAvailabilityWarning: ModelAvailabilityWarning?

    struct ModelAvailabilityWarning: Equatable {
        let provider: String
        let model: String
        let detail: String
    }

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
        Task { [weak self] in
            await self?.refreshWatchedFolders()
            await self?.refreshFileStats()
            await self?.refreshFilterConfig()
            await self?.refreshBackendSettings()
        }
        startEmbedderReadinessPolling()
    }

    /// Polls `/api/status/` until `embedder_ready` is true,
    /// then waits 1 second before marking the embedder as ready.
    private func startEmbedderReadinessPolling() {
        embedderPollTask?.cancel()
        embedderPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let status = try await apiClient.fetchStatus()
                    if let progress = status.initProgress {
                        self.embedderLoadProgress = progress
                    }
                    if status.embedderReady == true {
                        self.embedderLoadProgress = 1.0
                        // Wait 1s after model load before enabling search
                        try await Task.sleep(for: .seconds(1))
                        if !Task.isCancelled {
                            self.isEmbedderReady = true
                        }
                        return
                    }
                } catch {
                    // Backend may not be fully up yet, keep polling
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    deinit {
        updatesStream.disconnect()
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
