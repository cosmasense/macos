//
//  AppModel+Queue.swift
//  fileSearchForntend
//
//  Queue management: status, items, pause/resume, scheduler
//

import Foundation

/// Treat URLSession cancellations as non-errors. They happen on purpose
/// when a new request replaces an in-flight one (e.g. the queue view
/// swapping tabs) and surfacing them as a "Queue Error: cancelled"
/// dialog scared users into thinking the backend was broken.
private func queueErrorMessage(from error: Error) -> String? {
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
        switch ns.code {
        // Cancelled: happens when a new request supersedes an in-flight one.
        // TimedOut / CannotConnect: backend is busy or restarting; the next
        // poll tick will recover, so don't alarm the user.
        case NSURLErrorCancelled,
             NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet:
            return nil
        default: break
        }
    }
    if error is CancellationError { return nil }
    return error.localizedDescription
}

// MARK: - Queue Status & Items

extension AppModel {

    /// Fetches current queue status from backend (paused state, counts)
    func refreshQueueStatus() async {
        do {
            queueStatus = try await apiClient.fetchQueueStatus()
        } catch {
            queueError = queueErrorMessage(from: error)
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
            queueError = queueErrorMessage(from: error)
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
            queueError = queueErrorMessage(from: error)
        }
    }

    /// Force-resume the queue regardless of who paused it. Used when the
    /// scheduler is the active blocker and the user wants to override its
    /// pause without first manually pausing then resuming.
    func forceResumeQueue() async {
        do {
            _ = try await apiClient.resumeQueue()
            await refreshQueueStatus()
        } catch {
            queueError = queueErrorMessage(from: error)
        }
    }

    /// Removes a single item from the queue
    func removeQueueItem(itemId: String) async {
        do {
            _ = try await apiClient.removeQueueItem(itemId: itemId)
            await refreshQueueItems()
        } catch {
            queueError = queueErrorMessage(from: error)
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
            queueError = queueErrorMessage(from: error)
        }
    }

    /// Fetches list of recently processed files
    func refreshRecentFiles() async {
        do {
            let response = try await apiClient.fetchRecentFiles()
            recentFiles = response.files
        } catch {
            queueError = queueErrorMessage(from: error)
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
            queueError = queueErrorMessage(from: error)
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
            queueError = queueErrorMessage(from: error)
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
            queueError = queueErrorMessage(from: error)
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
        // Bump totalFileCount for the owning folder
        updateFolder(forFilePath: filePath) { folder in
            folder.totalFileCount += 1
        }
        updateFolderProgressFromQueue(forFilePath: filePath)
    }

    /// Tracks when a queue item completes (success or failure)
    internal func trackQueueItemCompleted(filePath: String) {
        let now = Date()
        expireOldProgressItems(now: now)
        if queueProgressItems[filePath] != nil {
            queueProgressItems[filePath]?.completed = true
        }
        // Bump indexedFileCount for the owning folder
        updateFolder(forFilePath: filePath) { folder in
            folder.indexedFileCount += 1
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
