#if os(macOS)
import SwiftUI

enum KanbanCardComputedSupport {
    static func isOverdue(task: AppTask) -> Bool {
        guard !task.dueDate.isEmpty, !task.isDone else { return false }
        return task.dueDate < DateFormatters.todayKey()
    }

    static func isOverdo(task: AppTask) -> Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
    }

    static func isDoToday(task: AppTask) -> Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return task.scheduledDate == DateFormatters.todayKey()
    }

    static func completionButtonIcon(
        task: AppTask,
        isPendingCompletion: Bool,
        isPendingCancel: Bool
    ) -> String {
        if task.isCancelled { return "xmark.circle.fill" }
        if task.isDone { return "checkmark.circle.fill" }
        if isPendingCancel { return "xmark.circle" }
        if isPendingCompletion { return "circle.inset.filled" }
        return "circle"
    }

    static func completionButtonColor(
        task: AppTask,
        isPendingCompletion: Bool,
        isPendingCancel: Bool
    ) -> Color {
        if task.isCancelled || isPendingCancel { return Theme.dim }
        if task.isDone || isPendingCompletion { return Theme.green }
        return Theme.priorityColor(task.priority)
    }

    static func handleCompletionTap(
        task: AppTask,
        isPendingCompletion: Bool,
        isPendingCancel: Bool,
        manager: TaskCompletionAnimationManager
    ) {
        if isPendingCompletion {
            manager.cancelPending(for: task.id)
            manager.toggleCancellation(for: task)
        } else if isPendingCancel {
            manager.cancelCancelPending(for: task.id)
        } else {
            manager.toggleCompletion(for: task)
        }
    }

}
#endif
