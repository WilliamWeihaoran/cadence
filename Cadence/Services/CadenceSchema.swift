import SwiftData

enum CadenceSchema {
    static let schema = Schema([
        Context.self,
        Area.self,
        Project.self,
        Tag.self,
        AppTask.self,
        Subtask.self,
        DailyNote.self,
        WeeklyNote.self,
        PermNote.self,
        Document.self,
        Note.self,
        SavedLink.self,
        EventNote.self,
        MarkdownImageAsset.self,
        Goal.self,
        GoalListLink.self,
        Habit.self,
        HabitCompletion.self,
    ])
}
