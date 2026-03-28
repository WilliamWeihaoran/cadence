import Foundation

// MARK: - Date Formatters
// All DateFormatter instances live here as statics. Never create DateFormatter() inline elsewhere.

enum DateFormatters {
    /// `yyyy-MM-dd` — storage format used in all SwiftData model date strings
    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `EEEE, MMMM d` — "Saturday, March 28"
    static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    /// `MMMM yyyy` — "March 2026"
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// `MMM d` — "Mar 28"
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// `MMM d, yyyy` — "Mar 28, 2026"
    static let fullShortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// `EEE` — "Sat"
    static let dayOfWeek: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// `d` — day-of-month number only: "28"
    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    /// `MMM` — "Mar"
    static let monthAbbrev: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    // MARK: - Convenience

    /// Returns today's date as a `yyyy-MM-dd` storage key
    static func todayKey() -> String {
        ymd.string(from: Date())
    }

    /// Converts a `Date` to a `yyyy-MM-dd` storage key
    static func dateKey(from date: Date) -> String {
        ymd.string(from: date)
    }

    /// Parses a `yyyy-MM-dd` storage key back to a `Date`
    static func date(from key: String) -> Date? {
        ymd.date(from: key)
    }

    /// Converts a `yyyy-MM-dd` storage key to a short display string: "Jan 15"
    static func shortDateString(from key: String) -> String {
        guard let date = ymd.date(from: key) else { return key }
        return shortDate.string(from: date)
    }
}

// MARK: - Time Formatters

enum TimeFormatters {
    /// Formats minutes-from-midnight as 12-hour time: 75 → "1:15 AM", 720 → "12 PM"
    static func timeString(from minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let ampm = h < 12 ? "AM" : "PM"
        return m == 0 ? "\(h12) \(ampm)" : String(format: "%d:%02d %@", h12, m, ampm)
    }

    /// Formats a start/end minute pair as a range: "1:15 AM – 2:15 AM"
    static func timeRange(startMin: Int, endMin: Int) -> String {
        "\(timeString(from: startMin)) – \(timeString(from: endMin))"
    }
}
