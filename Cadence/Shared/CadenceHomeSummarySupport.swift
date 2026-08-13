import Foundation

/// Everything the iPhone Home screen shows that is *derived* rather than typed in: the greeting,
/// the today card's three counts, the single next action, and the one grid count that is not a
/// plain badge (habits, which read `done/due` rather than a total).
///
/// It lives in `Shared/` rather than next to `iOSCompactHomeView` for two reasons. `Cadence/iOS/`
/// is entirely inside `#if os(iOS)`, so anything defined there is invisible to `CadenceTests`
/// (which builds for macOS); and every count here is a *restatement* of a rule that already exists
/// — `CadenceTaskQuerySupport.activeTodayTasks`, `completedTodayTasks`, `AppTask.isOverdue`,
/// `Habit.isDue(on:)`. Restating them in a view body is how the same idea ends up implemented
/// twice and then disagreeing; restating them here means a test can pin that it still forwards.
enum CadenceHomeSummarySupport {
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
    /// `.textCase(.uppercase)` itself, exactly as every other `iOSCompactPageHeader` eyebrow.
    static func dateEyebrow(for date: Date) -> String {
        DateFormatters.longDate.string(from: date)
    }

    /// Minutes from midnight, the same unit `AppTask.scheduledStartMin` is stored in, so "now" and
    /// a scheduled slot can be compared without either side building a `Date`.
    static func minuteOfDay(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    // MARK: - Today card

    struct TodayStats: Equatable {
        let dueTodayCount: Int
        let overdueCount: Int
        let completedCount: Int

        var isQuiet: Bool { dueTodayCount == 0 && overdueCount == 0 && completedCount == 0 }
    }

    /// The card's three numbers. Every one of them forwards to the predicate the Today screen
    /// itself uses, so tapping through from the card can never show a different day's worth of
    /// work than the card promised:
    /// - overdue is `AppTask.isOverdue(todayKey:)`, the one overdue predicate;
    /// - done is `CadenceTaskQuerySupport.completedTodayTasks`, which is what `iPadTodayView`
    ///   counts under "Done" — deliberately its definition and not macOS's stricter
    ///   `completedAt`-only one, because the Today screen this card opens is the iOS one.
    static func todayStats(from tasks: [AppTask], todayKey: String) -> TodayStats {
        let open = CadenceTaskQuerySupport.openTasks(from: tasks)
        return TodayStats(
            dueTodayCount: open.reduce(into: 0) { count, task in
                if task.dueDate == todayKey { count += 1 }
            },
            overdueCount: open.reduce(into: 0) { count, task in
                if task.isOverdue(todayKey: todayKey) { count += 1 }
            },
            completedCount: CadenceTaskQuerySupport.completedTodayTasks(from: tasks, todayKey: todayKey).count
        )
    }

    /// The one thing to do next.
    ///
    /// Preference order, in one place so it can be argued with rather than guessed at:
    /// 1. the earliest timed slot on today's timeline that has not already finished — that is what
    ///    "next" means on a day that has a schedule;
    /// 2. failing that (nothing timed, or every slot already ran), the head of
    ///    `CadenceTaskQuerySupport.activeTodayTasks`, whose ordering is already
    ///    past due → past do → due today → do today.
    ///
    /// `nowMinute` is passed in rather than read from the clock so the rule is testable, and
    /// omitting it means "ignore the time of day", which is the right answer for a caller that has
    /// no clock rather than a reason to pick midnight.
    static func nextAction(
        from tasks: [AppTask],
        todayKey: String,
        nowMinute: Int? = nil
    ) -> AppTask? {
        let candidates = CadenceTaskQuerySupport.activeTodayTasks(
            from: tasks,
            todayKey: todayKey,
            sortMode: .doDate
        )
        let timed = candidates
            .filter { $0.scheduledDate == todayKey && $0.scheduledStartMin >= 0 }
            .sorted { lhs, rhs in
                if lhs.scheduledStartMin != rhs.scheduledStartMin {
                    return lhs.scheduledStartMin < rhs.scheduledStartMin
                }
                // `sorted` is not stable, and two tasks can share a start minute. Same total
                // tie-break every other task surface uses, so the card does not pick a different
                // one of the pair between redraws.
                return TaskOrdering.fallbackPrecedes(lhs, rhs)
            }

        if let nowMinute {
            if let live = timed.first(where: { $0.scheduledEndMin > nowMinute }) { return live }
        } else if let first = timed.first {
            return first
        }

        return candidates.first
    }

    /// What the next action's trailing chip says: its time if it has one today, otherwise the list
    /// it lives in. Never both — one fact, and the time is the more useful of the two.
    enum NextActionDetail: Equatable {
        case scheduled(String)
        case list(String)

        var label: String {
            switch self {
            case .scheduled(let value), .list(let value): return value
            }
        }

        var systemImage: String {
            switch self {
            case .scheduled: return "clock"
            case .list: return "folder"
            }
        }
    }

    static func nextActionDetail(for task: AppTask, todayKey: String) -> NextActionDetail {
        if task.scheduledDate == todayKey, task.scheduledStartMin >= 0 {
            return .scheduled(TimeFormatters.timeString(from: task.scheduledStartMin))
        }
        let container = task.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return .list(container.isEmpty ? "Inbox" : container)
    }

    // MARK: - Navigation grid

    /// The grid's destinations, in order. `today` is deliberately absent: the today card *is* the
    /// Today cell, and a second one would be the same destination twice on one screen.
    static let gridDestinations: [CadenceFeatureDestination] = [
        .allTasks,
        .inbox,
        .calendar,
        .notes,
        .focus,
        .lists,
        .goals,
        .habits
    ]

    struct HabitProgress: Equatable {
        let completed: Int
        let due: Int

        var label: String { "\(completed)/\(due)" }
    }

    /// `2/5` — today's habit check-ins over the habits actually due today. Habits that are not due
    /// today are not part of the fraction; a Monday-only habit is not something you are behind on
    /// during the week. `nil` when nothing is due, because a cell reading `0/0` is a count that
    /// means nothing, and the brief was explicit that counts only appear where they mean something.
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

    /// The count a grid cell shows, or `nil` for the cells where no number is worth the space
    /// (Calendar, Notes, Focus). Everything but habits forwards to the existing badge snapshot —
    /// the same numbers the iPad sidebar and the workspace drawer show.
    static func gridCountLabel(
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
