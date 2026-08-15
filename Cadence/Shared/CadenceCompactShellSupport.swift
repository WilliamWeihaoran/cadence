import Foundation

/// The two derived values the iPhone tab shell shows: the greeting and date in the Tasks tab's
/// header, and the count on a More row.
///
/// This was `CadenceHomeSummarySupport`, and it backed the compact Home grid — greeting, a today
/// card of three counts, a single "next action", and the grid's per-cell counts. Home is gone,
/// replaced by the bottom tab bar, and the card and the grid went with it. What survived is what
/// was never about either of them.
///
/// It lives in `Shared/` rather than next to the views because `Cadence/iOS/` is entirely inside
/// `#if os(iOS)`, so anything defined there is invisible to `CadenceTests` (which builds for
/// macOS); and `habitProgress` is a *restatement* of a rule that already exists — `Habit.isDue(on:)`
/// — which is how the same idea ends up implemented twice and then disagreeing. Here a test can pin
/// that it still forwards.
enum CadenceCompactShellSupport {
    // MARK: - Header

    /// Three greetings, not four: a 2 a.m. "Good night" reads as a farewell from an app you just
    /// opened. Late night stays "Good evening".
    static func greeting(forHour hour: Int) -> String {
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        greeting(forHour: calendar.component(.hour, from: date))
    }

    /// The header eyebrow — weekday and date. Returned in its natural case; the header applies
    /// `.textCase(.uppercase)` itself, exactly as every other eyebrow.
    static func dateEyebrow(for date: Date) -> String {
        DateFormatters.longDate.string(from: date)
    }

    // MARK: - Destination counts

    struct HabitProgress: Equatable {
        let completed: Int
        let due: Int

        var label: String { "\(completed)/\(due)" }
    }

    /// `2/5` — today's habit check-ins over the habits actually due today. Habits that are not due
    /// today are not part of the fraction; a Monday-only habit is not something you are behind on
    /// during the week. `nil` when nothing is due, because a row reading `0/0` is a count that
    /// means nothing, and counts only appear where they mean something.
    static func habitProgress(
        for habits: [Habit],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> HabitProgress? {
        let todayKey = DateFormatters.dateKey(from: date, calendar: calendar)
        let due = habits.filter { $0.isDue(on: date, calendar: calendar) }
        guard !due.isEmpty else { return nil }
        return HabitProgress(
            completed: due.reduce(into: 0) { count, habit in
                if habit.isDone(on: todayKey) { count += 1 }
            },
            due: due.count
        )
    }

    /// The count a More row shows, or `nil` for the rows where no number is worth the space
    /// (Focus, Search, Settings). Everything but habits forwards to the existing badge snapshot —
    /// the same numbers the iPad sidebar and the workspace drawer show.
    static func countLabel(
        for destination: CadenceFeatureDestination,
        badges: CadenceFeatureBadgeSupport.Snapshot,
        habitProgress: HabitProgress?
    ) -> String? {
        if destination == .habits {
            return habitProgress?.label
        }
        return badges.count(for: destination).map(String.init)
    }
}
