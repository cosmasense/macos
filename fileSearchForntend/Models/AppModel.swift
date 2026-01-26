//
//  AppModel.swift
//  fileSearchForntend
//
//  Main app state management using @Observable
//

import Foundation
import Observation
import AppKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case jobs = "Jobs"
    case settings = "Settings"

    var id: String { rawValue }
}

@MainActor
@Observable
class AppModel {
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
    
    nonisolated private static let backendURLDefaultsKey = "backendURL"
    nonisolated private static let bookmarksDefaultsKey = "watchedFolderBookmarks"
    
    // Navigation
    var selection: SidebarItem? = .home

    // Data
    var watchedFolders: [WatchedFolder] = []
    var recentSearches: [RecentSearch] = []
    var isLoadingWatchedFolders: Bool = false
    var missingWatchedEndpoint: Bool = false

    // Search state
    var searchText: String = ""
    var searchTokens: [SearchToken] = []
    var searchResults: [SearchResultItem] = []
    var isSearching: Bool = false
    var searchError: String?
    var jobsError: String?
    var backendConnectionState: BackendConnectionState = .idle
    private var lastSearchQuery: String?
    @ObservationIgnored private var activeSearchRequestID: UUID?
    var backendURL: String {
        didSet {
            guard backendURL != oldValue else { return }
            UserDefaults.standard.set(backendURL, forKey: Self.backendURLDefaultsKey)
            reconfigureBackend()
        }
    }
    /// Whether file filtering is enabled (based on backend mode)
    var fileFilterEnabled: Bool = true

    /// Current filter mode (local, may differ from saved)
    var filterMode: String = "blacklist"

    /// Mode-specific pattern storage (NEW)
    var blacklistExclude: [String] = []
    var blacklistInclude: [String] = []
    var whitelistInclude: [String] = []
    var whitelistExclude: [String] = []

    /// Legacy exclude/include patterns (derived from mode-specific patterns)
    var excludePatterns: [String] {
        filterMode == "blacklist" ? blacklistExclude : whitelistExclude
    }

    var includePatterns: [String] {
        filterMode == "blacklist" ? blacklistInclude : whitelistInclude
    }

    /// Saved state from backend (for dirty tracking)
    private var savedFilterMode: String = "blacklist"
    private var savedBlacklistExclude: [String] = []
    private var savedBlacklistInclude: [String] = []
    private var savedWhitelistInclude: [String] = []
    private var savedWhitelistExclude: [String] = []

    /// Whether there are unsaved changes
    var hasUnsavedFilterChanges: Bool {
        filterMode != savedFilterMode ||
        blacklistExclude != savedBlacklistExclude ||
        blacklistInclude != savedBlacklistInclude ||
        whitelistInclude != savedWhitelistInclude ||
        whitelistExclude != savedWhitelistExclude
    }

    /// Whether filter config is loading
    var isLoadingFilterConfig: Bool = false

    /// Filter config loading error
    var filterConfigError: String?

    /// Filter patterns for UI display - derived from backend patterns
    var fileFilterPatterns: [FileFilterPattern] {
        get {
            var patterns: [FileFilterPattern] = []

            // Add exclude patterns
            for pattern in excludePatterns {
                patterns.append(FileFilterPattern(pattern: pattern, isEnabled: true))
            }

            // Add include patterns with ! prefix
            for pattern in includePatterns {
                patterns.append(FileFilterPattern(pattern: "!\(pattern)", isEnabled: true))
            }

            return patterns
        }
        set {
            // Extract exclude and include patterns from the array
            var newExclude: [String] = []
            var newInclude: [String] = []

            for pattern in newValue where pattern.isEnabled {
                if pattern.isNegation {
                    newInclude.append(pattern.effectivePattern)
                } else {
                    newExclude.append(pattern.pattern)
                }
            }

            // Update mode-specific arrays based on current mode
            if filterMode == "blacklist" {
                blacklistExclude = newExclude
                blacklistInclude = newInclude
            } else {
                whitelistInclude = newInclude
                whitelistExclude = newExclude
            }
        }
    }

    /// Legacy property for backwards compatibility - now derived from filter patterns
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

    // API Client
    @ObservationIgnored private let apiClient: APIClient
    @ObservationIgnored private let updatesStream = UpdatesStream()
    @ObservationIgnored nonisolated(unsafe) private var securityBookmarks: [String: Data] = [:]
    @ObservationIgnored private let bookmarkQueue = DispatchQueue(label: "com.filesearch.bookmarks", attributes: .concurrent)
    
