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

    /// Batched version of ``trackQueueItemAdded`` for QUEUE_BATCH_ADDED
    /// SSE events that carry hundreds of paths in a single payload.
    ///
    /// The per-path version mutates ``watchedFolders[i].totalFileCount``
    /// once *per path*, so a single 500-path SSE event triggered 500
    /// SwiftUI invalidations of the watched-folders array. During a
    /// fresh-folder discovery sweep the backend coalesces ~5 events/s,
    /// each ~400 paths — that's 2k @Observable mutations/sec landing on
    /// the main run loop. We measured a 150 s main-thread hang from
    /// this in practice (see temp/log.md, lines 1075→1907).
    ///
    /// This batched path: group paths by owning folder, mutate each
    /// folder's counters exactly once, then refresh progress once per
    /// folder. One 500-path event now produces O(folders) mutations
    /// instead of O(paths).
    internal func trackQueueItemsAddedBatch(filePaths: [String]) {
        guard !filePaths.isEmpty else { return }
        let now = Date()
        expireOldProgressItems(now: now)

        var deltaByFolderIndex: [Int: Int] = [:]
        for fp in filePaths {
            queueProgressItems[fp] = (addedAt: now, completed: false)
            let normalized = (fp as NSString).standardizingPath
            if let idx = watchedFolders.firstIndex(where: { normalized.hasPrefix($0.path) }) {
                deltaByFolderIndex[idx, default: 0] += 1
            }
        }

        for (idx, delta) in deltaByFolderIndex {
            watchedFolders[idx].totalFileCount += delta
            // One progress update per folder per batch.
            let total = watchedFolders[idx].totalFileCount
            let completed = watchedFolders[idx].indexedFileCount
            if total > 0 {
                watchedFolders[idx].progress = min(1.0, Double(completed) / Double(total))
            }
            watchedFolders[idx].lastModified = now
            if watchedFolders[idx].progress >= 1.0 {
                watchedFolders[idx].status = .complete
            } else if watchedFolders[idx].status != .paused {
                watchedFolders[idx].status = .indexing
            }
        }
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

    /// Updates folder progress based on queue item completion ratio.
    ///
    /// Performance note: this is called from `handleBackend(event:)` on
    /// the main actor for every queue_item_added / completed / removed
    /// event. The previous implementation did
    /// `queueProgressItems.filter { $0.key.standardizingPath.hasPrefix(folderPath) }`
    /// which is O(queueSize) per event with Unicode-grapheme `hasPrefix`
    /// comparisons. Under a single batched-enqueue burst (442 paths in
    /// one queue_batch_added), 442 × queueSize grapheme comparisons
    /// produced a 2.9s main-thread hang the watchdog caught at startup.
    ///
    /// The fix uses the per-folder counters that ``trackQueueItemAdded``
    /// and ``trackQueueItemCompleted`` already maintain in
    /// ``WatchedFolder.totalFileCount`` / ``indexedFileCount``. Progress
    /// is total/completed read directly off the folder, which is O(F)
    /// in the number of watched folders (typically < 10) and constant-
    /// time per event.
    internal func updateFolderProgressFromQueue(forFilePath filePath: String) {
        let normalizedFile = (filePath as NSString).standardizingPath
        guard let folderIndex = watchedFolders.firstIndex(where: { normalizedFile.hasPrefix($0.path) }) else {
            return
        }

        let total = watchedFolders[folderIndex].totalFileCount
        let completed = watchedFolders[folderIndex].indexedFileCount
        guard total > 0 else { return }

        let progress = min(1.0, Double(completed) / Double(total))
        watchedFolders[folderIndex].progress = progress
        watchedFolders[folderIndex].lastModified = Date()

        if progress >= 1.0 {
            watchedFolders[folderIndex].status = .complete
        } else if watchedFolders[folderIndex].status != .paused {
            watchedFolders[folderIndex].status = .indexing
        }
    }
}
