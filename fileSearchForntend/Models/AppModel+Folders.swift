//
//  AppModel+Folders.swift
//  fileSearchForntend
//
//  Watched folder management and security-scoped bookmarks
//

import Foundation
import AppKit

// MARK: - Folder Management

extension AppModel {

    /// Adds a new folder to watch for indexing
    ///
    /// - Parameter url: The folder URL selected by the user
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

    /// Removes a folder from the watch list
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
                    // Optimistic UI update
                    watchedFolders.removeAll { $0.id == folder.id }
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

    /// Triggers a re-index of all files in the folder
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

    /// Fetches the current list of watched folders from the backend
    func refreshWatchedFolders() async {
        isLoadingWatchedFolders = true
        defer { isLoadingWatchedFolders = false }

        do {
            let response = try await apiClient.fetchWatchJobs()
            missingWatchedEndpoint = false

            // Merge with existing state to preserve SSE-driven progress
            var merged: [WatchedFolder] = []
            for job in response.jobs {
                let newFolder = WatchedFolder(response: job)
                if let existing = watchedFolders.first(where: { $0.path == newFolder.path }) {
                    // Keep existing SSE-driven state, update backend metadata
                    var updated = existing
                    updated.backendID = newFolder.backendID
                    updated.recursive = newFolder.recursive
                    updated.filePattern = newFolder.filePattern
                    merged.append(updated)
                } else {
                    merged.append(newFolder)
                }
            }
            watchedFolders = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch let error as APIError {
            handleWatchListError(error)
        } catch {
            jobsError = "Unable to load watched folders: \(error.localizedDescription)"
        }
    }

    /// Dismisses the issue banner for a folder
    func dismissFolderIssue(_ folder: WatchedFolder) {
        guard let index = watchedFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        watchedFolders[index].lastIssueMessage = nil
        watchedFolders[index].lastIssueDate = nil
        watchedFolders[index].skippedFileCount = 0
    }

    // MARK: - Folder Update Helpers

    /// Upserts a folder entry, creating if it doesn't exist
    internal func upsertFolder(
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

    /// Updates a folder based on a file path within it
    internal func updateFolder(
        forFilePath filePath: String,
        mutate: (inout WatchedFolder) -> Void
    ) {
        let normalizedFile = (filePath as NSString).standardizingPath
        guard let index = watchedFolders.firstIndex(where: { normalizedFile.hasPrefix($0.path) }) else {
            return
        }
        mutate(&watchedFolders[index])
    }

    /// Increments progress for a file being processed
    internal func bumpProgress(forFilePath path: String, completed: Bool) {
        let normalizedFile = (path as NSString).standardizingPath

        // If queue-based progress is active for this folder, use that instead
        if let folderIndex = watchedFolders.firstIndex(where: { normalizedFile.hasPrefix($0.path) }) {
            let folderPath = watchedFolders[folderIndex].path
            let hasQueueItems = queueProgressItems.contains { ($0.key as NSString).standardizingPath.hasPrefix(folderPath) }
            if hasQueueItems {
                // Queue tracking is more accurate - just ensure status is indexing
                if watchedFolders[folderIndex].status == .idle {
                    watchedFolders[folderIndex].status = .indexing
                }
                watchedFolders[folderIndex].lastModified = Date()
                return
            }
        }

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

    internal func handleWatchListError(_ error: APIError) {
        switch error {
        case .serverError(let statusCode, _) where statusCode == 404:
            missingWatchedEndpoint = true
            jobsError = nil
        default:
            jobsError = error.localizedDescription
        }
    }
}

// MARK: - Security Scoped Bookmarks

extension AppModel {

    /// Stores a security-scoped bookmark for sandboxed file access
    nonisolated func storeSecurityBookmark(for url: URL) {
        let normalized = (url.path as NSString).standardizingPath
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarkQueue.async(flags: .barrier) { [weak self] in
                self?.securityBookmarks[normalized] = data
                self?.persistBookmarks()
            }
            #if DEBUG
            print("Stored security bookmark for: \(normalized)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to store bookmark for \(normalized): \(error)")
            #endif
        }
    }

    /// Executes a closure with security-scoped access to a file
    ///
    /// - Parameters:
    ///   - filePath: The file path to access
    ///   - perform: The closure to execute with access
    /// - Throws: `BookmarkError` if access cannot be obtained
    nonisolated func withSecurityScopedAccess<T>(for filePath: String, perform: () throws -> T) throws -> T {
        let normalized = (filePath as NSString).standardizingPath

        // Try to find an existing bookmark covering this file
        var bookmarkEntry: (key: String, value: Data)?
        bookmarkQueue.sync {
            bookmarkEntry = securityBookmarks.first(where: { normalized.hasPrefix($0.key) })
        }

        if let bookmarkEntry = bookmarkEntry {
            do {
                var isStale = false
                let scopedURL = try URL(
                    resolvingBookmarkData: bookmarkEntry.value,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    #if DEBUG
                    print("Bookmark is stale for \(bookmarkEntry.key), recreating...")
                    #endif
                    storeSecurityBookmark(for: scopedURL)
                }

                let granted = scopedURL.startAccessingSecurityScopedResource()
                defer {
                    if granted {
                        scopedURL.stopAccessingSecurityScopedResource()
                    }
                }

                if !granted {
                    #if DEBUG
                    print("Failed to start accessing security scoped resource for \(scopedURL.path)")
                    #endif
                    throw BookmarkError.folderUnknown
                }

                return try perform()
            } catch {
                #if DEBUG
                print("Error resolving bookmark: \(error)")
                #endif
                // Remove invalid bookmark
                bookmarkQueue.async(flags: .barrier) { [weak self] in
                    self?.securityBookmarks.removeValue(forKey: bookmarkEntry.key)
                    self?.persistBookmarks()
                }
            }
        }

        // No bookmark found, prompt user
        #if DEBUG
        print("No bookmark found for \(normalized), prompting user...")
        #endif
        try promptForBookmark(for: normalized)

        // Try again with newly created bookmark
        bookmarkQueue.sync {
            bookmarkEntry = securityBookmarks.first(where: { normalized.hasPrefix($0.key) })
        }

        if let bookmarkEntry = bookmarkEntry {
            var isStale = false
            let scopedURL = try URL(
                resolvingBookmarkData: bookmarkEntry.value,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let granted = scopedURL.startAccessingSecurityScopedResource()
            defer {
                if granted {
                    scopedURL.stopAccessingSecurityScopedResource()
                }
            }
            return try perform()
        }

        #if DEBUG
        print("Failed to obtain security bookmark after prompting")
        #endif
        throw BookmarkError.folderUnknown
    }

    nonisolated internal func persistBookmarks() {
        let encoded = securityBookmarks.mapValues { $0.base64EncodedString() }
        UserDefaults.standard.set(encoded, forKey: Self.bookmarksDefaultsKey)
    }

    internal func loadSecurityBookmarks() {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.bookmarksDefaultsKey) as? [String: String] else {
            securityBookmarks = [:]
            return
        }
        securityBookmarks = stored.reduce(into: [:]) { result, item in
            if let data = Data(base64Encoded: item.value) {
                result[(item.key as NSString).standardizingPath] = data
            }
        }
    }

    nonisolated internal func promptForBookmark(for path: String) throws {
        let result = MainActor.assumeIsolated {
            let folderInfo = self.watchedFolders.first(where: { path.hasPrefix(($0.path as NSString).standardizingPath) })

            let panel = NSOpenPanel()
            if let folder = folderInfo {
                panel.message = "fileSearchForntend needs access to \(folder.name) to open files."
                panel.directoryURL = URL(fileURLWithPath: folder.path)
            } else {
                let fileURL = URL(fileURLWithPath: path)
                let parentURL = fileURL.deletingLastPathComponent()
                panel.message = "fileSearchForntend needs access to open this file."
                panel.directoryURL = parentURL
            }

            panel.prompt = "Grant Access"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false

            if panel.runModal() == .OK {
                return panel.url
            } else {
                return nil
            }
        }

        if let url = result {
            storeSecurityBookmark(for: url)
        } else {
            throw BookmarkError.userCancelled
        }
    }

    /// Checks and logs which watched folders are missing bookmarks
    func ensureBookmarksForWatchedFolders() {
        for folder in watchedFolders {
            let normalized = (folder.path as NSString).standardizingPath
            var hasBookmark = false
            bookmarkQueue.sync {
                hasBookmark = securityBookmarks[normalized] != nil
            }
            if !hasBookmark {
                #if DEBUG
                print("Missing bookmark for watched folder: \(folder.path)")
                #endif
            }
        }
    }
}
