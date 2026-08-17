import Foundation
import SwiftData

/// Shared fast-path notification reconcile trigger for task/habit create, edit, and delete call
/// sites across macOS and iOS. Kept tiny and side-effect-only so each call site stays a one-liner.
nonisolated enum HabitNotificationReconcileSupport {
    static func scheduleReconcile(in context: ModelContext) {
        Task { @MainActor in
            guard let input = reconcileInput(
                tasks: try? context.fetch(FetchDescriptor<AppTask>()),
                habits: try? context.fetch(FetchDescriptor<Habit>())
            ) else { return }
            await NotificationManager.shared.reconcile(tasks: input.tasks, habits: input.habits)
        }
    }

    /// `nil` when either fetch failed, which callers must treat as "skip this pass".
    ///
    /// Coercing a failed fetch to `[]` is not inert: `reconcile` reads an empty desired set as
    /// "nothing should be pending" and cancels every managed notification the app has scheduled.
    /// A genuinely empty store still returns a (empty, empty) pair — that one really does mean
    /// there is nothing to notify about.
    static func reconcileInput(
        tasks: [AppTask]?,
        habits: [Habit]?
    ) -> (tasks: [AppTask], habits: [Habit])? {
        guard let tasks, let habits else { return nil }
        return (tasks, habits)
    }
}
