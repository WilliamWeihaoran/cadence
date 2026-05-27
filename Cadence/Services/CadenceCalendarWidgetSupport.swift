import Foundation
import SwiftData

enum CadenceCalendarWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

struct CadenceCalendarWidgetDay: Identifiable, Hashable {
    let dateKey: String
    let weekdayLabel: String
    let dayNumberLabel: String
    let dueCount: Int
    let scheduledCount: Int
    let totalCount: Int
    let isToday: Bool

    var id: String { dateKey }
}

struct CadenceCalendarWidgetSnapshot: Hashable {
    let date: Date
    let state: CadenceCalendarWidgetSnapshotState
    let statusMessage: String?
    let days: [CadenceCalendarWidgetDay]
    let overdueCount: Int
    let upcomingTitle: String?

    var calendarURL: URL {
        CadenceDeepLink.calendar.url
    }

    var isUnavailable: Bool {
        state == .unavailable
    }
}

enum CadenceCalendarWidgetSupport {
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

        let upcomingTitle = CadenceTodayWidgetSupport
            .todayTasks(from: openTasks, todayKey: todayKey)
            .first?
            .title

        let totalVisibleCount = days.reduce(0) { $0 + $1.totalCount }

        return CadenceCalendarWidgetSnapshot(
            date: today,
            state: totalVisibleCount == 0 && overdueCount == 0 ? .empty : .ready,
            statusMessage: nil,
            days: days,
            overdueCount: overdueCount,
            upcomingTitle: upcomingTitle
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
