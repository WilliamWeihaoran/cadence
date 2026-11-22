import Foundation
import SwiftData

/// **A task row let go over another row on Today, All Tasks or Inbox, on iPhone and iPad as on the
/// Mac ([[T-19100]]).**
///
/// [[T-18544]] gave iOS's rows a drop destination (`iOSTaskRowReorderDropModifier`) and wired it
/// only on a list's Tasks tab, so the same drop on Today, All Tasks or Inbox did nothing while the
/// Mac refiled the row into the target's group and renumbered it in front of the target. No
/// hardware constraint answered that split ([[T-8201]]): the touch lift is the same system drag
/// carrying the same `TaskDragPayload` string. The decision is the Mac's own
/// `TasksPanelDropCoordinator.handleTaskDrop` -- assign the target group's key, add a row it joined
/// to the scope ([[T-17112]]), renumber, and stop on a refused re-file ([[T-17115]]) -- moved to
/// `Shared/` for this; what this adds is the Mac pages' lookups, filled in from the page and the
/// store the way `CadenceTaskHeaderDrop.dropTask` fills in the heading drop's:
///
/// - the assign is `CadenceTaskHeaderDrop.assignTask`, with the lists read at drop time;
/// - the renumber is `CadenceTaskRowReorder.reorderTask`, spanning **every** task in the store
///   ([[T-1175]]): both Mac pages span their whole `allTasks` query, because a Today group or an
///   Inbox page is a strict slice of the list the `order` sequence covers;
/// - the off-screen notice is asked before the renumber and reported after it (T-1119).
///
/// The answer is `ListTasksGroupDrop.HeaderDropOutcome`, the three cases a list's Tasks tab already
/// draws: `.applied` with the off-screen notice, `.refused` with the sentence for whichever half
/// the store refused, `.resolvedNothing` for a payload the page does not hold or a row dropped on
/// itself -- the row springing back is that whole report (T-591).
enum CadenceTaskRowDrop {
    static func drop(
        payload: String,
        onto target: AppTask,
        scopeTasks: [AppTask],
        dropKey: String?,
        among pageTasks: [AppTask],
        todayKey: String,
        modelContext: ModelContext,
        sortKeyOrder: @escaping (AppTask, AppTask) -> TaskSortKeyOrder,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) -> ListTasksGroupDrop.HeaderDropOutcome {
        var outcome = ListTasksGroupDrop.HeaderDropOutcome.resolvedNothing
        let coordinator = TasksPanelDropCoordinator(
            allTasks: pageTasks,
            taskIDFromPayload: { TaskDragPayload.taskID(from: $0) },
            assignTask: { task, key in
                let assigned = CadenceTaskHeaderDrop.assignTask(
                    task,
                    for: key,
                    todayKey: todayKey,
                    areas: (try? modelContext.fetch(FetchDescriptor<Area>())) ?? [],
                    projects: (try? modelContext.fetch(FetchDescriptor<Project>())) ?? [],
                    modelContext: modelContext,
                    reconciler: reconciler,
                    commit: commit
                )
                if assigned == .refused {
                    outcome = .refused(notice: CadencePendingChangePersistence.editFailureNotice)
                }
                return assigned
            },
            reorderTask: { droppedID, targetID, scope in
                let landing = CadenceReorderVisibility.notice(
                    droppedID: droppedID,
                    targetID: targetID,
                    in: scope,
                    sortKeyOrder: sortKeyOrder
                )
                let reordered = CadenceTaskRowReorder.reorderTask(
                    droppedID: droppedID,
                    targetID: targetID,
                    scopeTasks: scope,
                    spanTasks: (try? modelContext.fetch(FetchDescriptor<AppTask>())) ?? pageTasks,
                    modelContext: modelContext,
                    commit: commit
                )
                outcome = reordered
                    ? .applied(notice: landing)
                    : .refused(notice: CadenceOrderCommit.failureNotice)
                return reordered
            }
        )
        _ = coordinator.handleTaskDrop(
            payload: payload,
            targetTask: target,
            scopeTasks: scopeTasks,
            dropKey: dropKey
        )
        return outcome
    }
}
