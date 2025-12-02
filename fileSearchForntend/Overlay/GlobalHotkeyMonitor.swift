//
//  GlobalHotkeyMonitor.swift
//  fileSearchForntend
//
//  Lightweight global hotkey listener using NSEvent monitors.
//

import AppKit

final class GlobalHotkeyMonitor {
    private var monitor: Any?
    private var currentHotkey: (mods: NSEvent.ModifierFlags, key: String)?
    private var action: (() -> Void)?

    deinit {
        stop()
    }

    func update(hotkey: String, action: @escaping () -> Void) {
        stop()
        guard let parsed = parse(hotkey: hotkey) else { return }
        currentHotkey = parsed
        self.action = action

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        currentHotkey = nil
        action = nil
    }

    private func handle(event: NSEvent) {
        guard let hotkey = currentHotkey else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyString = keyString(from: event)

        if flags.contains(hotkey.mods) && keyString == hotkey.key {
            action?()
        }
    }

    private func keyString(from event: NSEvent) -> String {
        if event.keyCode == 49 { // space bar
            return "space"
        }
        if let char = event.charactersIgnoringModifiers?.lowercased().first {
            return String(char)
        }
        return ""
    }

    private func parse(hotkey: String) -> (mods: NSEvent.ModifierFlags, key: String)? {
        let parts = hotkey.split(separator: "+")
        guard let last = parts.last else { return nil }
        let key = last == "space" ? "space" : String(last).lowercased()

        var mods: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "command":
                mods.insert(.command)
            case "option":
                mods.insert(.option)
            case "control":
                mods.insert(.control)
            case "shift":
                mods.insert(.shift)
            default:
                break
            }
        }
        return (mods, key)
    }
}
