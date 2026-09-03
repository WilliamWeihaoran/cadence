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
/// user is about to press again is chrome that says nothing. The exception is a notice in a
/// **markdown editing surface**, where the failing act (paste an image, tick an embedded task) is
/// not what the user does next — they go back to typing, and nothing they type touches the door
/// that set the notice. Those notices had no way to go away at all and sat under the toolbar for
/// the rest of the session. They pass `onDismiss`; nobody else should.
struct CadenceInlineFailureNotice: View {
    let text: String

    /// Supplied only by a caller whose notice has no next attempt to clear it. `nil` draws the
    /// bare sentence, which is what the other 43 of 49 call sites want.
    var onDismiss: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let onDismiss {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sentence
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.red)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .accessibilityLabel("Dismiss")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            sentence
        }
    }

    private var sentence: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
