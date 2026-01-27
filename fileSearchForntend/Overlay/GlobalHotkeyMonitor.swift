//
//  GlobalHotkeyMonitor.swift
//  fileSearchForntend
//
//  Global hotkey listener using NSEvent monitors + Carbon RegisterEventHotKey
//  Combines both approaches for maximum compatibility.
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics

final class GlobalHotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandler: EventHandlerRef?
    private var action: (() -> Void)?
    private var targetKeyCode: UInt16 = 0
    private var targetModifiers: NSEvent.ModifierFlags = []

    private let carbonHotkeyID = EventHotKeyID(signature: OSType(0x46535248), id: 1) // 'FSRH'

    deinit {
        stop()
    }

    /// Check if we have Input Monitoring permission (needed for global monitoring in sandboxed apps)
    /// Note: AXIsProcessTrusted() always returns false in sandboxed apps
    /// For sandboxed apps, use CGPreflightListenEventAccess() instead
    static var hasAccessibilityPermission: Bool {
        // For sandboxed apps, check Input Monitoring permission
        // CGPreflightListenEventAccess works in sandboxed apps
        return CGPreflightListenEventAccess()
    }

    /// Request Input Monitoring permission (shows system dialog)
    /// This is the correct approach for sandboxed apps
    static func requestAccessibilityPermission() {
        // For sandboxed apps, use CGRequestListenEventAccess
        CGRequestListenEventAccess()
    }

    /// Legacy check for non-sandboxed apps
    static var hasLegacyAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }

    /// Legacy request for non-sandboxed apps
    static func requestLegacyAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func update(hotkey: String, action: @escaping () -> Void) {
        stop()

        print("📝 Attempting to register global hotkey: \(hotkey)")

        guard let parsed = parse(hotkey: hotkey) else {
            print("❌ Failed to parse hotkey: \(hotkey)")
            return
        }

        self.action = action
        self.targetKeyCode = parsed.keyCode
        self.targetModifiers = parsed.modifiers

        print("✅ Parsed hotkey - keyCode: \(parsed.keyCode), modifiers: \(parsed.modifiers.rawValue)")

        // Method 1: Try Carbon RegisterEventHotKey (works without accessibility permission)
        let carbonRegistered = registerCarbonHotKey(
            keyCode: UInt32(parsed.keyCode),
            modifiers: carbonModifiers(from: parsed.modifiers)
        )

        if carbonRegistered {
            print("✅ Carbon hotkey registered successfully")
        } else {
            print("⚠️ Carbon hotkey registration failed, falling back to NSEvent monitors")
        }

        // Method 2: Also set up NSEvent monitors as backup
        // Global monitor - catches events when app is NOT focused
        if Self.hasAccessibilityPermission {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
            }
            print("✅ Global NSEvent monitor installed (Input Monitoring permission granted)")
        } else {
            print("⚠️ No Input Monitoring permission - global monitor not installed")
            print("   Go to System Settings > Privacy & Security > Input Monitoring to grant permission")
        }

        // Local monitor - catches events when app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }
        print("✅ Local NSEvent monitor installed")

        print("🎯 Global hotkey ready: \(hotkey)")
    }

    func stop() {
        // Remove NSEvent monitors
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Unregister Carbon hotkey
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonHotKeyRef = nil
        }
        if let handler = carbonEventHandler {
            RemoveEventHandler(handler)
            carbonEventHandler = nil
        }

        action = nil
        print("🛑 Hotkey unregistered")
    }

    // MARK: - NSEvent Handling

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check if this event matches our hotkey
        let eventModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        guard event.keyCode == targetKeyCode,
              eventModifiers == targetModifiers else {
            return false
        }

        print("🎯 Global hotkey triggered via NSEvent!")

        DispatchQueue.main.async { [weak self] in
            self?.action?()
        }

        return true
    }

    // MARK: - Carbon Hotkey (backup method)

    private func registerCarbonHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        // Set up event handler
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

        let handlerCallback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData, let event = event else {
                return OSStatus(eventNotHandledErr)
            }

            let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr, hotKeyID.id == monitor.carbonHotkeyID.id else {
                return OSStatus(eventNotHandledErr)
            }

            print("🎯 Global hotkey triggered via Carbon!")

            DispatchQueue.main.async {
                monitor.action?()
            }

            return noErr
        }

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            handlerCallback,
            1,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &carbonEventHandler
        )

        guard installStatus == noErr else {
            print("❌ Failed to install Carbon event handler: \(installStatus)")
            return false
        }

        // Register the hotkey
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            carbonHotkeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            print("❌ Failed to register Carbon hotkey: \(registerStatus)")
            if registerStatus == -9868 {
                print("   Error -9868: On macOS Sequoia, hotkeys must use Command or Control modifier")
            }
            if let handler = carbonEventHandler {
                RemoveEventHandler(handler)
                carbonEventHandler = nil
            }
            return false
        }

        carbonHotKeyRef = hotKeyRef
        return true
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    // MARK: - Parsing

    private func parse(hotkey: String) -> (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)? {
        let parts = hotkey.lowercased().split(separator: "+")
        guard let last = parts.last else { return nil }

        guard let keyCode = keyCodeFromString(String(last)) else {
            print("Failed to get keycode for: \(last)")
            return nil
        }

        var modifiers: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "command", "cmd":
                modifiers.insert(.command)
            case "option", "opt", "alt":
                modifiers.insert(.option)
            case "control", "ctrl":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            default:
                break
            }
        }

        return (keyCode, modifiers)
    }

    private func keyCodeFromString(_ key: String) -> UInt16? {
        if key == "space" { return UInt16(kVK_Space) }

        let lowercased = key.lowercased()
        switch lowercased {
        case "a": return UInt16(kVK_ANSI_A)
        case "b": return UInt16(kVK_ANSI_B)
        case "c": return UInt16(kVK_ANSI_C)
        case "d": return UInt16(kVK_ANSI_D)
        case "e": return UInt16(kVK_ANSI_E)
        case "f": return UInt16(kVK_ANSI_F)
        case "g": return UInt16(kVK_ANSI_G)
        case "h": return UInt16(kVK_ANSI_H)
        case "i": return UInt16(kVK_ANSI_I)
        case "j": return UInt16(kVK_ANSI_J)
        case "k": return UInt16(kVK_ANSI_K)
        case "l": return UInt16(kVK_ANSI_L)
        case "m": return UInt16(kVK_ANSI_M)
        case "n": return UInt16(kVK_ANSI_N)
        case "o": return UInt16(kVK_ANSI_O)
        case "p": return UInt16(kVK_ANSI_P)
        case "q": return UInt16(kVK_ANSI_Q)
        case "r": return UInt16(kVK_ANSI_R)
        case "s": return UInt16(kVK_ANSI_S)
        case "t": return UInt16(kVK_ANSI_T)
        case "u": return UInt16(kVK_ANSI_U)
        case "v": return UInt16(kVK_ANSI_V)
        case "w": return UInt16(kVK_ANSI_W)
        case "x": return UInt16(kVK_ANSI_X)
        case "y": return UInt16(kVK_ANSI_Y)
        case "z": return UInt16(kVK_ANSI_Z)
        case "0": return UInt16(kVK_ANSI_0)
        case "1": return UInt16(kVK_ANSI_1)
        case "2": return UInt16(kVK_ANSI_2)
        case "3": return UInt16(kVK_ANSI_3)
        case "4": return UInt16(kVK_ANSI_4)
        case "5": return UInt16(kVK_ANSI_5)
        case "6": return UInt16(kVK_ANSI_6)
        case "7": return UInt16(kVK_ANSI_7)
        case "8": return UInt16(kVK_ANSI_8)
        case "9": return UInt16(kVK_ANSI_9)
        default: return nil
        }
    }
}
