//
//  FELog.swift
//  fileSearchForntend
//
//  Centralized frontend logging. Routes through `os.Logger`, which
//  classifies entries by TYPE in the Xcode debug console (Notice in
//  our case). The cosma backend subprocess that CosmaManager forwards
//  comes through stdout, which Xcode shows as TYPE: stdio. So:
//
//    * Xcode console "Add Filter" → TYPE: Notice → only frontend
//    * Xcode console "Add Filter" → TYPE: stdio  → only backend
//    * Filter bar → "com.cosmasense.frontend" → only frontend (by
//      subsystem; useful in Console.app or for category drill-down)
//
//  We deliberately do NOT also `print()` the message. The previous
//  version did (stamped a "[FE]" prefix into stdout) which made every
//  frontend line appear under both TYPE: Notice AND TYPE: stdio,
//  defeating the type-filter the user wanted.
//

import Foundation
import os.log

enum FELog {
    private static let subsystem = "com.cosmasense.frontend"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let policy = Logger(subsystem: subsystem, category: "policy")
    static let statusBar = Logger(subsystem: subsystem, category: "statusBar")
    static let general = Logger(subsystem: subsystem, category: "general")

    /// Standard log call. Uses `.notice` so Xcode's debug console shows
    /// the entry by default (Debug/Info levels are sometimes filtered
    /// by the run scheme; Notice is always shown). Tag the message with
    /// `\(privacy: .public)` so the body isn't redacted in release
    /// builds — these are diagnostic lines, not user secrets.
    static func emit(_ logger: Logger, _ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
