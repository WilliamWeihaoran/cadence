#if os(macOS)
import SwiftData
import Foundation

extension ModelContext {
    func deleteTask(_ task: AppTask) {
        let taskID = task.id
        TaskCompletionAnimationManager.shared.cancelPending(for: taskID)
        TaskCompletionAnimationManager.shared.cancelCancelPending(for: taskID)

        guard let taskToDelete = currentTask(withID: taskID) else { return }

        if !taskToDelete.calendarEventID.isEmpty {
            SchedulingActions.removeFromCalendar(taskToDelete)
        }

        deleteTasks(withIDs: [taskID])
    }

    private func currentTask(withID taskID: UUID) -> AppTask? {
        let descriptor = FetchDescriptor<AppTask>()
        return (try? fetch(descriptor))?.first { $0.id == taskID }
    }

    func deleteTasks(withIDs taskIDs: Set<UUID>) {
        guard !taskIDs.isEmpty else { return }

        try? delete(model: Subtask.self, where: #Predicate<Subtask> { subtask in
            if let parentTask = subtask.parentTask {
                taskIDs.contains(parentTask.id)
            } else {
                false
            }
        })

        try? delete(model: AppTask.self, where: #Predicate<AppTask> { task in
            taskIDs.contains(task.id)
        })
    }
}
#endif
