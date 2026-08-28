import Foundation
import SwiftData

nonisolated enum CadenceCalendarWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

nonisolated struct CadenceCalendarWidgetDay: Identifiable, Hashable {
    let dateKey: String
    let weekdayLabel: String
    let dayNumberLabel: String
    let dueCount: Int
    let scheduledCount: Int
    let totalCount: Int
    let isToday: Bool

    var id: String { dateKey }
}

nonisolated struct CadenceCalendarWidgetSnapshot: Hashable {
    let date: Date
    let state: CadenceCalendarWidgetSnapshotState
    let statusMessage: String?
    let days: [CadenceCalendarWidgetDay]
    let overdueCount: Int
    let upcomingTitle: String?
    /// `yyyy-MM-dd` due date of the `upcomingTitle` task, empty when it has none. Defaulted so
    /// snapshot literals that only care about the title stay source-compatible.
    var upcomingDueDate: String = ""

    /// Points at the day this snapshot is *about*, which is the first cell of the strip it draws.
    /// See `CadenceDeepLink.calendar` for what a link without one used to do.
    var calendarURL: URL {
        CadenceDeepLink.calendar(dateKey: CadenceWidgetDateSupport.dateKey(from: date)).url
    }

    var isUnavailable: Bool {
        state == .unavailable
    }
}

nonisolated enum CadenceCalendarWidgetSupport {
    nonisolated static func snapshot(
        modelContext: ModelContext,
        dayCount: Int
    ) throws -> CadenceCalendarWidgetSnapshot {
        let today = Calendar.current.startOfDay(for: Date())
        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        return snapshot(from: tasks, today: today, dayCount: dayCount)
    }

    nonisolated static func snapshot(
        from tasks: [AppTask],
        today: Date = Calendar.current.startOfDay(for: Date()),
        dayCount: Int
    ) -> CadenceCalendarWidgetSnapshot {
        let safeDayCount = max(dayCount, 1)
        let calendar = Calendar.current
        let todayKey = CadenceWidgetDateSupport.dateKey(from: today)
        let openTasks = tasks.filter { !$0.isDone && !$0.isCancelled }
        let days = (0..<safeDayCount).compactMap { offset -> CadenceCalendarWidgetDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let dateKey = CadenceWidgetDateSupport.dateKey(from: date)
            let dueCount = openTasks.filter { $0.dueDate == dateKey }.count
            let scheduledOnlyCount = openTasks.filter {
                $0.scheduledDate == dateKey && $0.dueDate != dateKey
            }.count
            return CadenceCalendarWidgetDay(
                dateKey: dateKey,
                weekdayLabel: CadenceWidgetDateSupport.weekdayLabel(from: date),
                dayNumberLabel: CadenceWidgetDateSupport.dayNumberLabel(from: date),
                dueCount: dueCount,
                scheduledCount: scheduledOnlyCount,
                totalCount: dueCount + scheduledOnlyCount,
                isToday: offset == 0
            )
        }

        let overdueCount = openTasks.filter {
            !$0.dueDate.isEmpty && $0.dueDate < todayKey
        }.count

        let upcomingTask = CadenceTodayWidgetSupport
            .todayTasks(from: openTasks, todayKey: todayKey)
            .first

        // **`upcomingTask != nil` is load-bearing, not belt-and-braces.** `.empty` is not a
        // count — it swaps the whole body for `emptyState`, and "Next up" is inside the branch it
        // replaces. So a store whose only open work is a task planned for an earlier day rendered
        // the empty state even once `todayTasks` could see it: `days` spans today forward, and
        // `overdueCount` is due-dates only, so neither term has a past-do branch. That is the same
        // missing rule as T-353, a third time, and fixing the picker alone left this widget still
        // saying nothing was urgent while the app's Today page had work on it. Asking the picker
        // whether it found anything reuses `AppTask.isTodayWork` instead of adding a fourth date
        // comparison here.
        let totalVisibleCount = days.reduce(0) { $0 + $1.totalCount }
        let isEmpty = totalVisibleCount == 0 && overdueCount == 0 && upcomingTask == nil

        return CadenceCalendarWidgetSnapshot(
            date: today,
            state: isEmpty ? .empty : .ready,
            statusMessage: nil,
            days: days,
            overdueCount: overdueCount,
            upcomingTitle: upcomingTask?.title,
            upcomingDueDate: upcomingTask?.dueDate ?? ""
        )
    }

    nonisolated static func unavailableSnapshot(
        today: Date = Calendar.current.startOfDay(for: Date()),
        message: String = "Open Cadence once to finish setting up shared widget data."
    ) -> CadenceCalendarWidgetSnapshot {
        CadenceCalendarWidgetSnapshot(
            date: today,
            state: .unavailable,
            statusMessage: message,
            days: [],
            overdueCount: 0,
            upcomingTitle: nil
        )
    }

    nonisolated static func recommendedReloadDate(
        for snapshot: CadenceCalendarWidgetSnapshot,
        referenceDate: Date = Date()
    ) -> Date {
        let fallbackInterval: TimeInterval
        switch snapshot.state {
        case .unavailable:
            fallbackInterval = 5 * 60
        case .empty:
            fallbackInterval = 45 * 60
        case .ready:
            fallbackInterval = 20 * 60
        }

        let calendar = Calendar.current
        let nextStartOfDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        ).addingTimeInterval(60)
        return min(referenceDate.addingTimeInterval(fallbackInterval), nextStartOfDay)
    }
}