    enum BookmarkError: Error {
        case userCancelled
        case folderUnknown
    }

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
        }
    }

    deinit {
        updatesStream.disconnect()
    }

    private func configureStreams() {
        if let url = URL(string: backendURL) {
            apiClient.updateBaseURL(url)
            updatesStream.connect(to: url)
        } else {
            backendConnectionState = .error("Invalid backend URL")
        }
        
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
        }
    }
    
    // MARK: - Folder Management

    func addFolder(url: URL) {
        // Start accessing the security-scoped resource
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        storeSecurityBookmark(for: url)
        let path = url.path
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await apiClient.startWatchingDirectory(path: path)
                await refreshWatchedFolders()
            } catch let error as APIError {
                jobsError = error.localizedDescription
            } catch {
                jobsError = error.localizedDescription
            }
        }
    }

    func removeFolder(_ folder: WatchedFolder) {
        guard let jobId = folder.backendID else {
            jobsError = "Cannot remove folder: missing backend ID"
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await apiClient.deleteWatchJob(jobId: jobId)
                if response.success {
                    // Remove from local list immediately for responsive UI
                    watchedFolders.removeAll { $0.id == folder.id }
                    // Also refresh from backend to ensure consistency
                    await refreshWatchedFolders()
                } else {
                    jobsError = response.message
                }
            } catch let error as APIError {
                jobsError = error.localizedDescription
            } catch {
                jobsError = error.localizedDescription
            }
        }
    }
    
    func reindex(folder: WatchedFolder) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await apiClient.indexDirectory(path: folder.path)
            } catch let error as APIError {
                jobsError = error.localizedDescription
            } catch {
                jobsError = error.localizedDescription
            }
        }
    }
    
    func refreshWatchedFolders() async {
        isLoadingWatchedFolders = true
        defer { isLoadingWatchedFolders = false }

        do {
            let response = try await apiClient.fetchWatchJobs()
            missingWatchedEndpoint = false
            watchedFolders = response.jobs
                .map { WatchedFolder(response: $0) }
                .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        } catch let error as APIError {
            handleWatchListError(error)
        } catch {
            jobsError = "Unable to load watched folders: \(error.localizedDescription)"
        }
    }

    // MARK: - Search

    func performSearch() {
        let query = buildSearchQuery()
        
        // Don't search if query is empty
        guard !query.isEmpty else { return }
        
        // Add to recent searches
        let newSearch = RecentSearch(
            date: Date(),
            rawQuery: query,
            tokens: searchTokens
        )
        recentSearches.insert(newSearch, at: 0)
        
        // Perform API search
        Task {
            await searchFiles(query: query)
        }
    }
    
    @MainActor
    func searchFiles(query: String) async {
        // Strip @ tokens from the query - directory is passed separately
        let cleanedQuery = stripTokensFromQuery(query)
        let normalizedQuery = cleanedQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // Allow search even if query is empty but we have directory filter
        let directory = directoryFromTokens()
        guard !normalizedQuery.isEmpty || directory != nil else { return }

        let requestID = UUID()
        activeSearchRequestID = requestID
        lastSearchQuery = query // Store original query for retry
        isSearching = true
        searchError = nil
        searchResults = []

        defer {
            if activeSearchRequestID == requestID {
                isSearching = false
                activeSearchRequestID = nil
            }
        }

        do {
            // Use new POST /api/search endpoint
            // Don't pass filters - directory is enough
            let response = try await apiClient.search(
                query: normalizedQuery.isEmpty ? "*" : normalizedQuery,
                directory: directory,
                filters: nil,
                limit: 50
            )

            guard activeSearchRequestID == requestID else { return }
            searchResults = response.results
        } catch let error as APIError {
            guard activeSearchRequestID == requestID else { return }
            searchError = error.localizedDescription
        } catch {
            guard activeSearchRequestID == requestID else { return }
            searchError = "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    private func stripTokensFromQuery(_ query: String) -> String {
        // Remove @FolderName patterns from the query
        var result = query
        for token in searchTokens {
            result = result.replacingOccurrences(of: "@\(token.value)", with: "")
        }
        // Also remove any remaining @ patterns that might match watched folders
        let words = result.split(separator: " ")
        let cleanedWords = words.filter { word in
            if word.hasPrefix("@") {
                let folderName = String(word.dropFirst())
                return !watchedFolders.contains { $0.name.caseInsensitiveCompare(folderName) == .orderedSame }
            }
            return true
        }
        return cleanedWords.joined(separator: " ")
    }
    
    func clearSearchResults() {
        searchResults = []
        searchError = nil
    }

    func loadRecentSearch(_ search: RecentSearch) {
        searchTokens = search.tokens
        // Extract text without tokens
        let tokenStrings = search.tokens.map { "@\($0.value)" }
        var text = search.rawQuery
        for tokenStr in tokenStrings {
            text = text.replacingOccurrences(of: tokenStr, with: "")
        }
        searchText = text.trimmingCharacters(in: .whitespaces)
        
        // Perform the search automatically
        Task {
            await searchFiles(query: search.rawQuery)
        }
    }
    
    var canRetryLastSearch: Bool {
        guard let query = lastSearchQuery else { return false }
        return !query.isEmpty
    }
    
    func retryLastSearch() {
        guard canRetryLastSearch, let query = lastSearchQuery else { return }
        Task {
            await searchFiles(query: query)
        }
    }

    private func buildSearchQuery() -> String {
        let tokenStrings = searchTokens.map { token in
            switch token.kind {
            case .folder:
                return "@\(token.value)"
            }
        }
        let components = tokenStrings + [searchText]
        return components.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Backend updates
    
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
    
    private func handleBackend(event: BackendUpdateEvent) {
        // For directory events, path is the directory itself
        // For file events, path is the file path
        let path = event.data.path

        switch event.opcode {
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
                // Remove folder from local list when watch is removed
                let normalized = (dirPath as NSString).standardizingPath
                watchedFolders.removeAll { $0.path == normalized }
            }

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
                upsertFolder(forDirectory: dirPath) { folder in
                    folder.status = .complete
                    folder.progress = 1.0
                    folder.lastModified = Date()
                }
            }

        case .fileParsing, .fileParsed, .fileSummarizing, .fileSummarized,
             .fileEmbedding, .fileEmbedded, .fileComplete:
            if let filePath = path {
                bumpProgress(forFilePath: filePath, completed: event.opcode == .fileComplete)
            }

        case .fileSkipped:
            // File was skipped (already processed or filtered out)
            // Just bump progress slightly
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
            // File was created or modified - processing will follow
            if let filePath = path {
                updateFolder(forFilePath: filePath) { folder in
                    if folder.status == .complete {
                        folder.status = .indexing
                        folder.progress = 0.9  // Near complete, just updating
                    }
                    folder.lastModified = Date()
                }
            }

        case .fileDeleted:
            // File was deleted from watched directory
            // No progress update needed, but could update lastModified
            if let filePath = path {
                updateFolder(forFilePath: filePath) { folder in
                    folder.lastModified = Date()
                }
            }

        case .fileMoved:
            // File was moved - handled by src_path and dest_path
            // Typically treated as delete + create
            break

        case .error:
            // General error from backend
            if let message = event.message {
                jobsError = message
            }

        case .info, .statusUpdate:
            // Informational messages - could log or display
            break

        case .shuttingDown:
            // Backend is shutting down
            backendConnectionState = .error("Backend shutting down")

        case .unknown:
            // Unknown opcode - log for debugging
            print("Unknown SSE opcode received")
        }
    }
    
    private func upsertFolder(
        forDirectory directory: String,
        mutate: (inout WatchedFolder) -> Void
    ) {
        let normalized = (directory as NSString).standardizingPath
        if let index = watchedFolders.firstIndex(where: { $0.path == normalized }) {
            mutate(&watchedFolders[index])
            return
        }
        
        var folder = WatchedFolder(
            name: URL(fileURLWithPath: normalized).lastPathComponent,
            path: normalized,
            progress: 0.0,
            status: .idle
        )
        mutate(&folder)
        watchedFolders.append(folder)
        watchedFolders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func bumpProgress(forFilePath path: String, completed: Bool) {
        updateFolder(forFilePath: path) { folder in
            if folder.status == .idle {
                folder.status = .indexing
            }
            let increment = completed ? 0.15 : 0.05
            folder.progress = min(1.0, folder.progress + increment)
            folder.lastModified = Date()
            if folder.progress >= 0.99 && completed {
                folder.status = .complete
                folder.progress = 1.0
            }
        }
    }
    
    private func updateFolder(
        forFilePath filePath: String,
        mutate: (inout WatchedFolder) -> Void
    ) {
        let normalizedFile = (filePath as NSString).standardizingPath
        guard let index = watchedFolders.firstIndex(where: { normalizedFile.hasPrefix($0.path) }) else {
            return
        }
        mutate(&watchedFolders[index])
    }
    
    private func directoryFromTokens() -> String? {
        guard let token = searchTokens.first(where: { $0.kind == .folder }) else {
            return nil
        }
        if let folder = watchedFolders.first(where: { $0.name == token.value }) {
            return folder.path
        }
        return token.value
    }
    
    private func filtersFromTokens(directory: String?) -> [String: String]? {
        if let dir = directory {
            return ["folder": dir]
        }
        return nil
    }
    
    private func handleWatchListError(_ error: APIError) {
        switch error {
        case .serverError(let statusCode, _)
            where statusCode == 404:
            missingWatchedEndpoint = true
            jobsError = nil
        default:
            jobsError = error.localizedDescription
        }
    }
    
    func dismissFolderIssue(_ folder: WatchedFolder) {
        guard let index = watchedFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        watchedFolders[index].lastIssueMessage = nil
        watchedFolders[index].lastIssueDate = nil
        watchedFolders[index].skippedFileCount = 0
    }
    
    // MARK: - Settings helpers
    
    func testBackendConnection() async -> (success: Bool, message: String) {
        do {
            let status = try await apiClient.fetchStatus()
            let jobsCount = status.jobs ?? 0
            return (true, "Connected (\(jobsCount) jobs running)")
        } catch let error as APIError {
            return (false, error.localizedDescription)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Security Bookmarks

    nonisolated func storeSecurityBookmark(for url: URL) {
        let normalized = (url.path as NSString).standardizingPath
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmarkQueue.async(flags: .barrier) { [weak self] in
                self?.securityBookmarks[normalized] = data
                self?.persistBookmarks()
            }
            print("Stored security bookmark for: \(normalized)")
        } catch {
            print("Failed to store bookmark for \(normalized): \(error)")
        }
    }

    nonisolated func withSecurityScopedAccess<T>(for filePath: String, perform: () throws -> T) throws -> T {
        let normalized = (filePath as NSString).standardizingPath
        
        // First try to find an existing bookmark that covers this file
        var bookmarkEntry: (key: String, value: Data)?
        bookmarkQueue.sync {
            bookmarkEntry = securityBookmarks.first(where: { normalized.hasPrefix($0.key) })
        }
        
        if let bookmarkEntry = bookmarkEntry {
            do {
                var isStale = false
                let scopedURL = try URL(resolvingBookmarkData: bookmarkEntry.value, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                // If stale, recreate the bookmark
                if isStale {
                    print("Bookmark is stale for \(bookmarkEntry.key), recreating...")
                    storeSecurityBookmark(for: scopedURL)
                }
                
                let granted = scopedURL.startAccessingSecurityScopedResource()
                defer {
                    if granted {
                        scopedURL.stopAccessingSecurityScopedResource()
                    }
                }
                
                if !granted {
                    print("Failed to start accessing security scoped resource for \(scopedURL.path)")
                    throw BookmarkError.folderUnknown
                }
                
                return try perform()
            } catch {
                print("Error resolving bookmark: \(error)")
                // Remove the invalid bookmark
                bookmarkQueue.async(flags: .barrier) { [weak self] in
                    self?.securityBookmarks.removeValue(forKey: bookmarkEntry.key)
                    self?.persistBookmarks()
                }
            }
        }
        
        // No bookmark found, prompt user for access
        print("No bookmark found for \(normalized), prompting user...")
        try promptForBookmark(for: normalized)
        
        // After prompting, try again with the newly created bookmark
        bookmarkQueue.sync {
            bookmarkEntry = securityBookmarks.first(where: { normalized.hasPrefix($0.key) })
        }
        
        if let bookmarkEntry = bookmarkEntry {
            var isStale = false
            let scopedURL = try URL(resolvingBookmarkData: bookmarkEntry.value, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            let granted = scopedURL.startAccessingSecurityScopedResource()
            defer {
                if granted {
                    scopedURL.stopAccessingSecurityScopedResource()
                }
            }
            return try perform()
        }
        
        // If we still don't have access, throw an error
        print("Failed to obtain security bookmark after prompting")
        throw BookmarkError.folderUnknown
    }

    nonisolated private func persistBookmarks() {
        // This is called from bookmarkQueue.async, so we're already on that queue
        // Just read the bookmarks directly (we're inside the barrier)
        let encoded = securityBookmarks.mapValues { $0.base64EncodedString() }
        UserDefaults.standard.set(encoded, forKey: Self.bookmarksDefaultsKey)
    }
    
    private func loadSecurityBookmarks() {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.bookmarksDefaultsKey) as? [String: String] else {
            securityBookmarks = [:]
            return
        }
        securityBookmarks = stored.reduce(into: [:]) { partialResult, item in
            if let data = Data(base64Encoded: item.value) {
                partialResult[(item.key as NSString).standardizingPath] = data
            }
        }
    }
    
    nonisolated private func promptForBookmark(for path: String) throws {
        // This will be called from main thread, so we can use assumeIsolated
        // Get watched folders info and show panel on main thread
        let result = MainActor.assumeIsolated {
            // Get folder info
            let folderInfo = self.watchedFolders.first(where: { path.hasPrefix(($0.path as NSString).standardizingPath) })
            
            // Create and show panel
            let panel = NSOpenPanel()
            if let folder = folderInfo {
                panel.message = "fileSearchForntend needs access to \(folder.name) to open files."
                panel.directoryURL = URL(fileURLWithPath: folder.path)
            } else {
                // If we can't find a watched folder, try to get the parent directory
                let fileURL = URL(fileURLWithPath: path)
                let parentURL = fileURL.deletingLastPathComponent()
                panel.message = "fileSearchForntend needs access to open this file."
                panel.directoryURL = parentURL
            }
            
            panel.prompt = "Grant Access"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            
            // Show panel and return result
            if panel.runModal() == .OK {
                return panel.url
            } else {
                return nil
            }
        }
        
        // Store bookmark if user selected a folder
        if let url = result {
            storeSecurityBookmark(for: url)
        } else {
            throw BookmarkError.userCancelled
        }
    }
    
    /// Request access to all watched folders that don't have bookmarks yet
    func ensureBookmarksForWatchedFolders() {
        for folder in watchedFolders {
            let normalized = (folder.path as NSString).standardizingPath
            var hasBookmark = false
            bookmarkQueue.sync {
                hasBookmark = securityBookmarks[normalized] != nil
            }
            if !hasBookmark {
                print("Missing bookmark for watched folder: \(folder.path)")
                // We could prompt here, but it's better to wait until the user actually tries to access a file
            }
        }
    }

    // MARK: - Filter Configuration (Backend-Synced)

    /// Refresh filter configuration from backend
    func refreshFilterConfig() async {
        isLoadingFilterConfig = true
        filterConfigError = nil

        defer { isLoadingFilterConfig = false }

        do {
            let config = try await apiClient.fetchFilterConfig()

            // Update local state
            filterMode = config.mode
            blacklistExclude = config.blacklistExclude
            blacklistInclude = config.blacklistInclude
            whitelistInclude = config.whitelistInclude
            whitelistExclude = config.whitelistExclude
            fileFilterEnabled = true

            // Save as the "clean" state for dirty tracking
            savedFilterMode = config.mode
            savedBlacklistExclude = config.blacklistExclude
            savedBlacklistInclude = config.blacklistInclude
            savedWhitelistInclude = config.whitelistInclude
            savedWhitelistExclude = config.whitelistExclude
        } catch let error as APIError {
            filterConfigError = error.localizedDescription
            print("Failed to fetch filter config: \(error)")
        } catch {
            filterConfigError = error.localizedDescription
            print("Failed to fetch filter config: \(error)")
        }
    }

    /// Add a new filter pattern (local only - doesn't save to backend)
    /// Call saveFilterConfig() to persist changes
    func addFilterPattern(_ pattern: String, description: String? = nil) {
        // Determine if it's an include or exclude pattern
        let isNegation = pattern.hasPrefix("!")
        let effectivePattern = isNegation ? String(pattern.dropFirst()) : pattern

        // Add to appropriate mode-specific array
        if filterMode == "blacklist" {
            if isNegation {
                if !blacklistInclude.contains(effectivePattern) {
                    blacklistInclude.append(effectivePattern)
                }
            } else {
                if !blacklistExclude.contains(effectivePattern) {
                    blacklistExclude.append(effectivePattern)
                }
            }
        } else {
            if isNegation {
                if !whitelistExclude.contains(effectivePattern) {
                    whitelistExclude.append(effectivePattern)
                }
            } else {
                if !whitelistInclude.contains(effectivePattern) {
                    whitelistInclude.append(effectivePattern)
                }
            }
        }
    }

    /// Remove a filter pattern (local only - doesn't save to backend)
    /// Call saveFilterConfig() to persist changes
    func removeFilterPattern(_ pattern: FileFilterPattern) {
        let effectivePattern = pattern.effectivePattern

        // Remove from appropriate mode-specific array
        if filterMode == "blacklist" {
            if pattern.isNegation {
                blacklistInclude.removeAll { $0 == effectivePattern }
            } else {
                blacklistExclude.removeAll { $0 == effectivePattern }
            }
        } else {
            if pattern.isNegation {
                whitelistExclude.removeAll { $0 == effectivePattern }
            } else {
                whitelistInclude.removeAll { $0 == effectivePattern }
            }
        }
    }

    /// Save filter configuration changes to backend
    func saveFilterConfig() async {
        isLoadingFilterConfig = true
        filterConfigError = nil

        defer { isLoadingFilterConfig = false }

        do {
            let response = try await apiClient.updateFilterConfig(
                mode: filterMode,
                blacklistExclude: blacklistExclude,
                blacklistInclude: blacklistInclude,
                whitelistInclude: whitelistInclude,
                whitelistExclude: whitelistExclude,
                applyImmediately: true
            )

            if response.success {
                // Update saved state
                savedFilterMode = response.config.mode
                savedBlacklistExclude = response.config.blacklistExclude
                savedBlacklistInclude = response.config.blacklistInclude
                savedWhitelistInclude = response.config.whitelistInclude
                savedWhitelistExclude = response.config.whitelistExclude

                // Sync local state with backend response
                filterMode = response.config.mode
                blacklistExclude = response.config.blacklistExclude
                blacklistInclude = response.config.blacklistInclude
                whitelistInclude = response.config.whitelistInclude
                whitelistExclude = response.config.whitelistExclude
            } else {
                filterConfigError = response.message
            }
        } catch let error as APIError {
            filterConfigError = error.localizedDescription
        } catch {
            filterConfigError = error.localizedDescription
        }
    }

    /// Discard unsaved filter configuration changes
    func discardFilterChanges() {
        filterMode = savedFilterMode
        blacklistExclude = savedBlacklistExclude
        blacklistInclude = savedBlacklistInclude
        whitelistInclude = savedWhitelistInclude
        whitelistExclude = savedWhitelistExclude
        filterConfigError = nil
    }

    /// Reset filter patterns to defaults
    func resetFilterPatternsToDefaults() {
        Task {
            do {
                let response = try await apiClient.resetFilterConfig()
                if response.success {
                    // Update both local and saved state
                    filterMode = response.config.mode
                    blacklistExclude = response.config.blacklistExclude
                    blacklistInclude = response.config.blacklistInclude
                    whitelistInclude = response.config.whitelistInclude
                    whitelistExclude = response.config.whitelistExclude

                    savedFilterMode = response.config.mode
                    savedBlacklistExclude = response.config.blacklistExclude
                    savedBlacklistInclude = response.config.blacklistInclude
                    savedWhitelistInclude = response.config.whitelistInclude
                    savedWhitelistExclude = response.config.whitelistExclude
                } else {
                    filterConfigError = response.message
                }
            } catch let error as APIError {
                filterConfigError = error.localizedDescription
            } catch {
                filterConfigError = error.localizedDescription
            }
        }
    }

    /// Update filter mode (local only - doesn't save to backend)
    /// Call saveFilterConfig() to persist changes
    func updateFilterMode(_ mode: String) {
        filterMode = mode
        // Mode change is now just a local state update
        // Patterns automatically switch via excludePatterns/includePatterns computed properties
    }

    /// Check if a file should be filtered based on current settings
    ///
    /// **Note: Filtering is now handled server-side.**
    /// This method is kept for backward compatibility but uses the backend patterns.
    func shouldFilterFile(filePath: String, filename: String) -> Bool {
        guard fileFilterEnabled else { return false }
        return FileFilterService.shouldFilter(
            filePath: filePath,
            filename: filename,
            patterns: fileFilterPatterns
        )
    }
}
