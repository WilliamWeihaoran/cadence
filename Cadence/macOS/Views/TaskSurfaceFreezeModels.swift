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
///
/// **`storeTasks` is the surface's own read of the store, and a frozen row missing from it is gone
/// ([[T-16572]]).** A delete saved in ANOTHER context -- a CloudKit import of a delete made on
/// another device -- raises neither of `frozenRowLeftTheStore`'s signals on the main context's
/// instance; only a store read sees it. Each surface already holds one: Today, All Tasks and the
/// Inbox their unfiltered `@Query` of every task, the All Tasks board the same query handed down,
/// a list's section board the list's tasks. That read refreshes when the import lands, which is
/// also what re-renders the surface, so membership in it answers at no extra fetch. It must be the
/// UNFILTERED universe, never the page's live array: a rescheduled row is still in the store and
/// T-342 keeps it.
func applyFrozenTaskOrder(_ sorted: [AppTask], frozen: [AppTask]?, storeTasks: [AppTask]) -> [AppTask] {
    guard let frozen else { return sorted }
    let stillStored = frozenRowsStillInStore(frozen, storeTasks: storeTasks)
    let activeFrozen = frozen.filter {
        stillStored.contains($0.persistentModelID)
            && !frozenRowLeftTheStore($0)
            && !CadenceTaskQuerySupport.isFinishedTask($0)
    }
    let frozenIDs = Set(activeFrozen.map(\.id))
    return activeFrozen + sorted.filter { !frozenIDs.contains($0.id) }
}

/// Which frozen rows the surface's store read still holds, by `persistentModelID` -- not by `id`,
/// since a duplicated UUID (a CloudKit double insert) must not keep a deleted twin drawn. Runs only
/// while a freeze is up, and stops scanning once every frozen row is found.
func frozenRowsStillInStore(_ frozen: [AppTask], storeTasks: [AppTask]) -> Set<PersistentIdentifier> {
    var unfound = Set(frozen.map(\.persistentModelID))
    var found = Set<PersistentIdentifier>()
    for task in storeTasks where !unfound.isEmpty {
        let id = task.persistentModelID
        if unfound.remove(id) != nil { found.insert(id) }
    }
    return found
}

/// **Whether a frozen row was deleted, read off the model rather than the page ([[T-16552]]).**
///
/// The page's live array cannot answer it: on Today a row the freeze holds on purpose is absent
/// from that array too. The model can, by the two signals `CadenceDetailPanelPresentation`
/// measured for a delete made in the main context (every in-app delete): `isDeleted` between the
/// delete and its save, `modelContext == nil` after it. A delete saved in another context (a
/// CloudKit import) raises neither; a per-row store fetch here would be one fetch per frozen row
/// per render, so that case is answered by the surface's own store read instead -- the
/// `storeTasks` membership in `applyFrozenTaskOrder` ([[T-16572]]).
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
    // Every row it hands on is in `sorted`, the list's own read, so that is its store read too.
    return applyFrozenTaskOrder(sorted, frozen: frozen.filter { liveIDs.contains($0.id) }, storeTasks: sorted)
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
