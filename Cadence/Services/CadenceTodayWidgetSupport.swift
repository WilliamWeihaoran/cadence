import Foundation
import SwiftData

nonisolated enum CadenceTodayWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

nonisolated struct CadenceTodayWidgetTask: Identifiable, Hashable {
    let id: UUID
    let title: String
    let priorityRaw: String
    let dueDate: String
    let scheduledDate: String
    let containerName: String

    var deepLinkURL: URL {
        CadenceDeepLink.task(id).url
    }
}

nonisolated struct CadenceTodayWidgetSnapshot: Hashable {
    let date: Date
    let dateKey: String
    let state: CadenceTodayWidgetSnapshotState
    let statusMessage: String?
    let totalCount: Int
    let overdueCount: Int
    let dueTodayCount: Int
    let scheduledTodayCount: Int
    let tasks: [CadenceTodayWidgetTask]

    var todayURL: URL {
        CadenceDeepLink.today.url
    }

    var isUnavailable: Bool {
        state == .unavailable
    }
}

nonisolated enum CadenceTodayWidgetSupport {
    nonisolated static func snapshot(
        modelContext: ModelContext,
        limit: Int = 3
    ) throws -> CadenceTodayWidgetSnapshot {
        try snapshot(modelContext: modelContext, todayKey: currentTodayKey(), limit: limit)
    }

    nonisolated static func snapshot(
        modelContext: ModelContext,
        todayKey: String,
        limit: Int = 3
    ) throws -> CadenceTodayWidgetSnapshot {
        let tasks = try modelContext.fetch(todayCandidateFetchDescriptor())
        let suppressedTaskIDs = CadenceWidgetRefreshCenter.suppressedTaskIDs()
        return snapshot(
            from: tasks,
            todayKey: todayKey,
            limit: limit,
            suppressedTaskIDs: suppressedTaskIDs
        )
    }

    nonisolated static func snapshot(
        from tasks: [AppTask],
        todayKey: String,
        limit: Int = 3,
        suppressedTaskIDs: Set<UUID> = []
    ) -> CadenceTodayWidgetSnapshot {
        let visibleLimit = max(limit, 0)
        var totalCount = 0
        var overdueCount = 0
        var dueTodayCount = 0
        var scheduledTodayCount = 0
        var visibleTasks: [CadenceTodayWidgetTask] = []
        visibleTasks.reserveCapacity(visibleLimit)

        for task in todayTasks(from: tasks, todayKey: todayKey) where !suppressedTaskIDs.contains(task.id) {
            totalCount += 1
            // The badges read the shared standing rather than the dates a third time. Exhaustive
            // on purpose: the three counts must add up to `totalCount`, and before T-353 they did
            // not — a past-do task fell through all three branches, so a widget drawing one row
            // could read "0 overdue, 0 due, 0 planned" beside it.
            switch task.todayStanding(todayKey: todayKey) {
            case .pastDue:
                overdueCount += 1
            case .dueToday:
                dueTodayCount += 1
            case .pastDo, .doToday:
                // Yesterday's plan is still planned work; "Planned" is the badge it belongs under.
                scheduledTodayCount += 1
            case nil:
                break // Unreachable: `todayTasks` drops anything with no standing.
            }

            if visibleTasks.count < visibleLimit {
                visibleTasks.append(widgetTask(task))
            }
        }

        let state: CadenceTodayWidgetSnapshotState = totalCount == 0 ? .empty : .ready

        return CadenceTodayWidgetSnapshot(
            date: Date(),
            dateKey: todayKey,
            state: state,
            statusMessage: nil,
            totalCount: totalCount,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            scheduledTodayCount: scheduledTodayCount,
            tasks: visibleTasks
        )
    }

    nonisolated static func unavailableSnapshot(
        todayKey: String = currentTodayKey(),
        message: String = "Open Cadence once to finish setting up your shared widget data."
    ) -> CadenceTodayWidgetSnapshot {
        CadenceTodayWidgetSnapshot(
            date: Date(),
            dateKey: todayKey,
            state: .unavailable,
            statusMessage: message,
            totalCount: 0,
            overdueCount: 0,
            dueTodayCount: 0,
            scheduledTodayCount: 0,
            tasks: []
        )
    }

    nonisolated static func recommendedReloadDate(
        for snapshot: CadenceTodayWidgetSnapshot,
        referenceDate: Date = Date()
    ) -> Date {
        let calendar = Calendar.current
        let nextStartOfDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        ).addingTimeInterval(60)

        let fallbackInterval: TimeInterval
        switch snapshot.state {
        case .unavailable:
            fallbackInterval = 5 * 60
        case .empty:
            fallbackInterval = 30 * 60
        case .ready:
            fallbackInterval = 15 * 60
        }

        return min(referenceDate.addingTimeInterval(fallbackInterval), nextStartOfDay)
    }

    /// The widget's Today list — **the app's Today scope, in the app's Today rank order**, with a
    /// priority tie-break of its own on top.
    ///
    /// Both of those used to be spelled here: a local `rank` with no past-do branch and a
    /// `rank < 3` membership test. So an unfinished task planned for an earlier day with no due
    /// date was on the app's Today page and missing from this list — and from the Calendar
    /// widget's "Next up", which is `.first` of this same call. That is T-353, and the reason it
    /// was two definitions rather than one missed case is that `Cadence/Shared/` is not compiled
    /// into `CadenceWidgets`. `AppTask.isTodayWork` / `todayStanding` are in `Models/`, which is,
    /// so this and `CadenceTaskQuerySupport.activeTodayTasks` now read the same rule.
    nonisolated static func todayTasks(
        from tasks: [AppTask],
        todayKey: String
    ) -> [AppTask] {
        tasks.compactMap { task -> (task: AppTask, rank: Int, priorityRank: Int)? in
            guard task.isTodayWork(todayKey: todayKey),
                  let standing = task.todayStanding(todayKey: todayKey) else { return nil }
            return (task, standing.rawValue, priorityRank(task.priority))
        }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.priorityRank != rhs.priorityRank {
                    return lhs.priorityRank > rhs.priorityRank
                }
                // The shared tie-break rather than a bare `order`. A widget renders the first
                // few rows of this list, so an unstable tail is the difference between "the
                // widget updated" and "the widget shuffled".
                return TaskOrdering.fallbackPrecedes(lhs.task, rhs.task)
            }
            .map(\.task)
    }

    private nonisolated static func widgetTask(_ task: AppTask) -> CadenceTodayWidgetTask {
        CadenceTodayWidgetTask(
            id: task.id,
            title: task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : task.title,
            priorityRaw: task.priority.rawValue,
            dueDate: task.dueDate,
            scheduledDate: task.scheduledDate,
            containerName: task.containerName
        )
    }

    private nonisolated static func priorityRank(_ priority: TaskPriority) -> Int { priority.rank }

    /// The rows the store has to hand over for `todayTasks` to pick from — **a deliberate
    /// superset, and deliberately ignorant of what day it is.**
    ///
    /// A `#Predicate` is a macro compiled to a store query; it cannot call
    /// `AppTask.isTodayWork(todayKey:)`, so this is the one place a Today rule *could* only exist
    /// as a second copy. It used to be one: three date terms with no past-do branch, which is why
    /// fixing `todayTasks` alone would have left the shipping widget still missing the task —
    /// the row never reached it. So the date terms are gone rather than corrected. What is left
    /// says only "unfinished, and carrying at least one date", which every standing in
    /// `CadenceTodayStanding` implies and no future edit to that rule can outgrow.
    ///
    /// Internal rather than `private` so a test can drive the store query and the in-memory scope
    /// from one fixture set and require the same ids —
    /// `theWidgetsStoreQueryKeepsEveryTaskItsTodayScopeAdmits`.
    nonisolated static func todayCandidateFetchDescriptor() -> FetchDescriptor<AppTask> {
        let doneStatus = TaskStatus.done.rawValue
        let cancelledStatus = TaskStatus.cancelled.rawValue

        let predicate = #Predicate<AppTask> { task in
            task.statusRaw != doneStatus &&
            task.statusRaw != cancelledStatus &&
            (task.dueDate != "" || task.scheduledDate != "")
        }

        return FetchDescriptor<AppTask>(predicate: predicate)
    }

    private nonisolated static func currentTodayKey() -> String {
        CadenceWidgetDateSupport.dateKey(from: Date())
    }
}

