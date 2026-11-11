#if os(macOS)
import SwiftData
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

/// The group's colour is deliberately NOT here. It was, and its only reader was the accent bar
/// `TaskListGroupHeader` drew; T-2084 removed that bar, and a snapshot field that nothing reads is
/// a second copy of a list's colour waiting to go stale against the one in the store.
struct FrozenTaskGroupSnapshot: Identifiable {
    let id: String
    let title: String
    let taskIDs: [UUID]
}

struct ResolvedFrozenTaskGroup: Identifiable {
    let id: String
    let title: String
    let tasks: [AppTask]
}

/// T-342: the freeze holds a task in place so a row does not jump out from under the pointer, and
/// releases it once the task is over. "Over" is `isFinishedTask` — done **or** cancelled — not
/// `isDone`. Filtering on `isDone` alone kept a task cancelled during the freeze pinned to the top
/// of an *active* list until the freeze released, while a task completed in the same breath left
/// immediately: half a rule, so half the tasks.
///
/// **A deleted row is over too ([[T-16552]]).** The freeze keeps a frozen row that has left the
/// live array on purpose -- a Today row rescheduled, an All Tasks row that stops matching the
/// filter -- and it used to keep a *deleted* one the same way: Cmd+Delete over a hovered row on
/// Today, All Tasks, the Inbox or a board left the row drawn until the pointer left the surface.
/// `frozenRowLeftTheStore` tells the two apart without touching T-342's hold on the rest.
func applyFrozenTaskOrder(_ sorted: [AppTask], frozen: [AppTask]?) -> [AppTask] {
    guard let frozen else { return sorted }
    let activeFrozen = frozen.filter { !frozenRowLeftTheStore($0) && !CadenceTaskQuerySupport.isFinishedTask($0) }
    let frozenIDs = Set(activeFrozen.map(\.id))
    return activeFrozen + sorted.filter { !frozenIDs.contains($0.id) }
}

/// **Whether a frozen row was deleted, read off the model rather than the page ([[T-16552]]).**
///
/// The page's live array cannot answer it: on Today a row the freeze holds on purpose is absent
/// from that array too. The model can, by the two signals `CadenceDetailPanelPresentation`
/// measured for a delete made in the main context (every in-app delete): `isDeleted` between the
/// delete and its save, `modelContext == nil` after it. A delete saved in another context (a
/// CloudKit import) raises neither; only a store fetch sees that, and this runs per frozen row per
/// render, so it is left out ([[T-16572]]).
///
/// A row that was never inserted also answers `true`. Every row a surface freezes came from a
/// query or a relationship, so none is free-standing; a test that freezes rows inserts them.
func frozenRowLeftTheStore(_ task: AppTask) -> Bool {
    task.isDeleted || task.modelContext == nil
}

/// **A list page's freeze reorders its rows; it never puts back a row the list no longer has
/// ([[T-16551]]).**
///
/// `applyFrozenTaskOrder` keeps a frozen row that has left the live array on purpose -- on Today a
/// row that stops matching while the pointer is over it stays put (T-342). A list's own Tasks tab
/// has no such row: its live array is every open task of the list, so the only ways a row leaves it
/// are finishing (already dropped) and leaving the list -- Move to List, or Delete Task. Both kept
/// the row drawn on the list it had left, for as long as the pointer stayed over the tab, under By
/// Date (the default), By Priority and None; By Section already dropped it at once, because
/// `resolveFrozenTaskGroups` resolves the snapshot through the list's tasks. So the frozen order is
/// read here only for the rows the list still holds.
func applyFrozenListOrder(_ sorted: [AppTask], frozen: [AppTask]?) -> [AppTask] {
    guard let frozen else { return sorted }
    let liveIDs = Set(sorted.map(\.id))
    return applyFrozenTaskOrder(sorted, frozen: frozen.filter { liveIDs.contains($0.id) })
}

/// Same rule as `applyFrozenTaskOrder`, and the same T-342 fix: a frozen group empties out when its
/// tasks are finished, whichever way they finished. A group left holding only cancelled work used
/// to survive the `isEmpty` check and keep rendering.
func resolveFrozenTaskGroups(_ frozen: [FrozenTaskGroupSnapshot]?, from allTasks: [AppTask]) -> [ResolvedFrozenTaskGroup]? {
    guard let frozen else { return nil }
    let tasksByID = CadenceIdentityMap.firstWins(allTasks.map { ($0.id, $0) })
    return frozen.compactMap { group in
        let resolvedTasks = group.taskIDs
            .compactMap { tasksByID[$0] }
            .filter { !CadenceTaskQuerySupport.isFinishedTask($0) }
        guard !resolvedTasks.isEmpty else { return nil }
        return ResolvedFrozenTaskGroup(
            id: group.id,
            title: group.title,
            tasks: resolvedTasks
        )
    }
}
#endif
