#if os(macOS)
import SwiftData
import Foundation

extension ModelContext {
    func deleteTask(_ task: AppTask) {
        let taskID = task.id
        deleteTasks(withIDs: [taskID])
    }

    func deleteTasks(withIDs taskIDs: Set<UUID>) {
        guard !taskIDs.isEmpty else { return }

        cancelTaskState(for: taskIDs)

        let descriptor = FetchDescriptor<AppTask>()
        let allTasks = (try? fetch(descriptor)) ?? []
        let tasks = allTasks.filter { taskIDs.contains($0.id) }
        guard !tasks.isEmpty else { return }

        let subtasks = ((try? fetch(FetchDescriptor<Subtask>())) ?? [])
            .filter { subtask in
                guard let parentTask = subtask.parentTask else { return false }
                return taskIDs.contains(parentTask.id)
            }

        for subtask in subtasks {
            subtask.parentTask = nil
            delete(subtask)
        }

        let touchedBundles = uniqueBundles(from: tasks.compactMap(\.bundle))
        CadenceTaskRecurrenceWorkflowSupport.repairDanglingRecurrenceLinks(forDeleted: tasks, allTasks: allTasks)

        for task in tasks {
            detachRelationships(for: task)
            delete(task)
        }

        let deletedBundleIDs = deleteEmptyBundles(touchedBundles)
        if let activeBundle = FocusManager.shared.activeBundle,
           deletedBundleIDs.contains(activeBundle.id) {
            FocusManager.shared.activeSession = nil
            FocusManager.shared.reset()
        }
        processPendingChanges()
        try? save()

        // Cheaper than a full reconcile since we already know exactly which tasks were removed.
        Task { await NotificationManager.shared.cancel(taskIDs: Array(taskIDs)) }
    }

    private func cancelTaskState(for taskIDs: Set<UUID>) {
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

    private func detachRelationships(for task: AppTask) {
        let taskID = task.id

        if !task.calendarEventID.isEmpty {
            SchedulingActions.removeFromCalendar(task)
        }

        if let area = task.area {
            area.tasks = (area.tasks ?? []).filter { $0.id != taskID }
        }
        if let project = task.project {
            project.tasks = (project.tasks ?? []).filter { $0.id != taskID }
        }
        if let context = task.context {
            context.tasks = (context.tasks ?? []).filter { $0.id != taskID }
        }
        if let goal = task.goal {
            goal.tasks = (goal.tasks ?? []).filter { $0.id != taskID }
        }
        if let bundle = task.bundle {
            bundle.tasks = (bundle.tasks ?? []).filter { $0.id != taskID }
        }
        for tag in task.tags ?? [] {
            tag.tasks = (tag.tasks ?? []).filter { $0.id != taskID }
        }

        task.area = nil
        task.project = nil
        task.context = nil
        task.goal = nil
        task.bundle = nil
        task.bundleOrder = 0
        task.tags = []
        task.subtasks = []
    }

    @discardableResult
    private func deleteEmptyBundles(_ bundles: [TaskBundle]) -> Set<UUID> {
        var deletedIDs = Set<UUID>()
        for bundle in bundles where (bundle.tasks ?? []).isEmpty {
            deletedIDs.insert(bundle.id)
            delete(bundle)
        }
        return deletedIDs
    }

    private func uniqueBundles(from bundles: [TaskBundle]) -> [TaskBundle] {
        var seen = Set<UUID>()
        return bundles.filter { seen.insert($0.id).inserted }
    }
}
#endif
