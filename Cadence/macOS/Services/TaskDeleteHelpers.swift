#if os(macOS)
import SwiftData

extension ModelContext {
    func deleteTask(_ task: AppTask) {
        TaskCompletionAnimationManager.shared.cancelPending(for: task.id)
        TaskCompletionAnimationManager.shared.cancelCancelPending(for: task.id)

        if !task.calendarEventID.isEmpty {
            SchedulingActions.removeFromCalendar(task)
        }

        let subtasks = Array(task.subtasks ?? [])
        for subtask in subtasks {
            delete(subtask)
        }

        delete(task)
    }
}
#endif
