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
struct CadenceInlineFailureNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
