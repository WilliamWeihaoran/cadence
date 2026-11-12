import SwiftData

nonisolated enum CadenceSchema {
    /// The authoritative model list, as types rather than as a built `Schema`.
    ///
    /// [[T-15751]] needs the types themselves: `NSManagedObjectModel.makeManagedObjectModel(for:)`
    /// takes `[any PersistentModel.Type]`, and a `Schema`'s entities cannot be turned back into
    /// one. Hoisted rather than copied, so `CadenceCloudKitSchemaInitializer` publishes exactly
    /// the types this app opens its store with.
    nonisolated static let models: [any PersistentModel.Type] = [
        Context.self,
        Area.self,
        Project.self,
        Pursuit.self,
        Tag.self,
        AppTask.self,
        TaskBundle.self,
        FocusSessionLog.self,
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
        SidebarLayoutPreference.self,
        LookPreference.self,
        NoteTemplatePreference.self,
    ]

    nonisolated static let schema = Schema(models)
}
