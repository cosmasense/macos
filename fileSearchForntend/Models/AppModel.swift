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

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case jobs = "Jobs"
    case queue = "Queue"
    case settings = "Settings"

    var id: String { rawValue }
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

    var selection: SidebarItem? = .home

    // MARK: - Watched Folders State

    var watchedFolders: [WatchedFolder] = []
    var isLoadingWatchedFolders: Bool = false
    var missingWatchedEndpoint: Bool = false
    var jobsError: String?

    // MARK: - Main Window Search State

    var searchText: String = ""
    var searchTokens: [SearchToken] = []
    var searchResults: [SearchResultItem] = []
    var isSearching: Bool = false
    var searchError: String?
    var recentSearches: [RecentSearch] = []
    @ObservationIgnored var lastSearchQuery: String?
    @ObservationIgnored var activeSearchRequestID: UUID?

    // MARK: - Popup Search State (Quick Search Overlay)

    var popupSearchText: String = ""
    var popupSearchTokens: [SearchToken] = []
    var popupSearchResults: [SearchResultItem] = []
    var popupIsSearching: Bool = false
    var popupSearchError: String?
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

        configureStreams()
        loadSecurityBookmarks()

        Task { [weak self] in
            await self?.refreshWatchedFolders()
            await self?.refreshFilterConfig()
            await self?.refreshBackendSettings()
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
            for i in watchedFolders.indices where watchedFolders[i].status == .paused {
                watchedFolders[i].status = .indexing
            }

        case .schedulerPaused:
            for i in watchedFolders.indices where watchedFolders[i].status == .indexing {
                watchedFolders[i].status = .paused
            }

        case .schedulerResumed:
            for i in watchedFolders.indices where watchedFolders[i].status == .paused {
                watchedFolders[i].status = .indexing
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
