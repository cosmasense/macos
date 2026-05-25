//
//  AppModel+Search.swift
//  fileSearchForntend
//
//  Search functionality for main window and popup overlay
//

import Foundation
import OSLog

/// Subsystem-tagged logger so search timing shows up in Console.app
/// under "filesearch" with the "search" category — easy to filter.
/// Each search emits start / success / error / cancel lines with the
/// query, request id, and elapsed ms, so when a search hangs we can
/// correlate the frontend log against the backend's
/// "Search request received" / "Search completed" timing chain.
private let searchLog = Logger(subsystem: "com.filesearch", category: "search")

// MARK: - Main Window Search

extension AppModel {

    /// Builds and executes a search from the current search text and tokens.
    /// Adds the query to recent searches for quick access.
    func performSearch() {
        let query = buildSearchQuery()

        guard !query.isEmpty else { return }

        // Belt-and-suspenders: even if a code path bypasses the UI gate
        // (menu command, scripted test, etc.), we refuse to search while
        // AI setup is still running. Queries launched against a partial
        // index return confusing results and are a common source of
        // "why doesn't search work" bugs.
        if !aiReadyForSearch { return }

        // Add to recent searches
        let newSearch = RecentSearch(
            date: Date(),
            rawQuery: query,
            tokens: searchTokens
        )
        recentSearches.insert(newSearch, at: 0)

        Task {
            await searchFiles(query: query)
        }
    }

    /// Executes a search query against the backend API.
    /// Handles request cancellation for rapid typing scenarios.
    ///
    /// - Parameter query: The search query (may include @folder tokens)
    @MainActor
    func searchFiles(query: String) async {
        let cleanedQuery = stripTokensFromQuery(query)
        let normalizedQuery = cleanedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = scopeFromTokens(searchTokens)
        let directory = directoryFromTokens()
        let pathPattern = globFromTokens(searchTokens)

        // Allow search with empty query if any non-text filter (folder, scope, glob) is set.
        let hasFilter = directory != nil || scope != nil || pathPattern != nil
        guard !normalizedQuery.isEmpty || hasFilter else { return }

        let requestID = UUID()
        activeSearchRequestID = requestID
        lastSearchQuery = query
        searchError = nil

        // Check cache for instant results. The cache key embeds the
        // full filter set — switching scope or glob must not serve a
        // stale list from a previous query.
        let cacheKey = Self.cacheKey(
            query: normalizedQuery.isEmpty ? "*" : normalizedQuery,
            directory: directory,
            scope: scope,
            pathPattern: pathPattern,
            limit: 50
        )
        let now = Date()
        if let entry = searchResultCache[cacheKey],
           now.timeIntervalSince(entry.cachedAt) < Self.searchCacheTTL {
            // Serve cached results immediately
            searchResults = entry.results
            isSearching = false
        } else {
            isSearching = true
            // Keep old results visible until new ones arrive (avoids UI flicker)
        }

        defer {
            if activeSearchRequestID == requestID {
                isSearching = false
                activeSearchRequestID = nil
            }
        }

        let started = Date()
        let shortID = requestID.uuidString.prefix(8)
        searchLog.info("search.start id=\(shortID) q=\(normalizedQuery, privacy: .public) dir=\(directory ?? "-", privacy: .public) ai_ready=\(self.aiReadyForSearch) embedder_ready=\(self.embedderReady)")

        do {
            let response = try await apiClient.search(
                query: normalizedQuery.isEmpty ? "*" : normalizedQuery,
                directory: directory,
                filters: nil,
                limit: 50,
                scope: scope,
                pathPattern: pathPattern
            )

            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            guard activeSearchRequestID == requestID else {
                searchLog.info("search.cancel id=\(shortID) elapsed=\(elapsedMs)ms (superseded)")
                return
            }
            searchResults = response.results
            // Apps now compete with files in the same RRF, so the
            // backend only returns apps that earned a slot in the
            // top-N (or none at all when the query is unrelated to
            // apps). The disableAppsSearch toggle still wins as a
            // hard UI override for users who want apps suppressed.
            searchApps = disableAppsSearch ? [] : (response.apps ?? [])
            cacheSearchResults(key: cacheKey, results: response.results)
            searchLog.info("search.ok id=\(shortID) elapsed=\(elapsedMs)ms results=\(response.results.count) apps=\(self.searchApps.count)")
        } catch let error as APIError {
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            guard activeSearchRequestID == requestID else {
                searchLog.info("search.cancel id=\(shortID) elapsed=\(elapsedMs)ms (superseded)")
                return
            }
            searchLog.error("search.err id=\(shortID) elapsed=\(elapsedMs)ms type=APIError detail=\(error.localizedDescription, privacy: .public)")
            if searchResults.isEmpty {
                searchError = error.localizedDescription
            }
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            guard activeSearchRequestID == requestID else {
                searchLog.info("search.cancel id=\(shortID) elapsed=\(elapsedMs)ms (superseded)")
                return
            }
            searchLog.error("search.err id=\(shortID) elapsed=\(elapsedMs)ms type=\(String(describing: type(of: error))) detail=\(error.localizedDescription, privacy: .public)")
            if searchResults.isEmpty {
                searchError = "An unexpected error occurred: \(error.localizedDescription)"
            }
        }
    }

