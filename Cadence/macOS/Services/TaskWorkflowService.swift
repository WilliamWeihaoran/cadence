#if os(macOS)
import SwiftData
import Foundation

enum TaskWorkflowService {
    @discardableResult
    static func markDone(_ task: AppTask, in context: ModelContext) -> AppTask? {
        let spawned = CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context)
        // Fast-path reconcile so a just-completed task's pending "starting now"/"due today"
        // notification is promptly cleared — a stale nudge firing after completion would be a
        // visibly broken behavior. The scenePhase checkpoint is the correctness safety net for
        // any site that doesn't call this.
        HabitNotificationReconcileSupport.scheduleReconcile(in: context)
        return spawned
    }

    @discardableResult
    static func markCancelled(_ task: AppTask, in context: ModelContext) -> AppTask? {
        let spawned = CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: context)
        HabitNotificationReconcileSupport.scheduleReconcile(in: context)
        return spawned
    }

    // MARK: - The committing spellings (T-628)

    /// `markDone`, with a commit boundary.
    ///
    /// **The funnel had none at all.** `TaskCompletionAnimationManager.write` reached
    /// `markDone(_:in:)`, which reaches `spawnNextOccurrenceIfNeeded`, which does
    /// `context.insert(nextTask)` — and nothing anywhere in that chain saved. Ticking a recurring
    /// task's circle on macOS therefore created its successor as a *pending* row in the app's one
    /// `ModelContext`, for the next unrelated `save()` from any other screen to take or the next
    /// unrelated `rollback()` to discard. T-327 measured the sibling of that: a delete flushed by
    /// nobody came back next launch. Autosave's `true` default is not a commit boundary, because
    /// "eventually" is the whole problem.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    static func commitMarkDone(
        _ task: AppTask,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try commitSettle(task, in: context, commit: commit) { markDone(task, in: context) }
    }

    /// `markCancelled`, with a commit boundary. Cancelling advances the series too (T-202), so it
    /// inserts exactly as completing does.
    static func commitMarkCancelled(
        _ task: AppTask,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try commitSettle(task, in: context, commit: commit) { markCancelled(task, in: context) }
    }

    /// Settle a task and commit it, putting **both** halves back when the commit is refused.
    ///
    /// **The body is `CadenceTaskMutationSupport.commitSettle` now (T-636).** It was written here
    /// for T-628 and imported nothing platform-specific, so when the iOS completion spine needed
    /// the identical sentence the choice was one shared body or two copies asserted to agree. This
    /// spelling delegates and must not grow a body of its own — the same rule, for the same
    /// reason, as `rollOverTaskToToday` two files over.
    private static func commitSettle(
        _ task: AppTask,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void,
        _ settle: () -> AppTask?
    ) throws {
        try CadenceTaskMutationSupport.commitSettle(task, in: context, commit: commit, settle)
    }

    static func markTodo(_ task: AppTask) {
        CadenceTaskRecurrenceWorkflowSupport.markTodo(task)
        if let context = task.modelContext {
            HabitNotificationReconcileSupport.scheduleReconcile(in: context)
        }
    }

    static func ensureRecurrenceSeriesMetadata(for task: AppTask) {
        CadenceTaskRecurrenceWorkflowSupport.ensureRecurrenceSeriesMetadata(for: task)
    }

    static func applyRecurrenceRule(
        _ rule: TaskRecurrenceRule,
        to task: AppTask,
        allTasks: [AppTask],
        scope: CadenceTaskRecurrenceEditScope
    ) {
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
            rule,
            to: task,
            allTasks: allTasks,
            scope: scope
        )
    }

    static func recurrenceTargets(
        from task: AppTask,
        allTasks: [AppTask],
        scope: CadenceTaskRecurrenceEditScope
    ) -> [AppTask] {
        CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: task,
            allTasks: allTasks,
            scope: scope
        )
    }
}

// `TaskContainerLifecycleService` is NOT here any more. T-215 moved it to
// `Cadence/Services/CadenceTaskContainerLifecycleService.swift`: it sat inside this file's
// `#if os(macOS)` importing nothing platform-specific, which is what left iOS's list archive a
// bare `status = .archived` while macOS's cancelled the list's remaining active tasks. Same move,
// and same reason, as `RemindersManager`, `PrivacyDataResetService` and `ListDeleteHelpers` —
// except those three left whole-file tombstones and this one is a comment, because
// `TaskWorkflowService` itself stays: it is the macOS wrapper that adds the notification
// reconcile hop around the shared recurrence transitions.

#endif
