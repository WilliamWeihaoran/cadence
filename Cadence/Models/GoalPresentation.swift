import Foundation

/// Date-range and progress derivations for a `Goal`.
///
/// These lived in `macOS/Views/GoalsSupportViews.swift`, inside a `#if os(macOS)` block in a
/// *views* file, which had three consequences worth spelling out:
///
/// - iOS, `CadenceWidgets` and `CadenceMCPServer` could not see any of it, so each re-derived the
///   same answers or went without. `Goal.isOverdue` was the sixth `isOverdue` in the app.
/// - `startDateDate` / `endDateDate` called `DateFormatters.ymd.date(from:)` directly, bypassing
///   `DateFormatters.date(from:in:)` — the timezone-safe API. `ymd` is a shared formatter with no
///   pinned time zone, so a goal's start and end resolved in whatever zone happened to be current
///   while the rest of the app measured them in a calendar's own.
/// - `progressSummary` reached into `GoalContributionResolver` from a view file, inverting the
///   dependency direction.
///
/// `Models/` is compiled into every target, so this is the only home from which all four surfaces
/// can share one answer.
extension Goal {
    /// Resolved in `calendar`'s own time zone, matching how the durations below are measured.
    func startDate(in calendar: Calendar = .current) -> Date? {
        DateFormatters.date(from: startDate, in: calendar)
    }

    func endDate(in calendar: Calendar = .current) -> Date? {
        DateFormatters.date(from: endDate, in: calendar)
    }

    var startDateDate: Date? { startDate(in: .current) }
    var endDateDate: Date? { endDate(in: .current) }

    var rangeLabel: String {
        guard let start = startDateDate, let end = endDateDate else { return "No date range" }
        return "\(DateFormatters.shortDate.string(from: start)) - \(DateFormatters.shortDate.string(from: end))"
    }

    var progressSummary: String {
        GoalContributionResolver.summary(for: self).taskCountLabel
    }

    /// How much of the goal's window is left, as of `now`.
    ///
    /// Injectable so it can be asserted without depending on the wall clock at test-run time —
    /// the view-file original read `Date()` and `Calendar.current` inline and was untestable.
    func daysSummary(asOf now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let end = endDate(in: calendar) else { return "No end date" }
        if status == .done { return "Completed" }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        if days < 0 { return "\(-days)d late" }
        if days == 0 { return "Due today" }
        return "\(days)d left"
    }

    var daysSummary: String { daysSummary() }

    /// A goal is overdue when its **end date** has passed and it is not done.
    ///
    /// Named for the goal deliberately: `AppTask.isOverdue(todayKey:)` answers the same-sounding
    /// question about a task's *due date*, and the two were the fifth and sixth spellings of
    /// "overdue" in the app. Keeping both but naming this one for its subject stops a future
    /// reader assuming they are interchangeable.
    func isOverdue(asOf now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard status != .done, let end = endDate(in: calendar) else { return false }
        return end < calendar.startOfDay(for: now)
    }

    var isOverdue: Bool { isOverdue() }
}
