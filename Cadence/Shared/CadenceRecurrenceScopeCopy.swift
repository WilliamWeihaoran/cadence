import Foundation

/// The "which occurrences does this apply to?" dialogs, worded once.
///
/// Both are asked from three places each, and every one of the six spelled its own copy:
///
/// - the calendar one from `TimelineEventBlock`, `TimelineEventBlockSupportViews` (the Mac's
///   inline block and its editor popover) and `iOSCalendarEventEditSheet`;
/// - the task one from `TaskEmbedFieldEditorPopover`, `iOSTaskDetailSheet` and
///   `iOSTaskRowActionViews`.
///
/// Six copies of four sentences is `CadenceEmptyStateCopy`'s problem one surface over, and the
/// same fix: the dialog a reader sees does not depend on which control opened it, so the words
/// should not either. Measured at HEAD the six agreed exactly — this converges them *before* the
/// drift rather than after it, which is the only difference from the empty-state pairs that were
/// found already broken.
///
/// **The buttons are deliberately not here.** They are `CalendarRecurrenceEditScope.label` and
/// `CadenceTaskRecurrenceEditScope.label`, which belong with the enum that also decides the
/// `EKSpan`/series semantics — a button whose words and whose effect come from one value cannot
/// name the wrong scope. `TaskInspectorWorkflowSupportViews.scopeOptions` uses a shorter inline
/// wording for the same two cases on purpose; its own comment records why.
///
/// **A third dialog joined them for the delete ([[T-6115]])**, which is the same question asked of
/// a repeating task at the one other point a live occurrence can leave its series. Its buttons are
/// likewise not here: they are `CadenceTaskRecurrenceDeleteScope.label`, beside the enum the delete
/// core switches on.
///
/// `nonisolated` for the reason `CadenceEmptyStateCopy` gives: the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and constants have no state to protect.
nonisolated enum CadenceRecurrenceScopeCopy {

    /// Title of the confirmation dialog raised when an edit lands on a repeating **calendar
    /// event**.
    static let eventScopeTitle = "Change recurring event?"

    /// Names the two spans in the reader's words rather than EventKit's: "this occurrence" and
    /// "this and future events" are what `CalendarRecurrenceEditScope`'s two buttons do.
    static let eventScopeMessage =
        "Choose whether this calendar change applies only to this occurrence or to this and future events."

    /// Title of the confirmation dialog raised when a repeat rule changes on a repeating **task**.
    static let taskScopeTitle = "Change repeating task?"

    /// Says "instances" rather than "events", because a repeating task is spawned forward one
    /// occurrence at a time by `CadenceTaskRecurrenceWorkflowSupport` and is not an EventKit
    /// series.
    static let taskScopeMessage =
        "Choose whether this repeat change applies only here or to this task and future instances."

    /// Title of the confirmation raised when a **delete** lands on a repeating task ([[T-6115]]).
    ///
    /// The third dialog in this file, and the first that is not an *edit*. Title Case rather than
    /// the sentence case of the two above, because it replaces a delete confirmation's title and
    /// the delete family is title-cased on both platforms — "Delete Task?" on the Mac overlay and
    /// in both iOS alerts, "Couldn't Delete Task" on the failure alert.
    static let deleteScopeTitle = "Delete Repeating Task?"

    /// What the two delete buttons mean, in one sentence, shared by three surfaces.
    ///
    /// Here for the reason `taskScopeFailureTitle` is here: the Mac overlay and the two iOS alerts
    /// all raise this question, and the one thing a reader must not find worded differently is the
    /// promise that the repeat survives. The Mac prefixes the task's name to it, which is that
    /// overlay's existing habit for every other delete; the part that would drift is this.
    ///
    /// It says "the next one will still appear" rather than "the series continues" because that is
    /// the observable claim `CadenceTaskRecurrenceWorkflowSupport.spawnSuccessorBeforeDeletingOccurrence`
    /// actually makes — one occurrence is minted per settle, and this is a settle in all but name.
    static let deleteScopeMessage =
        "Deleting this occurrence keeps the repeat going, so the next one will still appear. "
        + "Deleting the series ends the repeat."

    /// Title of the alert raised when a repeat change on a repeating **task** did not land.
    ///
    /// Here rather than in the two files that show it, for the reason the dialog's own prose is
    /// here: the phone raises this scope question from a row chip and from the task sheet, and a
    /// sentence spelled twice is a sentence that drifts (T-633).
    static let taskScopeFailureTitle = "Couldn't Update the Series"

    /// Shown when the rest of the series could not be read at all, so the scope the user chose
    /// could not even be resolved to a list of tasks.
    ///
    /// Distinct from `CadencePendingChangePersistence.editFailureNotice`, which is what a refused
    /// *commit* says: this one is about the read that comes first, and "Try again" is honest for it
    /// in a way it would not be for a store that refused the write.
    static let taskScopeLookupFailureNotice =
        "Cadence couldn't load the rest of this repeating task, so nothing was changed. Try again."
}
