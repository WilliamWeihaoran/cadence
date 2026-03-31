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

    static func dayOffset(from key: String, relativeTo referenceDate: Date = Date()) -> Int? {
        guard let date = ymd.date(from: key) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceDate)
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: today, to: target).day
    }

    /// Converts a `yyyy-MM-dd` storage key to a relative string using task-friendly rules:
    /// "Today", "Tomorrow", "Yesterday", "in 5 days", "30 days ago", or "Mar 28"
    static func relativeDate(from key: String) -> String {
        guard let date = ymd.date(from: key) else { return key }
        let diff = dayOffset(from: key) ?? Int.max
        switch diff {
        case 0:          return "Today"
        case 1:          return "Tomorrow"
        case -1:         return "Yesterday"
        case 2...13:     return "in \(diff) days"
        case Int.min ..< -1: return "\(-diff) days ago"
        default:         return shortDate.string(from: date)
        }
    }

    // MARK: - Week keys

    /// Returns the current ISO week key: "2026-W13"
    static func currentWeekKey() -> String { weekKey(from: Date()) }

    /// Converts a Date to an ISO week key: "2026-W13"
    static func weekKey(from date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? cal.component(.year, from: date)
        let week = comps.weekOfYear ?? 1
        return String(format: "%d-W%02d", year, week)
    }

    /// Converts an ISO week key to a human-readable label: "Week of Mar 23"
    static func weekLabel(from weekKey: String) -> String {
        let parts = weekKey.components(separatedBy: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]), let week = Int(parts[1]) else { return weekKey }
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "en_US_POSIX")
        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = week
        comps.weekday = 2 // Monday
        guard let monday = cal.date(from: comps) else { return weekKey }
        return "Week of \(shortDate.string(from: monday))"
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

    /// Compact actual/estimated label: "3m/15m", "1h/2h", "-/30m", "45m/-", etc.
    /// Shows minutes for <60 min, hours (with one decimal if fractional) for ≥60 min.
    /// Returns "-" for any zero/negative value.
    static func durationLabel(actual: Int, estimated: Int) -> String {
        func fmt(_ m: Int) -> String {
            guard m > 0 else { return "-" }
            if m < 60 { return "\(m)m" }
            if m % 60 == 0 { return "\(m / 60)h" }
            return String(format: "%.1fh", Double(m) / 60.0)
        }
        return "\(fmt(actual))/\(fmt(estimated))"
    }
}
