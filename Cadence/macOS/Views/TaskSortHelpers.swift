#if os(macOS)
import Foundation

func taskPriorityRank(_ priority: TaskPriority) -> Int {
    switch priority {
    case .none: return 0
    case .low: return 1
    case .medium: return 2
    case .high: return 3
    }
}

private func taskSortFallbackPrecedes(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
    if lhs.order != rhs.order { return lhs.order < rhs.order }
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }

    let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
    if titleComparison != .orderedSame { return titleComparison == .orderedAscending }

    return lhs.id.uuidString < rhs.id.uuidString
}

/// Returns true if `lhs` should sort before `rhs` under the given field and direction.
/// This is the canonical comparison used by both `taskSorted` and any inline sort in views.
func taskSortPrecedes(_ lhs: AppTask, _ rhs: AppTask, field: TaskSortField, direction: TaskSortDirection) -> Bool {
    switch field {
    case .custom:
        return taskSortFallbackPrecedes(lhs, rhs)
    case .date:
        let ld = lhs.scheduledDate.isEmpty ? "9999-99-99" : lhs.scheduledDate
        let rd = rhs.scheduledDate.isEmpty ? "9999-99-99" : rhs.scheduledDate
        if ld != rd {
            return direction == .ascending ? ld < rd : ld > rd
        }
        return taskSortFallbackPrecedes(lhs, rhs)
    case .priority:
        let lp = taskPriorityRank(lhs.priority)
        let rp = taskPriorityRank(rhs.priority)
        if lp != rp {
            return direction == .ascending ? lp < rp : lp > rp
        }
        return taskSortFallbackPrecedes(lhs, rhs)
    }
}

extension Array where Element == AppTask {
    func taskSorted(by field: TaskSortField, direction: TaskSortDirection) -> [AppTask] {
        sorted { taskSortPrecedes($0, $1, field: field, direction: direction) }
    }
}

struct TaskDateBuckets {
    let overdueIDs: Set<UUID>
    let dueTodayIDs: Set<UUID>
    let doTodayIDs: Set<UUID>

    func contains(_ task: AppTask) -> Bool {
        overdueIDs.contains(task.id) || dueTodayIDs.contains(task.id) || doTodayIDs.contains(task.id)
    }
}

func classifyTasksByDate(_ tasks: [AppTask], todayKey: String) -> TaskDateBuckets {
    var overdueIDs = Set<UUID>()
    var dueTodayIDs = Set<UUID>()
    var doTodayIDs = Set<UUID>()

    for task in tasks {
        if !task.dueDate.isEmpty && task.dueDate < todayKey {
            overdueIDs.insert(task.id)
        } else if task.dueDate == todayKey {
            dueTodayIDs.insert(task.id)
        }
    }

    for task in tasks where !overdueIDs.contains(task.id) && !dueTodayIDs.contains(task.id) {
        if task.scheduledDate == todayKey {
            doTodayIDs.insert(task.id)
        }
    }

    return TaskDateBuckets(
        overdueIDs: overdueIDs,
        dueTodayIDs: dueTodayIDs,
        doTodayIDs: doTodayIDs
    )
}
#endif
