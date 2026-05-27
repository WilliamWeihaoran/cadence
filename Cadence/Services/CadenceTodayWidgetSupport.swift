import Foundation
import SwiftData

enum CadenceTodayWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

struct CadenceTodayWidgetTask: Identifiable, Hashable {
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

struct CadenceTodayWidgetSnapshot: Hashable {
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

enum CadenceTodayWidgetSupport {
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
        tasks.compactMap { task -> (task: AppTask, rank: Int, priorityRank: Int, order: Int)? in
            guard !task.isDone && !task.isCancelled else { return nil }
            let taskRank = rank(task, todayKey: todayKey)
            guard taskRank < 3 else { return nil }
            return (task, taskRank, priorityRank(task.priority), task.order)
        }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.priorityRank != rhs.priorityRank {
                    return lhs.priorityRank > rhs.priorityRank
                }
                return lhs.order < rhs.order
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

    private nonisolated static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }

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

enum CadenceWidgetDateSupport {
    nonisolated static func dateKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    nonisolated static func weekdayLabel(from date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    nonisolated static func dayNumberLabel(from date: Date) -> String {
        date.formatted(.dateTime.day())
    }
}
