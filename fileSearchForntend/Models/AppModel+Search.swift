//
//  AppModel+Search.swift
//  fileSearchForntend
//
//  Search functionality for main window and popup overlay
//

import Foundation

// MARK: - Main Window Search

extension AppModel {

    /// Builds and executes a search from the current search text and tokens.
    /// Adds the query to recent searches for quick access.
    func performSearch() {
        let query = buildSearchQuery()

        guard !query.isEmpty else { return }

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
        let directory = directoryFromTokens()

        // Allow search with empty query if directory filter is set
        guard !normalizedQuery.isEmpty || directory != nil else { return }

        let requestID = UUID()
        activeSearchRequestID = requestID
        lastSearchQuery = query
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

    /// Removes @folder tokens from the query string
    internal func stripTokensFromQuery(_ query: String) -> String {
        var result = query
        for token in searchTokens {
            result = result.replacingOccurrences(of: "@\(token.value)", with: "")
        }

        // Also remove any remaining @ patterns matching watched folders
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

    /// Extracts directory path from search tokens
    internal func directoryFromTokens() -> String? {
        guard let token = searchTokens.first(where: { $0.kind == .folder }) else {
            return nil
        }
        if let folder = watchedFolders.first(where: { $0.name == token.value }) {
            return folder.path
        }
        return token.value
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
        let directory = popupDirectoryFromTokens()

        guard !normalizedQuery.isEmpty || directory != nil else { return }

        let requestID = UUID()
        activePopupSearchRequestID = requestID
        popupIsSearching = true
        popupSearchError = nil
        popupSearchResults = []

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
                limit: 50
            )

            guard activePopupSearchRequestID == requestID else { return }
            popupSearchResults = response.results
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
                let folderName = String(word.dropFirst())
                return !watchedFolders.contains { $0.name.caseInsensitiveCompare(folderName) == .orderedSame }
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