    /// Builds a stable cache key for a search. Scope and pathPattern
    /// are part of the key so a user toggling between `@Applications`
    /// or a glob filter doesn't see a stale, differently-scoped list.
    nonisolated static func cacheKey(query: String, directory: String?, scope: String? = nil, pathPattern: String? = nil, limit: Int) -> String {
        "\(query)|\(directory ?? "")|\(scope ?? "")|\(pathPattern ?? "")|\(limit)"
    }

    /// Stores results in the cache, evicting the oldest entries if over the cap.
    @MainActor
    internal func cacheSearchResults(key: String, results: [SearchResultItem]) {
        searchResultCache[key] = (results: results, cachedAt: Date())
        if searchResultCache.count > Self.searchCacheMaxEntries {
            // Drop the oldest entry
            if let oldest = searchResultCache.min(by: { $0.value.cachedAt < $1.value.cachedAt }) {
                searchResultCache.removeValue(forKey: oldest.key)
            }
        }
    }

    /// Clears current search results and any error state
    func clearSearchResults() {
        searchResults = []
        searchError = nil
    }

    /// Loads a saved search from history and executes it
    func loadRecentSearch(_ search: RecentSearch) {
        searchTokens = search.tokens

        // Extract text without tokens
        let tokenStrings = search.tokens.map { "@\($0.value)" }
        var text = search.rawQuery
        for tokenStr in tokenStrings {
            text = text.replacingOccurrences(of: tokenStr, with: "")
        }
        searchText = text.trimmingCharacters(in: .whitespaces)

        Task {
            await searchFiles(query: search.rawQuery)
        }
    }

    /// Whether a retry of the last search is possible
    var canRetryLastSearch: Bool {
        guard let query = lastSearchQuery else { return false }
        return !query.isEmpty
    }

    /// Retries the last failed search
    func retryLastSearch() {
        guard canRetryLastSearch, let query = lastSearchQuery else { return }
        Task {
            await searchFiles(query: query)
        }
    }

    // MARK: - Search Query Helpers

    /// Builds a complete search query from tokens and text
    internal func buildSearchQuery() -> String {
        let tokenStrings = searchTokens.map { "@\($0.value)" }
        let components = tokenStrings + [searchText]
        return components.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Removes @-tokens (folder, applicationsOnly, glob) from the
    /// query string so only the human search terms reach the backend.
    /// Each token kind has its own filter field on the API request.
    internal func stripTokensFromQuery(_ query: String) -> String {
        var result = query
        for token in searchTokens {
            result = result.replacingOccurrences(of: "@\(token.value)", with: "")
        }

        // Also remove any remaining @ patterns that look like one of
        // our recognized token forms — watched folders, the literal
        // word "Applications", or a glob (contains * or ?).
        let words = result.split(separator: " ")
        let cleanedWords = words.filter { word in
            if word.hasPrefix("@") {
                let body = String(word.dropFirst())
                if body.isEmpty { return true }
                if body.caseInsensitiveCompare("Applications") == .orderedSame { return false }
                if body.contains("*") || body.contains("?") { return false }
                let isFolder = watchedFolders.contains { $0.name.caseInsensitiveCompare(body) == .orderedSame }
                return !isFolder
            }
            return true
        }
        return cleanedWords.joined(separator: " ")
    }

    /// Extracts directory path from search tokens
    internal func directoryFromTokens() -> String? {
        guard let token = searchTokens.first(where: { $0.kind == .folder }) else {
            return nil
        }
        if let folder = watchedFolders.first(where: { $0.name.caseInsensitiveCompare(token.value) == .orderedSame }) {
            return folder.path
        }
        return token.value
    }

    /// Maps tokens to the backend's `scope` API field. Only honors
    /// `.applicationsOnly` today — file-only is not user-exposed.
    internal func scopeFromTokens(_ tokens: [SearchToken]) -> String? {
        if tokens.contains(where: { $0.kind == .applicationsOnly }) {
            return "applications"
        }
        return nil
    }

    /// Returns the first `.glob` token's value, or nil. Backend
    /// applies it as a SQL LIKE filter on file_path / app_path.
    internal func globFromTokens(_ tokens: [SearchToken]) -> String? {
        tokens.first(where: { $0.kind == .glob })?.value
    }
}

// MARK: - Popup Search (Quick Search Overlay)

extension AppModel {

