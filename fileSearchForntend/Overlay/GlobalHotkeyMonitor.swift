//
//  GlobalHotkeyMonitor.swift
//  fileSearchForntend
//
//  Global hotkey listener using Carbon's RegisterEventHotKey API
//  Works in sandboxed apps without special permissions.
//

import AppKit
import Carbon.HIToolbox

// Module-level event handler callback (required for Carbon API)
private func globalHotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData, let event = event else {
        return OSStatus(eventNotHandledErr)
    }
    let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    return monitor.handleHotKeyEvent(event: event)
}

final class GlobalHotkeyMonitor {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var action: (() -> Void)?
    private let hotkeyID = EventHotKeyID(signature: OSType(0x46535248), id: 1) // 'FSRH' in hex

    deinit {
        stop()
    }

    func update(hotkey: String, action: @escaping () -> Void) {
        stop()

        print("📝 Attempting to register global hotkey: \(hotkey)")

        guard let parsed = parse(hotkey: hotkey) else {
            print("❌ Failed to parse hotkey: \(hotkey)")
            return
        }

        print("✅ Parsed hotkey - keyCode: \(parsed.keyCode), modifiers: \(parsed.modifiers)")

        self.action = action

        // Install event handler first
        setupEventHandler()

        // Register the hotkey with the event dispatcher
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            parsed.keyCode,
            parsed.modifiers,
            hotkeyID,
            GetEventDispatcherTarget(),  // Use dispatcher target, not application target
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr, hotKeyRef != nil else {
            print("❌ Failed to register hotkey: \(registerStatus)")
            if registerStatus == -9868 {
                print("   Error -9868: On macOS Sequoia, hotkeys must use Command or Control modifier")
                print("   (Option-only or Shift-only combinations are not allowed)")
            }
            cleanup()
            return
        }

        self.hotKeyRef = hotKeyRef

        print("✅ Global hotkey registered successfully!")
        print("   Press \(hotkey) from any app to trigger")
    }

    func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            print("🛑 Hotkey unregistered")
        }

        cleanup()
    }

    // MARK: - Event Handler Setup

    private func setupEventHandler() {
        guard eventHandler == nil else { return }

        guard let dispatcher = GetEventDispatcherTarget() else {
            print("❌ Failed to get event dispatcher target")
            return
        }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

        let status = InstallEventHandler(
            dispatcher,
            globalHotkeyEventHandler,
            1,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            print("❌ Failed to install event handler: \(status)")
            return
        }

        print("✅ Event handler installed on event dispatcher")
    }

    private func cleanup() {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        action = nil
    }

    // MARK: - Event Handling

    fileprivate func handleHotKeyEvent(event: EventRef) -> OSStatus {
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

        guard status == noErr, hotKeyID.id == self.hotkeyID.id else {
            return OSStatus(eventNotHandledErr)
        }

        print("🎯 Global hotkey triggered!")

        // Execute action on main thread
        if let action = self.action {
            DispatchQueue.main.async {
                action()
            }
        }

        return noErr
    }

    // MARK: - Parsing

    private func parse(hotkey: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = hotkey.split(separator: "+")
        guard let last = parts.last else { return nil }

        // Convert key string to keyCode
        guard let keyCode = keyCodeFromString(String(last)) else {
            print("Failed to get keycode for: \(last)")
            return nil
        }

        // Parse modifiers (Carbon modifier flags)
        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "command":
                modifiers |= UInt32(cmdKey)
            case "option":
                modifiers |= UInt32(optionKey)
            case "control":
                modifiers |= UInt32(controlKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            default:
                break
            }
        }

        return (keyCode, modifiers)
    }

    private func keyCodeFromString(_ key: String) -> UInt32? {
        // Special keys
        if key == "space" {
            return UInt32(kVK_Space)
        }

        // Letter and number keys
        let lowercased = key.lowercased()
        switch lowercased {
        // Letters
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)

        // Numbers
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)

        default:
            return nil
        }
    }
}
