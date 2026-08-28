#if os(macOS)
import SwiftUI

struct TaskSurfaceFreezeState<PrimarySnapshot, SecondarySnapshot> {
    var frozenOrder: [AppTask]?
    var primarySnapshot: [PrimarySnapshot]?
    var secondarySnapshot: [SecondarySnapshot]?

    /// `true` when this call actually froze something. See `TaskSurfaceFreezeCoordinator.capture`
    /// for why callers must not write the result back to their bindings otherwise.
    @discardableResult
    mutating func captureIfNeeded(
        naturalTasks: [AppTask],
        sourcePrimarySnapshot: [PrimarySnapshot],
        sourceSecondarySnapshot: [SecondarySnapshot]
    ) -> Bool {
        TaskSurfaceFreezeSupport.captureIfNeeded(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primarySnapshot,
            secondarySnapshot: &secondarySnapshot,
            naturalTasks: naturalTasks,
            sourcePrimarySnapshot: sourcePrimarySnapshot,
            sourceSecondarySnapshot: sourceSecondarySnapshot
        )
    }

    mutating func release() {
        TaskSurfaceFreezeSupport.releaseIfPossible(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primarySnapshot,
            secondarySnapshot: &secondarySnapshot
        )
    }
}

struct FrozenTaskGroupSnapshot: Identifiable {
    let id: String
    let title: String
    let accent: Color
    let taskIDs: [UUID]
}

struct ResolvedFrozenTaskGroup: Identifiable {
    let id: String
    let title: String
    let accent: Color
    let tasks: [AppTask]
}

/// T-342: the freeze holds a task in place so a row does not jump out from under the pointer, and
/// releases it once the task is over. "Over" is `isFinishedTask` — done **or** cancelled — not
/// `isDone`. Filtering on `isDone` alone kept a task cancelled during the freeze pinned to the top
/// of an *active* list until the freeze released, while a task completed in the same breath left
/// immediately: half a rule, so half the tasks.
func applyFrozenTaskOrder(_ sorted: [AppTask], frozen: [AppTask]?) -> [AppTask] {
    guard let frozen else { return sorted }
    let activeFrozen = frozen.filter { !CadenceTaskQuerySupport.isFinishedTask($0) }
    let frozenIDs = Set(activeFrozen.map(\.id))
    return activeFrozen + sorted.filter { !frozenIDs.contains($0.id) }
}

/// Same rule as `applyFrozenTaskOrder`, and the same T-342 fix: a frozen group empties out when its
/// tasks are finished, whichever way they finished. A group left holding only cancelled work used
/// to survive the `isEmpty` check and keep rendering.
func resolveFrozenTaskGroups(_ frozen: [FrozenTaskGroupSnapshot]?, from allTasks: [AppTask]) -> [ResolvedFrozenTaskGroup]? {
    guard let frozen else { return nil }
    let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
    return frozen.compactMap { group in
        let resolvedTasks = group.taskIDs
            .compactMap { tasksByID[$0] }
            .filter { !CadenceTaskQuerySupport.isFinishedTask($0) }
        guard !resolvedTasks.isEmpty else { return nil }
        return ResolvedFrozenTaskGroup(
            id: group.id,
            title: group.title,
            accent: group.accent,
            tasks: resolvedTasks
        )
    }
}
#endif
