//
//  GlobalHotkeyMonitor.swift
//  fileSearchForntend
//
//  Global hotkey listener using CGEventTap for true system-wide capture
//  (requires Accessibility permission).
//

import AppKit
import Carbon.HIToolbox

final class GlobalHotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentHotkey: (keyCode: CGKeyCode, mods: CGEventFlags)?
    private var action: (() -> Void)?
    private let queue = DispatchQueue(label: "com.filesearch.hotkey", qos: .userInteractive)

    deinit {
        stop()
    }

    func update(hotkey: String, action: @escaping () -> Void) {
        stop()
        
        print("📝 Attempting to register hotkey: \(hotkey)")
        
        guard ensureAccessibilityPermission() else {
            print("❌ Accessibility permission not granted!")
            print("   Go to System Settings > Privacy & Security > Accessibility")
            return
        }
        
        print("✅ Accessibility permission granted")
        
        guard let parsed = parse(hotkey: hotkey) else { 
            print("❌ Failed to parse hotkey: \(hotkey)")
            return 
        }
        
        print("✅ Parsed hotkey - keyCode: \(parsed.keyCode), mods: \(parsed.mods.rawValue)")
        
        queue.sync {
            self.currentHotkey = parsed
            self.action = action
        }
        
        // Create event tap for key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap!")
            print("   This usually means Accessibility permission is not granted")
            print("   Go to System Settings > Privacy & Security > Accessibility")
            print("   And make sure your app is checked")
            return
        }
        
        print("✅ Event tap created successfully")
        
        eventTap = tap
        
        // Add to run loop on main thread
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        
        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        print("✅ Global hotkey registered and enabled!")
        print("   Press \(hotkey) from any app to trigger")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                runLoopSource = nil
            }
            
            eventTap = nil
        }
        
        queue.sync {
            currentHotkey = nil
            action = nil
        }
    }

    func ensureAccessibilityPermission(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the tap is disabled, re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("⚠️ Event tap disabled (type: \(type)), re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        // Get current hotkey and action safely
        var matchedHotkey: (keyCode: CGKeyCode, mods: CGEventFlags)?
        var actionToExecute: (() -> Void)?
        
        queue.sync {
            matchedHotkey = self.currentHotkey
            actionToExecute = self.action
        }
        
        guard let hotkey = matchedHotkey else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        
        // Debug: print every key press (comment out after testing)
        // print("Key pressed: code=\(keyCode), flags=\(flags.rawValue)")
        
        // Check if this matches our hotkey
        if CGKeyCode(keyCode) == hotkey.keyCode && flags == hotkey.mods {
            print("🎯 Hotkey matched! Executing action...")
            
            // Execute action on main thread
            if let action = actionToExecute {
                DispatchQueue.main.async {
                    action()
                }
            }
            // Consume the event so it doesn't propagate
            return nil
        }
        
        // Pass through other events
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Parsing
    
    private func parse(hotkey: String) -> (keyCode: CGKeyCode, mods: CGEventFlags)? {
        let parts = hotkey.split(separator: "+")
        guard let last = parts.last else { return nil }
        
        // Convert key string to keyCode
        guard let keyCode = keyCodeFromString(String(last)) else {
            print("Failed to get keycode for: \(last)")
            return nil
        }
        
        // Parse modifiers
        var mods: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "command":
                mods.insert(.maskCommand)
            case "option":
                mods.insert(.maskAlternate)
            case "control":
                mods.insert(.maskControl)
            case "shift":
                mods.insert(.maskShift)
            default:
                break
            }
        }
        
        return (keyCode, mods)
    }
    
    private func keyCodeFromString(_ key: String) -> CGKeyCode? {
        // Special keys
        if key == "space" {
            return CGKeyCode(kVK_Space)
        }
        
        // Letter and number keys
        let lowercased = key.lowercased()
        switch lowercased {
        // Letters
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)
        
        // Numbers
        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)
        
        default:
            return nil
        }
    }
}
