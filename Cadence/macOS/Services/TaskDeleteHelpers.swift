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
        let tasks = ((try? fetch(descriptor)) ?? [])
            .filter { taskIDs.contains($0.id) }
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

        for task in tasks {
            detachRelationships(for: task)
            delete(task)
        }

        deleteEmptyBundles(touchedBundles)
        processPendingChanges()
        try? save()
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

    private func deleteEmptyBundles(_ bundles: [TaskBundle]) {
        for bundle in bundles where (bundle.tasks ?? []).isEmpty {
            delete(bundle)
        }
    }

    private func uniqueBundles(from bundles: [TaskBundle]) -> [TaskBundle] {
        var seen = Set<UUID>()
        return bundles.filter { seen.insert($0.id).inserted }
    }
}
#endif
