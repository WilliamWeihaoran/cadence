import SwiftData

enum CadenceSchema {
    static let schema = Schema([
        Context.self,
        Area.self,
        Project.self,
        Pursuit.self,
        Tag.self,
        AppTask.self,
        TaskBundle.self,
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
