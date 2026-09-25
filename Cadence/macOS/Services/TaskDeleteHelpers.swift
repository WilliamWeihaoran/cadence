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
    ///
    /// **The teardown is two halves now, and only one of them still runs above the commit
    /// ([[T-1351]]).** Every singleton below used to be cleared from `willDelete`, which the shared
    /// core calls *before* the rows are marked and therefore before any commit — the caller's on a
    /// cascade, its own otherwise. So a refused delete put every row back under "Nothing was
    /// removed." with the user's running focus session already ended, which is the one piece of
    /// state on this list that an alert cannot hand back.
    ///
    /// - **Hover, the completion animation and the subtask-entry field stay where they are.** They
    ///   are transient, the user re-acquires them by moving the mouse or clicking, and `willDelete`
    ///   is placed before the deletion *deliberately*: it exists to stop an animation aimed at a
    ///   row that is about to disappear. Moving a state-destructive callback earlier under a new
    ///   name is the repair R65 warns against, and this is its mirror — leaving a cheap one where
    ///   it belongs.
    /// - **Ending the focus session, and the bundle selection the user built by hand, is
    ///   deferred.** Both are decided here, while the doomed rows are still readable, and performed
    ///   only once a commit has landed: this call's own on the ordinary path, and the enclosing
    ///   `commitCascade`'s on the deferred one, through `CadenceDeferredDeleteEffects` — the queue
    ///   [[T-1348]] built for exactly this and which is no longer named for reminders.
    ///
    /// **With no queue and no commit of its own the teardown runs immediately, which is today's
    /// behaviour unchanged.** That is a caller passing `commitsImmediately: false` from outside a
    /// `commitCascade`; no such caller exists (`cascadeDeleteTasks` is the only one, and the source
    /// scan in `CadenceListCascadeRollbackTests` forbids a surface saving over a cascade's answer),
    /// and if one appears, a focus session left pointing at a row that really was deleted is a
    /// fault, not a stale label. The deferral errs toward the recoverable side in both directions.
    @discardableResult
    func deleteTasks(
        withIDs taskIDs: Set<UUID>,
        commitsImmediately: Bool = true,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        // This call's own queue when it owns the commit; the cascade's when it does not. Never
        // both: a queue released here on the deferred path would be releasing over a commit that
        // has not been attempted, which is the whole defect.
        let ownEffects = commitsImmediately ? CadenceDeferredDeleteEffects() : nil
        let effects = ownEffects ?? CadenceDeferredDeleteEffects.current

        let deleted = CadenceTaskMutationSupport.deleteTasks(
            withIDs: taskIDs,
            modelContext: self,
            commitsImmediately: commitsImmediately,
            commit: commit,
            willDelete: { ids in
                Self.cancelTransientTaskState(for: ids)
                Self.deferFocusTeardown(forTaskIDs: ids, to: effects)
            },
            didDeleteBundles: { deletedBundleIDs in
                Self.deferFocusTeardown(forBundleIDs: deletedBundleIDs, to: effects)
            }
        )

        if deleted {
            ownEffects?.release()
        }
        return deleted
    }

    /// The half that is cheap to re-acquire, and is therefore still torn down above the commit.
    private static func cancelTransientTaskState(for taskIDs: Set<UUID>) {
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
    }

    /// Decides now whether the doomed tasks invalidate the focus session or the bundle selection,
    /// and queues the teardown for a commit that has not happened yet.
    ///
    /// Decided here rather than inside the effect because by the time the effect runs the rows are
    /// deleted and committed, and reading `FocusManager.shared.activeTask.id` off one of them is a
    /// fault waiting for a fault handler.
    private static func deferFocusTeardown(forTaskIDs taskIDs: Set<UUID>, to effects: CadenceDeferredDeleteEffects?) {
        let endsTheSession = FocusManager.shared.activeTask.map { taskIDs.contains($0.id) } ?? false
        let deselects = !FocusManager.shared.selectedBundleTaskIDs.isDisjoint(with: taskIDs)
        guard endsTheSession || deselects else { return }

        Self.queueTeardown(taskIDs: taskIDs, to: effects) {
            if endsTheSession {
                FocusManager.shared.activeSession = nil
                FocusManager.shared.reset()
            }
            if deselects {
                FocusManager.shared.selectedBundleTaskIDs.subtract(taskIDs)
            }
        }
    }

    /// The same decision for the block a delete disposed of: a focus session running on a block
    /// that no longer exists has nothing left to count down.
    private static func deferFocusTeardown(forBundleIDs bundleIDs: Set<UUID>, to effects: CadenceDeferredDeleteEffects?) {
        guard let activeBundle = FocusManager.shared.activeBundle,
              bundleIDs.contains(activeBundle.id)
        else { return }

        Self.queueTeardown(taskIDs: [], to: effects) {
            FocusManager.shared.activeSession = nil
            FocusManager.shared.reset()
        }
    }

    /// `MainActor.assumeIsolated` rather than a `Task { @MainActor in … }`: every `release()` in
    /// the tree runs synchronously inside a main-actor delete surface, and hopping would put the
    /// teardown a run loop turn after the alert the user is already reading.
    private static func queueTeardown(
        taskIDs: Set<UUID>,
        to effects: CadenceDeferredDeleteEffects?,
        _ teardown: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let effects else {
            teardown()
            return
        }
        effects.hold(taskIDs: Array(taskIDs), habitIDs: []) {
            MainActor.assumeIsolated { teardown() }
        }
    }
}
#endif
