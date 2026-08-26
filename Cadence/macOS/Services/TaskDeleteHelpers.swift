#if os(macOS)
import SwiftData
import Foundation

extension ModelContext {
    func deleteTask(_ task: AppTask) {
        let taskID = task.id
        deleteTasks(withIDs: [taskID])
    }

    /// Deletes the given tasks and everything hanging off them. Returns `false` — having changed
    /// nothing — when the store could not be read.
    ///
    /// The deletion itself lives in `CadenceTaskMutationSupport.deleteTasks(withIDs:…)`, which is
    /// also iOS's only delete path; this wrapper exists solely to supply the two macOS-only hooks
    /// (singleton state teardown, and the focus session that a disposed bundle invalidates). The
    /// two implementations used to be independent, and the iOS one had drifted into losing empty
    /// bundles, pending notifications, and relationship detachment. Add behaviour to the shared
    /// core, not here, unless it is genuinely AppKit-shaped.
    ///
    /// `commitsImmediately` is forwarded rather than fixed here so the list cascades can defer the
    /// commit to the confirmation that owns it — see the shared core for why.
    @discardableResult
    func deleteTasks(withIDs taskIDs: Set<UUID>, commitsImmediately: Bool = true) -> Bool {
        CadenceTaskMutationSupport.deleteTasks(
            withIDs: taskIDs,
            modelContext: self,
            commitsImmediately: commitsImmediately,
            willDelete: { ids in
                Self.cancelTaskState(for: ids)
            },
            didDeleteBundles: { deletedBundleIDs in
                if let activeBundle = FocusManager.shared.activeBundle,
                   deletedBundleIDs.contains(activeBundle.id) {
                    FocusManager.shared.activeSession = nil
                    FocusManager.shared.reset()
                }
            }
        )
    }

    private static func cancelTaskState(for taskIDs: Set<UUID>) {
        for taskID in taskIDs {
            TaskCompletionAnimationManager.shared.cancelPending(for: taskID)
            TaskCompletionAnimationManager.shared.cancelCancelPending(for: taskID)
        }

        if let hoveredTask = HoveredTaskManager.shared.hoveredTask,
           taskIDs.contains(hoveredTask.id) {
            HoveredTaskManager.shared.clear()
        }
        if let requestedTaskID = TaskSubtaskEntryManager.shared.requestedTaskID,
           taskIDs.contains(requestedTaskID) {
            TaskSubtaskEntryManager.shared.requestedTaskID = nil
        }
        if let activeTask = FocusManager.shared.activeTask,
           taskIDs.contains(activeTask.id) {
            FocusManager.shared.activeSession = nil
            FocusManager.shared.reset()
        }
        FocusManager.shared.selectedBundleTaskIDs.subtract(taskIDs)
    }
}
#endif
