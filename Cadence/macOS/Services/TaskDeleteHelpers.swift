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

        let subtasks = currentSubtasks(parentTaskID: taskID)
        for subtask in subtasks {
            subtask.parentTask = nil
            delete(subtask)
        }

        delete(taskToDelete)
    }

    private func currentTask(withID taskID: UUID) -> AppTask? {
        let descriptor = FetchDescriptor<AppTask>()
        return (try? fetch(descriptor))?.first { $0.id == taskID }
    }

    private func currentSubtasks(parentTaskID taskID: UUID) -> [Subtask] {
        let descriptor = FetchDescriptor<Subtask>()
        return ((try? fetch(descriptor)) ?? []).filter { $0.parentTask?.id == taskID }
    }
}
#endif
