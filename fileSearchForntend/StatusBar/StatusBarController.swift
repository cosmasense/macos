//
//  StatusBarController.swift
//  fileSearchForntend
//
//  System status bar (menu bar) controller with menu options.
//

import AppKit
import SwiftUI

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    // Existing callbacks
    var onShowMainWindow: (() -> Void)?
    var onShowQuickSearch: (() -> Void)?
    var onQuit: (() -> Void)?

    // Backend management callbacks
    var onStartBackend: (() -> Void)?
    var onStopBackend: (() -> Void)?
    var onRestartBackend: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    // Backend state (triggers menu rebuild on change)
    var isManagedMode: Bool = false { didSet { if oldValue != isManagedMode { rebuildMenu() } } }
    var backendIsRunning: Bool = false { didSet { if oldValue != backendIsRunning { rebuildMenu() } } }
    var ownsProcess: Bool = false { didSet { if oldValue != ownsProcess { rebuildMenu() } } }
    var backendStatusText: String = "" { didSet { if oldValue != backendStatusText { rebuildMenu() } } }
    var updateAvailableText: String? { didSet { if oldValue != updateAvailableText { rebuildMenu() } } }

    func setup() {
        // Ensure we're on main thread for UI operations
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.setup()
            }
            return
        }

        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Use a placeholder SF Symbol icon
            button.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "File Search")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }

        rebuildMenu()
        statusItem?.menu = menu
    }

    func remove() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.remove()
            }
            return
        }

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            menu = nil
        }
    }

    private func rebuildMenu() {
        guard statusItem != nil else { return }

        let newMenu = NSMenu()

        // Show Main Window
        let showWindowItem = NSMenuItem(
            title: "Show File Search",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        newMenu.addItem(showWindowItem)

        // Quick Search
        let quickSearchItem = NSMenuItem(
            title: "Quick Search",
            action: #selector(showQuickSearch),
            keyEquivalent: ""
        )
        quickSearchItem.target = self
        newMenu.addItem(quickSearchItem)

        // Backend section (only if managed mode)
        if isManagedMode {
            newMenu.addItem(NSMenuItem.separator())

            // Status line (disabled info item)
            let statusItem = NSMenuItem(
                title: "Backend: \(backendStatusText)",
                action: nil,
                keyEquivalent: ""
            )
            statusItem.isEnabled = false
            newMenu.addItem(statusItem)

            // Start/Stop/Restart (only when we own the process)
            if ownsProcess {
                if backendIsRunning {
                    let restartItem = NSMenuItem(
                        title: "Restart Backend",
                        action: #selector(restartBackend),
                        keyEquivalent: ""
                    )
                    restartItem.target = self
                    newMenu.addItem(restartItem)

                    let stopItem = NSMenuItem(
                        title: "Stop Backend",
                        action: #selector(stopBackend),
                        keyEquivalent: ""
                    )
                    stopItem.target = self
                    newMenu.addItem(stopItem)
                } else {
                    let startItem = NSMenuItem(
                        title: "Start Backend",
                        action: #selector(startBackend),
                        keyEquivalent: ""
                    )
                    startItem.target = self
                    newMenu.addItem(startItem)
                }
            }

            // Update available
            if let updateText = updateAvailableText {
                let updateItem = NSMenuItem(
                    title: updateText,
                    action: #selector(checkForUpdates),
                    keyEquivalent: ""
                )
                updateItem.target = self
                updateItem.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: "Update")
                newMenu.addItem(updateItem)
            }
        }

        newMenu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit File Search",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        newMenu.addItem(quitItem)

        menu = newMenu
        self.statusItem?.menu = newMenu
    }

    @objc private func showMainWindow() {
        onShowMainWindow?()
    }

    @objc private func showQuickSearch() {
        onShowQuickSearch?()
    }

    @objc private func startBackend() {
        onStartBackend?()
    }

    @objc private func stopBackend() {
        onStopBackend?()
    }

    @objc private func restartBackend() {
        onRestartBackend?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func quitApp() {
        onQuit?()
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let visibilityModeChanged = Notification.Name("visibilityModeChanged")
}

// MARK: - App Visibility Mode

enum AppVisibilityMode: String, CaseIterable, Identifiable {
    case dockOnly = "Dock Only"
    case menuBarOnly = "Menu Bar Only"
    case both = "Both Dock and Menu Bar"

    var id: String { rawValue }

    var showInDock: Bool {
        switch self {
        case .dockOnly, .both: return true
        case .menuBarOnly: return false
        }
    }

    var showInMenuBar: Bool {
        switch self {
        case .menuBarOnly, .both: return true
        case .dockOnly: return false
        }
    }
}
