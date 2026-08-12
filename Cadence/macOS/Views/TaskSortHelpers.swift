#if os(macOS)
import Foundation

/// Free-function spelling of `TaskPriority.rank`, kept because the sort comparators below read
/// better with it. This was a seventh hand-written copy of the same switch — and the one driving
/// every macOS task sort — missed by an earlier consolidation because it is spelled
/// `taskPriorityRank` rather than `priorityRank`.
func taskPriorityRank(_ priority: TaskPriority) -> Int { priority.rank }

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

        let lhsTimed = lhs.scheduledStartMin >= 0
        let rhsTimed = rhs.scheduledStartMin >= 0
        if lhsTimed != rhsTimed { return lhsTimed }
        if lhsTimed, lhs.scheduledStartMin != rhs.scheduledStartMin {
            return direction == .ascending
                ? lhs.scheduledStartMin < rhs.scheduledStartMin
                : lhs.scheduledStartMin > rhs.scheduledStartMin
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

// Date bucketing deliberately does *not* live here. `TaskDateBuckets` / `classifyTasksByDate`
// used to sit below this line as a line-for-line twin of `CadenceTaskQuerySupport.dateBuckets`,
// with zero production callers — so the only test of the bucketing rule tested the copy nothing
// ran. Use `CadenceTaskQuerySupport.dateBuckets(for:todayKey:)` and `CadenceTaskDateBuckets`.
#endif
