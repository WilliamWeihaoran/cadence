#if os(macOS)
import SwiftUI

struct TaskSurfaceFreezeState<PrimarySnapshot, SecondarySnapshot> {
    var frozenOrder: [AppTask]?
    var primarySnapshot: [PrimarySnapshot]?
    var secondarySnapshot: [SecondarySnapshot]?

    mutating func captureIfNeeded(
        naturalTasks: [AppTask],
        sourcePrimarySnapshot: [PrimarySnapshot],
        sourceSecondarySnapshot: [SecondarySnapshot]
    ) {
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

func applyFrozenTaskOrder(_ sorted: [AppTask], frozen: [AppTask]?) -> [AppTask] {
    guard let frozen else { return sorted }
    let activeFrozen = frozen.filter { !$0.isDone }
    let frozenIDs = Set(activeFrozen.map(\.id))
    return activeFrozen + sorted.filter { !frozenIDs.contains($0.id) }
}

func resolveFrozenTaskGroups(_ frozen: [FrozenTaskGroupSnapshot]?, from allTasks: [AppTask]) -> [ResolvedFrozenTaskGroup]? {
    guard let frozen else { return nil }
    let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
    return frozen.compactMap { group in
        let resolvedTasks = group.taskIDs.compactMap { tasksByID[$0] }.filter { !$0.isDone }
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
