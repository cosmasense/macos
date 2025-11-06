//
//  AppModel.swift
//  fileSearchForntend
//
//  Main app state management using @Observable
//

import Foundation
import Combine

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case jobs = "Jobs"
    case settings = "Settings"

    var id: String { rawValue }
}

enum AppError: LocalizedError {
    case invalidFolderPath
    case folderAlreadyWatched
    case fileSystemPermissionDenied
    case backendConnectionFailed
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .invalidFolderPath:
            return "The selected path is not a valid folder"
        case .folderAlreadyWatched:
            return "This folder is already being watched"
        case .fileSystemPermissionDenied:
            return "Permission denied to access this folder"
        case .backendConnectionFailed:
            return "Failed to connect to backend service"
        case .unknownError(let message):
            return message
        }
    }
}

@Observable
class AppModel {
    // Navigation
    var selection: SidebarItem? = .home

    // Data
    var watchedFolders: [WatchedFolder] = []
    var recentSearches: [RecentSearch] = []

    // Search state
    var searchText: String = ""
    var searchTokens: [SearchToken] = []
    var searchResults: [SearchResultItem] = []
    var isSearching: Bool = false
    var searchError: String?

    // API Client
    private let apiClient = APIClient.shared

    // Error handling
    var lastError: AppError?
    var showError: Bool = false

    // Progress simulation timer (replace with real backend connection later)
    private var progressTimer: AnyCancellable?

    init() {
        // Seed with sample data for development
        watchedFolders = [
            WatchedFolder(
                name: "Documents",
                path: "/Users/you/Documents",
                progress: 0.42,
                status: .indexing
            ),
            WatchedFolder(
                name: "Photos",
                path: "/Users/you/Pictures/Photos",
                progress: 0.91,
                status: .indexing
            )
        ]

        // Simulate progress updates (replace with real WebSocket/SSE later)
        startProgressSimulation()
    }

    // MARK: - Folder Management

    func addFolder(url: URL) {
        // Validate folder path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            lastError = .invalidFolderPath
            showError = true
            return
        }

        // Check if folder is already being watched
        if watchedFolders.contains(where: { $0.path == url.path }) {
            lastError = .folderAlreadyWatched
            showError = true
            return
        }

        // Check for read permissions
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            lastError = .fileSystemPermissionDenied
            showError = true
            return
        }

        let name = url.lastPathComponent
        let newFolder = WatchedFolder(
            name: name,
            path: url.path,
            progress: 0.0,
            status: .indexing
        )
        watchedFolders.append(newFolder)
        // TODO: POST to backend /watched
    }

    func removeFolder(_ folder: WatchedFolder) {
        watchedFolders.removeAll { $0.id == folder.id }
        // TODO: DELETE to backend /watched/:id
        // Note: Backend errors should be handled when integrated
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
        isSearching = true
        searchError = nil
        searchResults = []
        
        do {
            // Extract directory from tokens if present
            let directory = searchTokens.first(where: { $0.kind == .folder })?.value
            
            // Build filters from tokens if needed
            let filters: [String: String]? = {
                if let dir = directory {
                    return ["folder": dir]
                }
                return nil
            }()
            
            let response: SearchResponse
            if let filters = filters {
                response = try await apiClient.search(
                    query: query,
                    filters: filters,
                    limit: 50,
                    directory: directory
                )
            } else {
                response = try await apiClient.search(
                    query: query,
                    limit: 50,
                    directory: directory
                )
            }
            
            searchResults = response.results
            isSearching = false
        } catch let error as APIError {
            searchError = error.localizedDescription
            isSearching = false
        } catch {
            searchError = "An unexpected error occurred: \(error.localizedDescription)"
            isSearching = false
        }
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

    // MARK: - Progress Simulation

    private func startProgressSimulation() {
        progressTimer = Timer.publish(every: 1.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                for i in self.watchedFolders.indices {
                    if self.watchedFolders[i].status == .indexing {
                        self.watchedFolders[i].progress = min(1.0, self.watchedFolders[i].progress + 0.03)
                        if self.watchedFolders[i].progress >= 1.0 {
                            self.watchedFolders[i].status = .complete
                        }
                    }
                }
            }
    }
}
