#if os(macOS)
import SwiftData
import Foundation

extension ModelContext {
    /// - Returns: `false` when the delete could not be committed and was rolled back (T-365).
    ///   `@discardableResult` because most rows have nothing to do with the answer — the rollback
    ///   puts the row back on screen by itself — but the answer exists now, which it did not when
    ///   the shared core swallowed its save.
    @discardableResult
    func deleteTask(
        _ task: AppTask,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let taskID = task.id
        return deleteTasks(withIDs: [taskID], commit: commit)
    }

    /// Deletes the given tasks and everything hanging off them. Returns `false` — having changed
    /// nothing — when the delete did not go through.
    ///
    /// The deletion itself lives in `CadenceTaskMutationSupport.deleteTasks(withIDs:…)`, which is
    /// also iOS's only delete path; this wrapper exists solely to supply the two macOS-only hooks
    /// (singleton state teardown, and the focus session that a disposed bundle invalidates). The
    /// two implementations used to be independent, and the iOS one had drifted into losing empty
    /// bundles, pending notifications, and relationship detachment. Add behaviour to the shared
    /// core, not here, unless it is genuinely AppKit-shaped.
    ///
    /// `commitsImmediately` is forwarded rather than fixed here so the list cascades can defer the
    /// commit to the confirmation that owns it — see the shared core for why. `commit` is
    /// forwarded for the same reason: the wrapper is the only macOS-side delete path, so a test
    /// that wants to watch a refused commit travel back out through it needs the seam here too.
    ///
    /// The `false` this returns used to mean one thing — the store could not be read — and now
    /// means two; the other is a commit that was refused and rolled back. Both leave the store
    /// exactly as it was, which is why one return value can carry them.
    @discardableResult
    func deleteTasks(
        withIDs taskIDs: Set<UUID>,
        commitsImmediately: Bool = true,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        CadenceTaskMutationSupport.deleteTasks(
            withIDs: taskIDs,
            modelContext: self,
            commitsImmediately: commitsImmediately,
            commit: commit,
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
