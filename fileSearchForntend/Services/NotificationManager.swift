//
//  NotificationManager.swift
//  fileSearchForntend
//
//  Thin wrapper around UNUserNotificationCenter. Sends Banner-style
//  notifications when index status changes (start / pause / done) and
//  when an app or backend update is available.
//
//  Auth model: notifications are best-effort. We request authorization
//  once on first use, but if the user denies it the rest of the app
//  must keep working. Every send path must therefore be idempotent and
//  safe to call before the user has answered the prompt.
//

import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// Persistence key for "user toggled notifications off in Settings".
    /// We respect this even if the system-level permission is granted —
    /// it's the user's escape hatch from notifications they didn't want
    /// without forcing them into System Settings.
    static let userPreferenceKey = "notificationsEnabled"

    private let center = UNUserNotificationCenter.current()
    /// Cache of authorization state so we don't re-prompt on every send.
    /// Refreshed lazily.
    private var authorizationStatus: UNAuthorizationStatus?

    /// Re-fired notifications coalesce on this id so a queue that
    /// briefly pauses + resumes doesn't spam the user with two banners
    /// 50ms apart. UNUserNotificationCenter overwrites a delivered
    /// notification with the same identifier rather than stacking it.
    private enum Identifier {
        static let queueStart = "cosma.indexing.start"
        static let queuePause = "cosma.indexing.pause"
        static let queueDone = "cosma.indexing.done"
        static let appUpdate = "cosma.update.app"
        static let backendUpdate = "cosma.update.backend"
    }

    private init() {}

    // MARK: - Authorization

    /// Returns `true` when the user has granted Banner permission AND
    /// hasn't disabled notifications in our own Settings UI. Refreshes
    /// the cache on every call (cheap — UNUserNotificationCenter caches
    /// internally).
    func isAuthorized() async -> Bool {
        let userPref = UserDefaults.standard.object(forKey: Self.userPreferenceKey) as? Bool ?? true
        guard userPref else { return false }
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Ask the system for permission. Safe to call multiple times — the
    /// system silently no-ops after the first answer. Returns the
    /// granted state (true if the user is OK with banners).
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        // Only prompt once: if we already have a definitive answer,
        // honor it and skip the system dialog.
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            authorizationStatus = settings.authorizationStatus
            return true
        case .denied:
            authorizationStatus = .denied
            return false
        case .notDetermined, .ephemeral:
            break
        @unknown default:
            break
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorizationStatus = granted ? .authorized : .denied
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Indexing Notifications

    func notifyIndexingStarted(folderName: String?) {
        let body: String
        if let folderName, !folderName.isEmpty {
            body = "Started indexing \(folderName)."
        } else {
            body = "Indexing started."
        }
        send(
            id: Identifier.queueStart,
            title: "Cosma Sense",
            body: body
        )
    }

    func notifyIndexingPaused(reason: String? = nil) {
        let body: String
        if let reason, !reason.isEmpty {
            body = "Indexing paused — \(reason)."
        } else {
            body = "Indexing paused."
        }
        send(
            id: Identifier.queuePause,
            title: "Cosma Sense",
            body: body
        )
    }

    func notifyIndexingComplete(filesIndexed: Int? = nil) {
        let body: String
        if let count = filesIndexed, count > 0 {
            body = "Indexing complete. \(count) file\(count == 1 ? "" : "s") ready to search."
        } else {
            body = "Indexing complete."
        }
        send(
            id: Identifier.queueDone,
            title: "Cosma Sense",
            body: body
        )
    }

    // MARK: - Update Notifications

    func notifyAppUpdateAvailable(version: String) {
        send(
            id: Identifier.appUpdate,
            title: "Cosma Sense Update Available",
            body: "Version \(version) is ready. Open the app to install."
        )
    }

    func notifyBackendUpdateReady(downloadedVersion: String) {
        send(
            id: Identifier.backendUpdate,
            title: "Backend Update Ready",
            body: "Restart Cosma Sense to apply v\(downloadedVersion)."
        )
    }

    // MARK: - Internals

    private func send(id: String, title: String, body: String) {
        Task { @MainActor in
            guard await isAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil
            // Trigger immediately. nil trigger = "deliver now."
            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
            } catch {
                // Best-effort; never escalate to UI.
            }
        }
    }
}
