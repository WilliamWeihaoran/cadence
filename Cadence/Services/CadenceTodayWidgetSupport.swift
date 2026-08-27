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
        let tasks = try modelContext.fetch(relevantTaskFetchDescriptor(todayKey: todayKey))
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
            if !task.dueDate.isEmpty && task.dueDate < todayKey {
                overdueCount += 1
            } else if task.dueDate == todayKey {
                dueTodayCount += 1
            } else if task.scheduledDate == todayKey {
                scheduledTodayCount += 1
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

    nonisolated static func todayTasks(
        from tasks: [AppTask],
        todayKey: String
    ) -> [AppTask] {
        tasks.compactMap { task -> (task: AppTask, rank: Int, priorityRank: Int)? in
            guard !task.isDone && !task.isCancelled else { return nil }
            let taskRank = rank(task, todayKey: todayKey)
            guard taskRank < 3 else { return nil }
            return (task, taskRank, priorityRank(task.priority))
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

    private nonisolated static func rank(_ task: AppTask, todayKey: String) -> Int {
        if !task.dueDate.isEmpty && task.dueDate < todayKey { return 0 }
        if task.dueDate == todayKey { return 1 }
        if task.scheduledDate == todayKey { return 2 }
        return 3
    }

    private nonisolated static func priorityRank(_ priority: TaskPriority) -> Int { priority.rank }

    private nonisolated static func relevantTaskFetchDescriptor(todayKey: String) -> FetchDescriptor<AppTask> {
        let doneStatus = TaskStatus.done.rawValue
        let cancelledStatus = TaskStatus.cancelled.rawValue

        let predicate = #Predicate<AppTask> { task in
            task.statusRaw != doneStatus &&
            task.statusRaw != cancelledStatus &&
            (
                task.scheduledDate == todayKey ||
                task.dueDate == todayKey ||
                (task.dueDate != "" && task.dueDate < todayKey)
            )
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
    /// Gregorian regardless of `Calendar.current`'s identifier, matching `DateFormatters.ymd`,
    /// which is what every stored key was written with. The hand-rolled copy this replaces once
    /// read its components off `Calendar.current`: under a Buddhist current calendar `dateKey`
    /// then returned `"2569-08-11"`, which matches no row in the store, so the Today and Calendar
    /// widgets rendered permanently empty and every task read "Overdue".
    nonisolated static func storageCalendar(inheritingTimeZoneFrom calendar: Calendar) -> Calendar {
        DateFormatters.storageCalendar(inheritingTimeZoneFrom: calendar)
    }

    /// Calendar-injectable core. The `Calendar.current` convenience below is what the widget
    /// actually calls, but a test host is always Gregorian, so without a seam no assertion here
    /// can tell a correct implementation from one that reads `Calendar.current`'s components.
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
