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

    var onShowMainWindow: (() -> Void)?
    var onShowQuickSearch: (() -> Void)?
    var onQuit: (() -> Void)?

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

        setupMenu()
        statusItem?.menu = menu
        print("✅ Status bar item created successfully")
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

    private func setupMenu() {
        menu = NSMenu()

        // Show Main Window
        let showWindowItem = NSMenuItem(
            title: "Show File Search",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        menu?.addItem(showWindowItem)

        // Quick Search
        let quickSearchItem = NSMenuItem(
            title: "Quick Search",
            action: #selector(showQuickSearch),
            keyEquivalent: ""
        )
        quickSearchItem.target = self
        menu?.addItem(quickSearchItem)

        menu?.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit File Search",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)
    }

    @objc private func showMainWindow() {
        onShowMainWindow?()
    }

    @objc private func showQuickSearch() {
        onShowQuickSearch?()
    }

    @objc private func quitApp() {
        onQuit?()
    }
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
