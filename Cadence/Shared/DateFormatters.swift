import Foundation

// MARK: - Date Formatters
// All DateFormatter instances live here as statics. Never create DateFormatter() inline elsewhere.

/// `nonisolated`, and this one is worth spelling out because it is the only mark in the T-87 sweep
/// that puts shared state within reach of another thread.
///
/// The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this enum used to be
/// main-actor isolated — which meant every date-shaped helper that wanted to be `nonisolated` for
/// the widget target had to route around it. `CadenceWidgetDateSupport` exists precisely because
/// of that (see the note on `CadenceFocusPlanningSupport.dueLabel`), and a second copy of the
/// due-date vocabulary drifted while it did.
///
/// Three things make it safe rather than merely convenient:
/// - `DateFormatter` is documented thread-safe on macOS 10.9+ / iOS 7+ **as long as it is not
///   mutated**, and every formatter below is configured inside its initializer closure and never
///   touched again. Swift's lazy static initialization is itself thread-safe.
/// - This file already compiles into `CadenceMCPServer`, which sets no default actor isolation and
///   is on `SWIFT_VERSION = 6.0` — so these statics have been nonisolated in a shipping target all
///   along. This aligns the app with what that target already does.
/// - The calendar-based half (`storageCalendar`, `dateKey(from:calendar:)`, `date(from:in:)`,
///   `weekKey(from:)`, `weekStartDate(forWeekKey:calendar:)`) touches no shared instance at all.
///
/// If a formatter here ever needs to be *reconfigured* at runtime, that is the point at which this
/// stops being true — make it a computed property rather than re-isolating the enum.
nonisolated enum DateFormatters {
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
    ///
    /// Locale-pinned like `ymd`, and for the same reason this repo pins every fixed-format
    /// formatter: without it the month name follows the host's locale, so the notes list's month
    /// headers and the calendar's month title read "AOÛT 2026" on a French Mac while every other
    /// string in the app — which is English-only, with no localizations — stays English. Pinning
    /// also makes `NotesListVisibilityTests.monthGroupingFormsRunsOverTheFilteredList` test the
    /// implementation rather than the tester's `Language & Region` setting.
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// `MMM yyyy` — "Mar 2026". The month spelling the **iOS date selectors** read in.
    ///
    /// `monthYear` above is the long form and stays long: it renders the macOS calendar title, the
    /// notes list's month headings and `MonthCalendarPanel`'s header, none of which are this
    /// control. What this one exists for is `iOSDateJumpTitle` — the title-as-date-button shared by
    /// the four iOS calendar surfaces and the Notes header. Every other reading that control shows
    /// already abbreviates the month (`shortDate`'s "Aug 17", the notes week range's "Aug 17–23"),
    /// because it is a phone-width row that also holds a back chevron and two pill groups; the
    /// month grid was the one label in it still spelling "August 2026" in full, so one control read
    /// in two month vocabularies depending on which surface you were on.
    ///
    /// Locale-pinned for the same reason as `ymd` and `monthYear`: the app is English-only, so
    /// without it a French Mac or phone would read "août 2026" beside otherwise-English chrome.
    static let shortMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
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

    /// The calendar every `yyyy-MM-dd` storage key is expressed in: **always Gregorian**, with
    /// the time zone taken from `calendar`.
    ///
    /// `ymd` pins `en_US_POSIX`, so every key ever written to the store is Gregorian. Anything
    /// that derives the same key from `calendar.dateComponents` instead must therefore force
    /// Gregorian too, or it produces a string that cannot match stored data. `Calendar.current`
    /// is not Gregorian everywhere: region Thailand defaults to Buddhist, and Japanese and
    /// Islamic calendars are one Settings tap away. For 2026-08-11 those yield `2569-08-11`,
    /// `0008-08-11` (the year is era-relative) and `1448-02-27` respectively — none of which
    /// matches anything on disk.
    ///
    /// The time zone still comes from the caller, because *that* genuinely differs by call site
    /// and getting it wrong is the off-by-one-day DST bug this file already documents below.
    static func storageCalendar(inheritingTimeZoneFrom calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    /// Converts a `Date` to a `yyyy-MM-dd` storage key, read in `calendar`'s time zone.
    static func dateKey(from date: Date, calendar: Calendar) -> String {
        let components = storageCalendar(inheritingTimeZoneFrom: calendar)
            .dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    /// Parses a `yyyy-MM-dd` storage key back to a `Date`
    static func date(from key: String) -> Date? {
        ymd.date(from: key)
    }

    /// Resolves a `yyyy-MM-dd` key to midnight **in `calendar`'s own time zone**.
    ///
    /// `ymd` pins a locale but not a time zone, so it parses in the system zone. That is fine
    /// whenever the result is measured with `Calendar.current` too, but any code that takes a
    /// calendar as a parameter has to parse in that calendar or the two disagree: parsing
    /// "2026-03-09" in UTC+8 and then counting days from it in America/New_York lands on the
    /// previous day, which is how a DST-boundary offset silently became off-by-one.
    static func date(from key: String, in calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        // Keys are Gregorian (see `storageCalendar`); only the time zone is the caller's.
        return storageCalendar(inheritingTimeZoneFrom: calendar)
            .date(from: DateComponents(year: year, month: month, day: day))
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
    ///
    /// `relativeTo` exists so a caller that has already decided what "today" is can say so.
    /// `dayOffset` took one from the start; this did not, so
    /// `CadenceOverdueSummaryPresentation.line(…todayKey:)` was honouring its injected day for
    /// `isLate` and silently reading the system clock for the words beside it — the two halves of
    /// one line disagreeing about the date.
    static func relativeDate(from key: String, relativeTo referenceDate: Date = Date()) -> String {
        guard let date = ymd.date(from: key) else { return key }
        let diff = dayOffset(from: key, relativeTo: referenceDate) ?? Int.max
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

    /// The Monday that opens the ISO week named by `weekKey` ("2026-W33"), or `nil` if the key is
    /// malformed.
    ///
    /// This construction — `Calendar(identifier: .iso8601)` + `en_US_POSIX` + `weekday = 2` — was
    /// written out twice, here and in `NotesListGrouping.weekStartDateKey`, and neither copy
    /// inherited a time zone the way `storageCalendar(inheritingTimeZoneFrom:)` requires. One
    /// definition, and the time zone is the caller's, so the resulting date is measured in the
    /// same zone the key was written in.
    static func weekStartDate(forWeekKey weekKey: String, calendar: Calendar = .current) -> Date? {
        let parts = weekKey.components(separatedBy: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]), let week = Int(parts[1]) else { return nil }
        var iso = Calendar(identifier: .iso8601)
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = calendar.timeZone
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2 // Monday
        return iso.date(from: components)
    }

    /// Converts an ISO week key to a human-readable label: "Week of Mar 23"
    static func weekLabel(from weekKey: String) -> String {
        guard let monday = weekStartDate(forWeekKey: weekKey) else { return weekKey }
        return "Week of \(shortDate.string(from: monday))"
    }
}

// MARK: - Time Formatters

nonisolated enum TimeFormatters {
    /// Formats minutes-from-midnight as 12-hour time: 75 → "1:15 AM", 720 → "12 PM"
    static func timeString(from minutes: Int) -> String {
        let normalized = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        let h = normalized / 60
        let m = normalized % 60
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let ampm = h < 12 ? "AM" : "PM"
        return m == 0 ? "\(h12) \(ampm)" : String(format: "%d:%02d %@", h12, m, ampm)
    }

    /// Formats a start/end minute pair as a range: "1:15 AM – 2:15 AM"
    static func timeRange(startMin: Int, endMin: Int) -> String {
        "\(timeString(from: startMin)) – \(timeString(from: endMin))"
    }

    /// Canonical minutes → duration label for the whole app: "45m", "2h", "1h 24m". Never renders
    /// a decimal hour — the hour and minute components are shown separately, and a zero component
    /// is omitted.
    ///
    /// The gap between the hour and the minute component is a NON-BREAKING SPACE (U+00A0) on
    /// purpose. These labels are drawn inside hard-clipped fixed-size chrome (timeline blocks can
    /// be ~50pt wide when three tasks overlap); an ordinary space is a line-break opportunity, so
    /// "1h 30m" would wrap and the clipped second line would leave the badge reading "1h" for a
    /// 90-minute task — wrong information, not just truncation.
    ///
    /// `emptyPlaceholder` is what a zero/negative duration renders as, because the surfaces do not
    /// agree on that and should not have to fork the formatter to disagree: the estimate chips say
    /// `"0m"`, the actual/estimated pair says `"-"`, and the timeline event editor says an en dash.
    /// That difference is the *only* thing those call sites ever needed of their own — this was
    /// written out six times in three spellings, and two of the copies used a breakable space.
    ///
    /// It lives here rather than beside `CadenceTaskPresentationSupport.estimateLabel` (which now
    /// forwards to it) because `Shared/` is not compiled into the widget or MCP targets and
    /// `Models/GoalContributionSummary` needs it. `DateFormatters.swift` is in all three.
    static func durationLabel(minutes: Int, emptyPlaceholder: String) -> String {
        guard minutes > 0 else { return emptyPlaceholder }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h\u{00A0}\(remainder)m"
    }

    /// Compact actual/estimated label: "3m/15m", "1h/2h", "-/30m", "45m/-", etc.
    /// Returns "-" for either side when it is zero or negative.
    static func durationLabel(actual: Int, estimated: Int) -> String {
        let actualLabel = durationLabel(minutes: actual, emptyPlaceholder: "-")
        let estimatedLabel = durationLabel(minutes: estimated, emptyPlaceholder: "-")
        return "\(actualLabel)/\(estimatedLabel)"
    }
}
