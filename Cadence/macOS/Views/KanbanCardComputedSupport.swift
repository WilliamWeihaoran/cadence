#if os(macOS)
import SwiftUI

enum KanbanCardComputedSupport {
    // **The day is the caller's, not the clock's ([[T-5012]]).** These read
    // `DateFormatters.todayKey()` themselves, from inside the body of a row whose inputs are the
    // same on both sides of midnight — so a list page left open overnight kept yesterday's red and
    // amber until something else redrew it. The page host observes the day once and hands its key
    // down; asking for it here is what makes forgetting it a compile error.
    static func isOverdue(task: AppTask, todayKey: String) -> Bool {
        task.isOverdue(todayKey: todayKey)
    }

    static func isOverdo(task: AppTask, todayKey: String) -> Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        // Still `dayOffset`, not a string compare, so iOS's twin answers alike — measured from
        // the handed day rather than from `Date()`.
        guard let today = DateFormatters.date(from: todayKey) else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate, relativeTo: today) ?? 0) < 0
    }

    static func isDoToday(task: AppTask, todayKey: String) -> Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return task.scheduledDate == todayKey
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
