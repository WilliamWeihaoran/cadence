import SwiftUI

/// One line of red text saying why the thing you just asked for did not happen.
///
/// **Why it exists (T-291).** Three macOS delete call sites needed a failure line at once — both
/// halves of `EditListSheet` and Settings → Lists / Contexts — and `LinksView` had already
/// hand-rolled the same `Text` + `Theme.red` + `fixedSize` stack. Three more copies is how a repo
/// ends up with four spellings of the same sentence in four weights.
///
/// It is deliberately not a banner or an alert. A destructive action that failed leaves the screen
/// that asked for it still open and still correct, so the notice belongs *beside* the control that
/// was pressed, not in a modal on top of it — the same choice `iOSListDeleteConfirmationSheet`
/// made. Those iOS sheets keep their own inline `Text` because it sits inside a card with the
/// card's own metrics; this is the plain-surface spelling.
///
/// **Dismissal is a parameter, not a policy (T-708).** Almost every caller sits beside the control
/// that failed — Save, Create, Restore, Delete — and its notice is cleared by the *next press of
/// that control*, which is the only dismissal those surfaces need: an ✕ next to a Save button the
/// user is about to press again is chrome that says nothing. The exception is a notice **no later
/// attempt clears**, and it has to be spelled that way rather than as a place ([[T-642]]).
///
/// T-708 wrote the rule as "a **markdown editing surface**" because all six sites it had were in
/// one: the failing act there (paste an image, tick an embedded task) is not what the user does
/// next — they go back to typing, and nothing they type touches the door that set the notice. Those
/// notices had no way to go away at all and sat under the toolbar for the rest of the session.
///
/// The seventh site, `CadenceTaskSettleFailureNoticeModifier`, is not a text editor and has the
/// property for a sharper reason: a **successful** settle writes nothing to
/// `CadenceTaskSettleFailureCenter` — `CadenceTaskStatusEditing.toggleCompletion` only `record()`s
/// on the failure path — so there is no clearing write to wait for at all, and the next tick landing
/// cleanly would leave the sentence sitting underneath it.
///
/// So: pass `onDismiss` when nothing the user can do next takes the sentence away, and not
/// otherwise. `onlyNoticesNoLaterAttemptClearsOfferToDismissThemselves` names all seven.
struct CadenceInlineFailureNotice: View {
    let text: String

    /// Supplied only by a caller whose notice has no next attempt to clear it. `nil` draws the
    /// bare sentence, which is what the other 54 of 61 call sites want.
    var onDismiss: (() -> Void)?

    /// **The layout moved to `CadenceInlineNotice` (T-1077) and the meaning stayed here.** A second
    /// notice needed the same line in the same place and the opposite colour, and two structs each
    /// spelling `Text` + `font` + `foregroundStyle` + `fixedSize` + the dismissal `HStack` is the
    /// near-copy this component was created to prevent. What this type still owns is the claim that
    /// the sentence is a *failure*, which is what its 61 call sites are asserting by naming it.
    var body: some View {
        CadenceInlineNotice(text: text, tone: .failure, onDismiss: onDismiss)
    }
}
