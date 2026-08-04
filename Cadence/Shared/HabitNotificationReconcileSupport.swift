import Foundation
import SwiftData

/// Shared fast-path notification reconcile trigger for task/habit create, edit, and delete call
/// sites across macOS and iOS. Kept tiny and side-effect-only so each call site stays a one-liner.
enum HabitNotificationReconcileSupport {
    static func scheduleReconcile(in context: ModelContext) {
        Task {
            let tasks = (try? context.fetch(FetchDescriptor<AppTask>())) ?? []
            let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            await NotificationManager.shared.reconcile(tasks: tasks, habits: habits)
        }
    }
}
