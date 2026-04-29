import SwiftData

enum CadenceSchema {
    static let schema = Schema([
        Context.self,
        Area.self,
        Project.self,
        AppTask.self,
        Subtask.self,
        DailyNote.self,
        WeeklyNote.self,
        PermNote.self,
        Document.self,
        SavedLink.self,
        EventNote.self,
        MarkdownImageAsset.self,
        Goal.self,
        Habit.self,
        HabitCompletion.self,
    ])
}
