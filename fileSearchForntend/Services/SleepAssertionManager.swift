//
//  SleepAssertionManager.swift
//  fileSearchForntend
//
//  Holds an IOPMAssertion to block idle system sleep while the
//  indexing queue is busy and the user has the "Prevent sleep during
//  indexing" preference on. Overnight indexing runs on big folders
//  routinely got cut short because the Mac fell asleep — this is the
//  fix.
//
//  PreventUserIdleSystemSleep is the right level here: it blocks the
//  idle timer (user not moving the mouse / typing) but still allows
//  sleep when the lid closes or the battery hits critical, so we're
//  not preventing user-intended sleep — only the silent overnight one.
//

import Foundation
import IOKit.pwr_mgt
import os.log

@MainActor
final class SleepAssertionManager {
    static let shared = SleepAssertionManager()

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var isActive: Bool = false
    private let log = Logger(subsystem: "com.filesearch", category: "sleep")

    private init() {}

    /// True iff an assertion is currently held. Mostly useful for tests
    /// and debug surfaces; the queue/preference syncer is the single
    /// caller of `setEnabled`.
    var isHoldingAssertion: Bool { isActive }

    /// Idempotent: calling with the same value twice is a no-op. The
    /// `reason` string surfaces in `pmset -g assertions`, which is the
    /// easiest way to verify the assertion is actually held when
    /// debugging an overnight-sleep complaint.
    func setEnabled(_ enabled: Bool, reason: String = "Cosma Sense is indexing files") {
        if enabled == isActive { return }
        if enabled {
            var newID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &newID
            )
            if result == kIOReturnSuccess {
                assertionID = newID
                isActive = true
                log.info("Sleep prevention activated (assertion=\(newID, privacy: .public))")
            } else {
                log.error("Failed to create sleep assertion: IOReturn=\(result, privacy: .public)")
            }
        } else {
            let result = IOPMAssertionRelease(assertionID)
            if result != kIOReturnSuccess {
                log.error("Failed to release sleep assertion: IOReturn=\(result, privacy: .public)")
            } else {
                log.info("Sleep prevention released")
            }
            // Reset state regardless — a leaked assertion is preferable
            // to a stuck `isActive=true` that would block all future
            // setEnabled calls.
            assertionID = IOPMAssertionID(0)
            isActive = false
        }
    }
}
