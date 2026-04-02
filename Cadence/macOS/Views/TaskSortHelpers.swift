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

/// Returns true if `lhs` should sort before `rhs` under the given field and direction.
/// This is the canonical comparison used by both `taskSorted` and any inline sort in views.
func taskSortPrecedes(_ lhs: AppTask, _ rhs: AppTask, field: TaskSortField, direction: TaskSortDirection) -> Bool {
    switch field {
    case .custom:
        return lhs.order < rhs.order
    case .date:
        let ld = lhs.scheduledDate.isEmpty ? "9999-99-99" : lhs.scheduledDate
        let rd = rhs.scheduledDate.isEmpty ? "9999-99-99" : rhs.scheduledDate
        if ld != rd {
            return direction == .ascending ? ld < rd : ld > rd
        }
        return lhs.order < rhs.order
    case .priority:
        let lp = taskPriorityRank(lhs.priority)
        let rp = taskPriorityRank(rhs.priority)
        if lp != rp {
            return direction == .ascending ? lp < rp : lp > rp
        }
        return lhs.order < rhs.order
    }
}

extension Array where Element == AppTask {
    func taskSorted(by field: TaskSortField, direction: TaskSortDirection) -> [AppTask] {
        sorted { taskSortPrecedes($0, $1, field: field, direction: direction) }
    }
}
#endif
