#if os(macOS)
import SwiftData
import Foundation

enum TaskWorkflowService {
    static func markDone(_ task: AppTask, in context: ModelContext) {
        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context)
        // Fast-path reconcile so a just-completed task's pending "starting now"/"due today"
        // notification is promptly cleared — a stale nudge firing after completion would be a
        // visibly broken behavior. The scenePhase checkpoint is the correctness safety net for
        // any site that doesn't call this.
        HabitNotificationReconcileSupport.scheduleReconcile(in: context)
    }

    static func markCancelled(_ task: AppTask, in context: ModelContext) {
        CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: context)
        HabitNotificationReconcileSupport.scheduleReconcile(in: context)
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
