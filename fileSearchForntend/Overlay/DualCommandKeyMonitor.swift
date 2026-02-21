//
//  DualCommandKeyMonitor.swift
//  fileSearchForntend
//
//  Detects both Command keys pressed simultaneously.
//  Uses a CGEventTap for global flagsChanged detection (NSEvent global
//  monitors don't reliably deliver modifier-only events from other apps)
//  plus an NSEvent local monitor as a fallback when the app is focused.
//

import AppKit
import CoreGraphics

final class DualCommandKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var action: (() -> Void)?

    private var hasFired = false
    private var lastFireTime: CFAbsoluteTime = 0
    private static let cooldown: CFAbsoluteTime = 0.3

    // Device-dependent flag masks (from IOKit NX_ defines)
    // These distinguish left vs right modifier keys, unlike the
    // device-independent .maskCommand which merges both.
    private static let leftCmdMask: UInt64 = 0x00000008   // NX_DEVICELCMDKEYMASK
    private static let rightCmdMask: UInt64 = 0x00000010  // NX_DEVICERCMDKEYMASK

    deinit {
        stop()
    }

    func start(action: @escaping () -> Void) {
        stop()
        self.action = action

        // --- CGEventTap for global flagsChanged detection ---
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<DualCommandKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

                // Re-enable tap if macOS disabled it
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                monitor.handleCGFlags(event.flags)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            print("Failed to create CGEventTap for DualCommandKeyMonitor (Input Monitoring permission may be missing)")
            Unmanaged<DualCommandKeyMonitor>.fromOpaque(selfPtr).release()
        }

        // --- NSEvent local monitor as fallback when app is focused ---
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSFlags(event.modifierFlags)
            return event
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                runLoopSource = nil
            }
            // Release the retained self from start()
            var context = CFMachPortContext()
            CFMachPortGetContext(tap, &context)
            if let info = context.info {
                Unmanaged<DualCommandKeyMonitor>.fromOpaque(info).release()
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        hasFired = false
        action = nil
    }

    // MARK: - Flag checking

    private func handleCGFlags(_ flags: CGEventFlags) {
        let raw = flags.rawValue
        let leftDown = (raw & Self.leftCmdMask) != 0
        let rightDown = (raw & Self.rightCmdMask) != 0
        evaluateDualCommand(leftDown: leftDown, rightDown: rightDown)
    }

    private func handleNSFlags(_ flags: NSEvent.ModifierFlags) {
        let raw = UInt64(flags.rawValue)
        let leftDown = (raw & Self.leftCmdMask) != 0
        let rightDown = (raw & Self.rightCmdMask) != 0
        evaluateDualCommand(leftDown: leftDown, rightDown: rightDown)
    }

    private func evaluateDualCommand(leftDown: Bool, rightDown: Bool) {
        if !leftDown || !rightDown {
            hasFired = false
            return
        }

        guard !hasFired else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard (now - lastFireTime) >= Self.cooldown else { return }

        hasFired = true
        lastFireTime = now

        DispatchQueue.main.async { [weak self] in
            self?.action?()
        }
    }
}
