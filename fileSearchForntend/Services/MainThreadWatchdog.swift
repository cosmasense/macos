//
//  MainThreadWatchdog.swift
//  fileSearchForntend
//
//  Detects and logs main-thread stalls so a "frozen UI" report has
//  hard data attached: when did it start, how long, and (when run via
//  Console.app) what stack the app was on while frozen.
//

import Foundation
import OSLog

/// Pings the main thread every ``probeInterval`` from a background timer
/// queue. Each ping schedules a Dispatch onto main. If main doesn't pick
/// up the dispatch within ``hangThreshold``, the watchdog logs a
/// ``ui.hang.start`` entry; once it picks back up, ``ui.hang.end`` with
/// the measured duration.
///
/// Logs land in OSLog under `subsystem=com.filesearch, category=watchdog`,
/// filterable in Console.app. Pair with the sample CLI to get a stack:
///
///     sample 'Cosma Sense' 5 -file /tmp/cosma-sample.txt
///
/// run during a hang, then `grep -A 30 'main thread' /tmp/cosma-sample.txt`.
///
/// Class is *not* @MainActor — all internal bookkeeping happens on a
/// dedicated serial DispatchQueue so we can hop on/off main freely
/// without actor-hop overhead skewing the latency we're measuring.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    private let log = Logger(subsystem: "com.filesearch", category: "watchdog")

    /// How often we ping main. Cheap (one Date() + a Dispatch hop), so
    /// 500ms is plenty granular without being noisy in logs.
    private let probeInterval: TimeInterval = 0.5
    /// Hang threshold — main must service the dispatch within this
    /// window or we count it as a stall. SwiftUI's worst-case smooth
    /// frame is ~16ms; anything over 250ms is user-visible jank.
    private let hangThreshold: TimeInterval = 0.25

    /// All mutable state below is touched ONLY from `timerQueue`, which
    /// is a serial DispatchQueue — that's our isolation guarantee.
    private var timer: DispatchSourceTimer?
    private var hangStartedAt: Date?

    private let timerQueue = DispatchQueue(
        label: "com.filesearch.MainThreadWatchdog",
        qos: .utility
    )

    private init() {}

    func start() {
        timerQueue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.log.info("watchdog.start interval=\(self.probeInterval, privacy: .public)s threshold=\(self.hangThreshold, privacy: .public)s")
            let t = DispatchSource.makeTimerSource(queue: self.timerQueue)
            t.schedule(deadline: .now() + self.probeInterval, repeating: self.probeInterval)
            t.setEventHandler { [weak self] in
                self?.tick()
            }
            self.timer = t
            t.resume()
        }
    }

    func stop() {
        timerQueue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// Runs on `timerQueue`. Schedules a probe onto main and times how
    /// long it takes to be serviced.
    private func tick() {
        let enqueuedAt = Date()
        DispatchQueue.main.async { [weak self] in
            // On main now — measure the full enqueue→service latency.
            let elapsed = Date().timeIntervalSince(enqueuedAt)
            self?.timerQueue.async { [weak self] in
                self?.recordProbeResult(enqueuedAt: enqueuedAt, mainLatency: elapsed)
            }
        }
    }

    /// Runs on `timerQueue`. Updates hang bookkeeping based on the
    /// latency the probe measured on main.
    private func recordProbeResult(enqueuedAt: Date, mainLatency: TimeInterval) {
        let isHang = mainLatency >= hangThreshold
        if isHang {
            if hangStartedAt == nil {
                hangStartedAt = enqueuedAt
                let ms = Int(mainLatency * 1000)
                log.error("ui.hang.start latency=\(ms, privacy: .public)ms")
                let pid = ProcessInfo.processInfo.processIdentifier
                log.error("ui.hang.tip Run: sample \(pid, privacy: .public) 5 -file /tmp/cosma-sample.txt   (then grep -A 30 'main thread' /tmp/cosma-sample.txt)")
            }
        } else if let start = hangStartedAt {
            let totalMs = Int(Date().timeIntervalSince(start) * 1000)
            log.error("ui.hang.end duration=\(totalMs, privacy: .public)ms")
            hangStartedAt = nil
        }
    }
}
