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
        let todayTasks = todayTasks(from: tasks, todayKey: todayKey)
            .filter { !suppressedTaskIDs.contains($0.id) }
        let overdue = todayTasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
        let dueToday = todayTasks.filter { $0.dueDate == todayKey }
        let scheduledToday = todayTasks.filter { $0.scheduledDate == todayKey && $0.dueDate != todayKey }
        let state: CadenceTodayWidgetSnapshotState = todayTasks.isEmpty ? .empty : .ready

        return CadenceTodayWidgetSnapshot(
            date: Date(),
            dateKey: todayKey,
            state: state,
            statusMessage: nil,
            totalCount: todayTasks.count,
            overdueCount: overdue.count,
            dueTodayCount: dueToday.count,
            scheduledTodayCount: scheduledToday.count,
            tasks: Array(todayTasks.prefix(max(limit, 0))).map(widgetTask)
        )
    }

    nonisolated static func unavailableSnapshot(
        todayKey: String = currentTodayKey(),
        message: String = "Open Cadence once to finish loading your shared data."
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
        tasks
            .filter { task in
                guard !task.isDone && !task.isCancelled else { return false }
                return task.scheduledDate == todayKey ||
                    task.dueDate == todayKey ||
                    (!task.dueDate.isEmpty && task.dueDate < todayKey)
            }
            .sorted { lhs, rhs in
                let leftRank = rank(lhs, todayKey: todayKey)
                let rightRank = rank(rhs, todayKey: todayKey)
                if leftRank != rightRank { return leftRank < rightRank }
                if lhs.priority != rhs.priority {
                    return priorityRank(lhs.priority) > priorityRank(rhs.priority)
                }
                return lhs.order < rhs.order
            }
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
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
