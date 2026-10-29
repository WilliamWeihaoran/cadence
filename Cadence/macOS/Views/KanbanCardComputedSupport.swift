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

    /// This was a second, byte-identical copy of `TaskCompletionButton`'s ordered `if` chain (with
    /// an icon and a colour helper beside it, gone since [[T-8411]] handed the card's circle the
    /// glyph itself). It now reads the one shared decision, `CadenceTaskCompletionGlyph`.
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

    static func handleCompletionTap(
        task: AppTask,
        isPendingCompletion: Bool,
        isPendingCancel: Bool,
        manager: TaskCompletionAnimationManager
    ) {
        // The three-tap walk is the manager's one decision now ([[T-8203]]), shared with the task
        // row and every iOS circle; the pending flags this takes are the manager's own answers.
        manager.advanceCompletionControl(for: task)
    }

}
#endif
