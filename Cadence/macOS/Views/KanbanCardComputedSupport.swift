#if os(macOS)
import SwiftUI

enum KanbanCardComputedSupport {
    static func isOverdue(task: AppTask) -> Bool {
        task.isOverdue(todayKey: DateFormatters.todayKey())
    }

    static func isOverdo(task: AppTask) -> Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
    }

    static func isDoToday(task: AppTask) -> Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return task.scheduledDate == DateFormatters.todayKey()
    }

    /// Both of these were a second, byte-identical copy of `TaskCompletionButton`'s ordered `if`
    /// chain. They now read the one shared decision, `CadenceTaskCompletionGlyph`.
    static func completionGlyph(
        task: AppTask,
        isPendingCompletion: Bool,
        isPendingCancel: Bool
    ) -> CadenceTaskCompletionGlyph {
        .resolve(
            task: task,
            isPendingCompletion: isPendingCompletion,
            isPendingCancellation: isPendingCancel
        )
    }

    static func completionButtonIcon(
        task: AppTask,
        isPendingCompletion: Bool,
        isPendingCancel: Bool
    ) -> String {
        completionGlyph(
            task: task,
            isPendingCompletion: isPendingCompletion,
            isPendingCancel: isPendingCancel
        ).symbolName
    }

    static func completionButtonColor(
        task: AppTask,
        isPendingCompletion: Bool,
        isPendingCancel: Bool
    ) -> Color {
        completionGlyph(
            task: task,
            isPendingCompletion: isPendingCompletion,
            isPendingCancel: isPendingCancel
        ).tint
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
