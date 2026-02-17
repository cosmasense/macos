//
//  AppModel+Queue.swift
//  fileSearchForntend
//
//  Queue management: status, items, pause/resume, scheduler
//

import Foundation

// MARK: - Queue Status & Items

extension AppModel {

    /// Fetches current queue status from backend (paused state, counts)
    func refreshQueueStatus() async {
        do {
            queueStatus = try await apiClient.fetchQueueStatus()
        } catch {
            queueError = error.localizedDescription
        }
    }

    /// Fetches paginated list of queue items
    func refreshQueueItems() async {
        isLoadingQueue = true
        defer { isLoadingQueue = false }

        do {
            let response = try await apiClient.fetchQueueItems()
            queueItems = response.items
            queueTotalCount = response.totalCount
            queueError = nil
        } catch {
            queueError = error.localizedDescription
        }
    }

    /// Toggles queue between paused and running state
    func toggleQueuePause() async {
        guard let status = queueStatus else { return }
        do {
            if status.manuallyPaused {
                _ = try await apiClient.resumeQueue()
            } else {
                _ = try await apiClient.pauseQueue()
            }
            await refreshQueueStatus()
        } catch {
            queueError = error.localizedDescription
        }
    }

    /// Removes a single item from the queue
    func removeQueueItem(itemId: String) async {
        do {
            _ = try await apiClient.removeQueueItem(itemId: itemId)
            await refreshQueueItems()
        } catch {
            queueError = error.localizedDescription
        }
    }
}

// MARK: - Failed & Recent Files

extension AppModel {

    /// Fetches list of files that failed processing
    func refreshFailedFiles() async {
        do {
            let response = try await apiClient.fetchFailedFiles()
            failedFiles = response.files
        } catch {
            queueError = error.localizedDescription
        }
    }

    /// Fetches list of recently processed files
    func refreshRecentFiles() async {
        do {
            let response = try await apiClient.fetchRecentFiles()
            recentFiles = response.files
        } catch {
            queueError = error.localizedDescription
        }
    }

    /// Re-queues a failed file for reprocessing
    func reindexFile(filePath: String) async {
        // Optimistic UI update
        failedFiles.removeAll { $0.filePath == filePath }

        do {
            _ = try await apiClient.reindexFile(filePath: filePath)
            await refreshQueueItems()
        } catch {
            queueError = error.localizedDescription
            // Revert optimistic update
            await refreshFailedFiles()
        }
    }
}

// MARK: - Scheduler Configuration

extension AppModel {

    /// Fetches current scheduler configuration
    func refreshSchedulerConfig() async {
        do {
            schedulerConfig = try await apiClient.fetchScheduler()
        } catch {
            queueError = error.localizedDescription
        }
    }

    /// Updates scheduler configuration
    ///
    /// - Parameters:
    ///   - enabled: Whether scheduler is active
    ///   - combineMode: "ALL" (all rules must pass) or "ANY" (any rule passes)
    ///   - checkIntervalSeconds: How often to check rules
    ///   - rules: List of scheduler rules
    func updateSchedulerConfig(
        enabled: Bool? = nil,
        combineMode: String? = nil,
        checkIntervalSeconds: Int? = nil,
        rules: [SchedulerRuleRequest]? = nil
    ) async {
        do {
            schedulerConfig = try await apiClient.updateScheduler(
                enabled: enabled,
                combineMode: combineMode,
                checkIntervalSeconds: checkIntervalSeconds,
                rules: rules
            )
        } catch {
            queueError = error.localizedDescription
        }
    }
}

// MARK: - Queue Progress Tracking

extension AppModel {

    /// Tracks when a queue item is added for progress calculation
    internal func trackQueueItemAdded(filePath: String) {
        let now = Date()
        expireOldProgressItems(now: now)
        queueProgressItems[filePath] = (addedAt: now, completed: false)
        updateFolderProgressFromQueue(forFilePath: filePath)
    }

    /// Tracks when a queue item completes (success or failure)
    internal func trackQueueItemCompleted(filePath: String) {
        let now = Date()
        expireOldProgressItems(now: now)
        if queueProgressItems[filePath] != nil {
            queueProgressItems[filePath]?.completed = true
        }
        updateFolderProgressFromQueue(forFilePath: filePath)
    }

    /// Tracks when a queue item is removed
    internal func trackQueueItemRemoved(filePath: String) {
        queueProgressItems.removeValue(forKey: filePath)
        let now = Date()
        expireOldProgressItems(now: now)
        updateFolderProgressFromQueue(forFilePath: filePath)
    }

    /// Removes completed items older than the progress window (30 minutes)
    internal func expireOldProgressItems(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.progressWindowSeconds)
        let expired = queueProgressItems.filter { $0.value.addedAt < cutoff && $0.value.completed }
        for key in expired.keys {
            queueProgressItems.removeValue(forKey: key)
        }
    }

    /// Updates folder progress based on queue item completion ratio
    internal func updateFolderProgressFromQueue(forFilePath filePath: String) {
        let normalizedFile = (filePath as NSString).standardizingPath
        guard let folderIndex = watchedFolders.firstIndex(where: { normalizedFile.hasPrefix($0.path) }) else {
            return
        }
        let folderPath = watchedFolders[folderIndex].path

        // Count items belonging to this folder
        let folderItems = queueProgressItems.filter { ($0.key as NSString).standardizingPath.hasPrefix(folderPath) }
        let total = folderItems.count
        let completed = folderItems.values.filter(\.completed).count

        guard total > 0 else { return }

        let progress = Double(completed) / Double(total)
        watchedFolders[folderIndex].progress = progress
        watchedFolders[folderIndex].lastModified = Date()

        if progress >= 1.0 {
            watchedFolders[folderIndex].status = .complete
        } else if watchedFolders[folderIndex].status != .paused {
            watchedFolders[folderIndex].status = .indexing
        }
    }
}
