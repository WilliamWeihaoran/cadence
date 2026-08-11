#if os(macOS)
import Foundation
import SwiftData

enum PrivacyDataResetService {
    static func deleteCadenceData(in modelContext: ModelContext) throws {
        try deleteAll(HabitCompletion.self, in: modelContext)
        try deleteAll(GoalListLink.self, in: modelContext)
        try deleteAll(Subtask.self, in: modelContext)
        try deleteAll(TaskBundle.self, in: modelContext)
        try deleteAll(AppTask.self, in: modelContext)
        try deleteAll(EventNote.self, in: modelContext)
        try deleteAll(DailyNote.self, in: modelContext)
        try deleteAll(WeeklyNote.self, in: modelContext)
        try deleteAll(PermNote.self, in: modelContext)
        try deleteAll(Note.self, in: modelContext)
        try deleteAll(Document.self, in: modelContext)
        try deleteAll(MarkdownImageAsset.self, in: modelContext)
        try deleteAll(SavedLink.self, in: modelContext)
        try deleteAll(Habit.self, in: modelContext)
        try deleteAll(Goal.self, in: modelContext)
        try deleteAll(Pursuit.self, in: modelContext)
        try deleteAll(Project.self, in: modelContext)
        try deleteAll(Area.self, in: modelContext)
        try deleteAll(Context.self, in: modelContext)
        try deleteAll(Tag.self, in: modelContext)
        try modelContext.save()

        // Pending OS notifications are not in the store, so wiping the store does not touch them.
        // That was nearly harmless while every reminder was a one-shot that fired once and
        // expired; now that habit reminders repeat on time-of-day, a reset would leave a banner
        // carrying a deleted habit's **title** firing every day until the next reconcile — and
        // reconcile only runs when the scene leaves `.active`. "Delete my data" has to mean the
        // notifications too.
        Task { await NotificationManager.shared.cancelAll() }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) throws {
        let models = try modelContext.fetch(FetchDescriptor<T>())
        for model in models {
            modelContext.delete(model)
        }
    }
}
#endif
