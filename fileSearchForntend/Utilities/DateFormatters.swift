//
//  DateFormatters.swift
//  fileSearchForntend
//
//  Centralized date formatting utilities with cached formatters.
//  DateFormatter creation is expensive - these cached instances improve performance.
//

import Foundation

// MARK: - Date Formatters

/// Centralized date formatting with cached formatters for performance.
enum DateFormatters {

    // MARK: - Cached Formatters

    /// Short time format (e.g., "2:30 PM")
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    /// Medium date with short time (e.g., "Jan 5, 2024, 2:30 PM")
    private static let mediumDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Month day and time (e.g., "Jan 5, 14:30")
    private static let monthDayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    /// Month day and year (e.g., "Jan 5, 2024")
    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    /// Relative time (e.g., "2 min ago")
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Full relative time (e.g., "2 minutes ago")
    private static let fullRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: - Public Formatting Methods

    /// Formats a date with smart logic: "Today 2:30 PM", "Yesterday 2:30 PM", "Jan 5, 14:30", or "Jan 5, 2024"
    static func smartFormat(_ date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current

        // Today
        if calendar.isDateInToday(date) {
            return "Today \(timeFormatter.string(from: date))"
        }

        // Yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(timeFormatter.string(from: date))"
        }

        // This year
        let dateComponents = calendar.dateComponents([.year], from: date, to: now)
        if dateComponents.year == 0 {
            return monthDayTimeFormatter.string(from: date)
        }

        // Older
        return monthDayYearFormatter.string(from: date)
    }

    /// Formats a date with medium date and short time style
    static func mediumDateTime(_ date: Date) -> String {
        mediumDateTimeFormatter.string(from: date)
    }

    /// Formats a date as abbreviated relative time (e.g., "2 min ago")
    static func relativeTime(_ date: Date, relativeTo now: Date = Date()) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    /// Formats a date as full relative time (e.g., "2 minutes ago")
    static func fullRelativeTime(_ date: Date, relativeTo now: Date = Date()) -> String {
        fullRelativeFormatter.localizedString(for: date, relativeTo: now)
    }

    /// Formats a Unix timestamp as abbreviated relative time
    static func relativeTime(fromTimestamp timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return relativeTime(date)
    }

    /// Formats time only (e.g., "2:30 PM")
    static func timeOnly(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

// MARK: - Date Extension

extension Date {
    /// Smart formatted string: "Today 2:30 PM", "Yesterday...", "Jan 5, 14:30", or "Jan 5, 2024"
    var smartFormatted: String {
        DateFormatters.smartFormat(self)
    }

    /// Medium date with short time: "Jan 5, 2024, 2:30 PM"
    var mediumDateTimeFormatted: String {
        DateFormatters.mediumDateTime(self)
    }

    /// Abbreviated relative time: "2 min ago"
    var relativeFormatted: String {
        DateFormatters.relativeTime(self)
    }
}
