import Foundation

/// The two "which occurrences does this apply to?" dialogs, worded once.
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
