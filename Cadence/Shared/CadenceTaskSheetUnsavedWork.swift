import Foundation

/// What the iOS task sheet would lose if it closed now: the one answer its swipe guard, its
/// Focus handoff and its Save read, so the three cannot disagree about what "unsaved" means.
///
/// **[[T-5359]] — completion is not an unsaved edit.** `CadenceScheduleDraft.isDone` is a mirror
/// of the task, never a field the panel lets anyone change: it only stops a past date being
/// painted as wrong on a finished task, and `CadenceTaskEditDraftCommit` never writes it. The sheet
/// copies the live status into it when Complete lands, so comparing it made a task completed from
/// the sheet look like a pending edit and the sheet refused its swipe-down until Reopen. It is
/// compared at the opened value, and every field a user can actually change still counts.
///
/// **[[T-5175]] — text typed into "Add subtask" and not yet sent is the user's work too.** It lives
/// in sheet state outside the draft, so a draft comparison alone let a swipe drop it. Whitespace is
/// nothing to lose, by the same normalisation the composer's own Add uses.
///
/// **[[T-5173]] — Focus This Task closes the sheet**, so it is offered only when closing would lose
/// nothing; otherwise the button is disabled and says why.
@MainActor
enum CadenceTaskSheetUnsavedWork {

    /// The caption the disabled Focus button carries while the sheet holds unsaved work.
    static let focusBlockedCaption = "Save or cancel your changes to focus on this task."

    /// Whether closing the sheet now would discard something the user did.
    static func hasUnsavedWork(
        draft: CadenceScheduleDraft,
        opened: CadenceScheduleDraft,
        notesHavePendingEdit: Bool,
        pendingSubtaskTitle: String
    ) -> Bool {
        draftDiffers(draft, from: opened)
            || notesHavePendingEdit
            || hasPendingComposerEntry(pendingSubtaskTitle)
    }

    /// The draft against the one it opened as, with the completion mirror left out.
    static func draftDiffers(_ draft: CadenceScheduleDraft, from opened: CadenceScheduleDraft) -> Bool {
        var comparable = draft
        comparable.isDone = opened.isDone
        return comparable != opened
    }

    /// Whether a composer field holds something its Add would add — by the normalisation
    /// `CadenceTaskMutationSupport.insertSubtask` itself applies, so Save never waits on an entry
    /// the insert would refuse as empty.
    static func hasPendingComposerEntry(_ text: String) -> Bool {
        !CadenceTitleNormalization.normalized(text).isEmpty
    }
}
