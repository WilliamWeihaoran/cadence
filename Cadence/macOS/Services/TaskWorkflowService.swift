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

enum TaskContainerLifecycleService {
    static func completeRemainingActiveTasks(in area: Area, includingChildProjects: Bool, in context: ModelContext) {
        finishRemainingActiveTasks(tasks(in: area, includingChildProjects: includingChildProjects), as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in area: Area, includingChildProjects: Bool, in context: ModelContext) {
        finishRemainingActiveTasks(tasks(in: area, includingChildProjects: includingChildProjects), as: .cancelled, in: context)
    }

    static func completeRemainingActiveTasks(in project: Project, in context: ModelContext) {
        finishRemainingActiveTasks(project.tasks ?? [], as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in project: Project, in context: ModelContext) {
        finishRemainingActiveTasks(project.tasks ?? [], as: .cancelled, in: context)
    }

    static func completeRemainingActiveTasks(in section: TaskSectionConfig, area: Area?, project: Project?, in context: ModelContext) {
        finishRemainingActiveTasks(tasks(in: section, area: area, project: project), as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in section: TaskSectionConfig, area: Area?, project: Project?, in context: ModelContext) {
        finishRemainingActiveTasks(tasks(in: section, area: area, project: project), as: .cancelled, in: context)
    }

    /// Settling a whole container is **not** the single-task transition, and must not become it.
    /// `markDone` / `markCancelled` spawn the next recurrence occurrence into the same area,
    /// project and section, so routing this through either would refill the list or column that
    /// was just completed or archived (`docs/TODO.md` T-213, T-214). It routes through
    /// `settleWithoutAdvancingSeries` instead, which is that decision written down once.
    ///
    /// What was actually wrong here was the timestamp: `.cancelled` hand-wrote
    /// `completedAt = nil`, so archiving a list or a kanban column produced untimestamped
    /// cancellations after T-202 had made a cancellation a timestamped event everywhere else —
    /// and `completedAt` is the only ground Today's Completed section has for settled work whose
    /// dates are empty or past, the *only* one on macOS. One `Date()` for the batch, because a
    /// single click settling twelve tasks settled them all at once.
    private static func finishRemainingActiveTasks(_ tasks: [AppTask], as status: TaskStatus, in context: ModelContext) {
        let now = Date()
        for task in unique(tasks) where !task.isDone && !task.isCancelled {
            CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries(task, as: status, now: now)
        }
    }

    private static func tasks(in area: Area, includingChildProjects: Bool) -> [AppTask] {
        var result = area.tasks ?? []
        if includingChildProjects {
            for project in area.projects ?? [] {
                result.append(contentsOf: project.tasks ?? [])
            }
        }
        return result
    }

    private static func tasks(in section: TaskSectionConfig, area: Area?, project: Project?) -> [AppTask] {
        let sourceTasks = area?.tasks ?? project?.tasks ?? []
        return sourceTasks.filter {
            $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
        }
    }

    private static func unique(_ tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
    }
}
#endif