/// The widget target's date vocabulary.
///
/// **Everything here now forwards to `DateFormatters`.** This enum was originally a hand-rolled
/// copy because `DateFormatters` was main-actor isolated and widget timeline providers run off the
/// main actor — but the T-87 sweep marked that enum `nonisolated`, and `Cadence/Shared/`
/// `DateFormatters.swift` is compiled into `CadenceWidgets` alongside this file. So the workaround
/// outlived its reason, and what was left of it was a second set of date formats that drifted:
/// the labels below were built with `date.formatted(...)`, which follows `Locale.current`, so a
/// widget on a French phone rendered `SAM.` and `15 août` beside the app's English chrome on the
/// same home screen. The pinned formatters are the whole point of that file.
nonisolated enum CadenceWidgetDateSupport {
    /// Calendar-injectable core. The `Calendar.current` convenience below is what the widget
    /// actually calls, but a test host is always Gregorian, so without a seam no assertion here
    /// can tell a correct implementation from one that reads `Calendar.current`'s components.
    ///
    /// The Gregorian forcing that keeps these keys matching the store lives in
    /// `DateFormatters.storageCalendar(inheritingTimeZoneFrom:)`, which documents the Buddhist /
    /// Japanese / Islamic keys a `Calendar.current` read produced. This enum used to re-expose
    /// that as a forwarding member of its own; the collapse in `0e78c5b` left it with no callers,
    /// and T-453 removed it. Reach for `DateFormatters` directly if a widget ever needs it again.
    nonisolated static func dateKey(from date: Date, calendar: Calendar) -> String {
        DateFormatters.dateKey(from: date, calendar: calendar)
    }

    nonisolated static func dateKey(from date: Date) -> String {
        dateKey(from: date, calendar: .current)
    }

    /// `"SAT"`. Pinned to `en_US_POSIX` via `DateFormatters.dayOfWeek`, so it reads the same on
    /// every host — see the note on this enum for what following the host looked like.
    nonisolated static func weekdayLabel(from date: Date) -> String {
        DateFormatters.dayOfWeek.string(from: date).uppercased()
    }

    /// `"15"`. Pinned too, and the numerals are the reason: `DateFormatters.dayNumber` documents
    /// that an unpinned `"d"` renders Arabic-Indic digits under an `ar` host.
    nonisolated static func dayNumberLabel(from date: Date) -> String {
        DateFormatters.dayNumber.string(from: date)
    }

    /// Cadence's single due-date vocabulary: `nil` (no due date at all), "Due today",
    /// "Due tomorrow", "Overdue Aug 2", "Due Aug 14".
    ///
    /// This is the one implementation — `CadenceFocusSupport.dueLabel(forDueDateKey:todayKey:)`
    /// forwards here. It lives in this enum rather than beside the focus helper because that is
    /// where the widget target's callers already look for it; the `nonisolated` marks are kept
    /// explicit for the same reason, since widget timeline providers run off the main actor.
    ///
    /// Returns `nil` — never a generic stand-in string — when the task has no due date, so a task
    /// due later can never render identically to one with no deadline at all. An overdue task
    /// names its date instead of saying a bare "Overdue"; the date is the part the reader needs.
    ///
    /// The widget copy used to name near dates by weekday ("Due Fri") and guard that with a
    /// six-day cutoff, because weekday names repeat at seven days. Both are gone with the weekday
    /// names: the only relative word left is "tomorrow", which is an exact one-day offset and so
    /// needs no window.
    nonisolated static func dueLabel(for dueDate: String, todayKey: String) -> String? {
        let key = dueDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if key == todayKey { return "Due today" }

        let day = dayLabel(fromKey: key)
        if key < todayKey { return "Overdue \(day)" }

        if let today = parsedDate(fromKey: todayKey),
           let date = parsedDate(fromKey: key),
           Calendar.current.dateComponents([.day], from: today, to: date).day == 1 {
            return "Due tomorrow"
        }
        return "Due \(day)"
    }

    /// "Aug 14" for a `yyyy-MM-dd` key, falling back to the raw key when it cannot be parsed.
    /// Literally `DateFormatters.shortDateString(from:)` — the app and the widget say the date the
    /// same way because they now say it with the same formatter.
    nonisolated static func dayLabel(fromKey key: String) -> String {
        DateFormatters.shortDateString(from: key)
    }

    /// Resolves a `yyyy-MM-dd` key to midnight in the current calendar's time zone.
    nonisolated static func parsedDate(fromKey key: String) -> Date? {
        DateFormatters.date(from: key, in: .current)
    }
}