    /// Executes a search from the popup overlay's current state.
    /// Does not add to recent searches to avoid clutter.
    func performPopupSearch() {
        let query = buildPopupSearchQuery()
        guard !query.isEmpty else { return }

        Task {
            await popupSearchFiles(query: query)
        }
    }

    /// Executes a popup search query against the backend API.
    /// Uses separate state from main window to allow independent searching.
    @MainActor
    func popupSearchFiles(query: String) async {
        let cleanedQuery = stripPopupTokensFromQuery(query)
        let normalizedQuery = cleanedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = scopeFromTokens(popupSearchTokens)
        let directory = popupDirectoryFromTokens()
        let pathPattern = globFromTokens(popupSearchTokens)

        let hasFilter = directory != nil || scope != nil || pathPattern != nil
        guard !normalizedQuery.isEmpty || hasFilter else { return }

        let requestID = UUID()
        activePopupSearchRequestID = requestID
        popupIsSearching = true
        popupSearchError = nil
        // Keep old results visible until new ones arrive (avoids UI flicker)

        defer {
            if activePopupSearchRequestID == requestID {
                popupIsSearching = false
                activePopupSearchRequestID = nil
            }
        }

        do {
            let response = try await apiClient.search(
                query: normalizedQuery.isEmpty ? "*" : normalizedQuery,
                directory: directory,
                filters: nil,
                limit: 50,
                scope: scope,
                pathPattern: pathPattern
            )

            guard activePopupSearchRequestID == requestID else { return }
            popupSearchResults = response.results
            popupSearchApps = disableAppsSearch ? [] : (response.apps ?? [])
        } catch let error as APIError {
            guard activePopupSearchRequestID == requestID else { return }
            popupSearchError = error.localizedDescription
        } catch {
            guard activePopupSearchRequestID == requestID else { return }
            popupSearchError = "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    /// Clears all popup search state
    func clearPopupSearch() {
        popupSearchText = ""
        popupSearchTokens = []
        popupSearchResults = []
        popupSearchError = nil
    }

    // MARK: - Popup Search Helpers

    internal func buildPopupSearchQuery() -> String {
        let tokenStrings = popupSearchTokens.map { "@\($0.value)" }
        let components = tokenStrings + [popupSearchText]
        return components.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    internal func stripPopupTokensFromQuery(_ query: String) -> String {
        var result = query
        for token in popupSearchTokens {
            result = result.replacingOccurrences(of: "@\(token.value)", with: "")
        }

        let words = result.split(separator: " ")
        let cleanedWords = words.filter { word in
            if word.hasPrefix("@") {
                let body = String(word.dropFirst())
                if body.isEmpty { return true }
                if body.caseInsensitiveCompare("Applications") == .orderedSame { return false }
                if body.contains("*") || body.contains("?") { return false }
                let isFolder = watchedFolders.contains { $0.name.caseInsensitiveCompare(body) == .orderedSame }
                return !isFolder
            }
            return true
        }
        return cleanedWords.joined(separator: " ")
    }

    internal func popupDirectoryFromTokens() -> String? {
        for token in popupSearchTokens {
            if case .folder = token.kind {
                if let folder = watchedFolders.first(where: { $0.name.caseInsensitiveCompare(token.value) == .orderedSame }) {
                    return folder.path
                }
            }
        }
        return nil
    }
}
