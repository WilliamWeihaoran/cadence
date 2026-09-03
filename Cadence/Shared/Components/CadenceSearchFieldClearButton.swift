import SwiftUI

/// The clear button at the trailing edge of a search field — **one copy, for every search field in
/// the app**.
///
/// **T-672.** Eleven pickers spelled this control by hand, and the ten that
/// `knownUnnamedIconButtonSites` listed stated no accessible name at all, so eleven search fields
/// carried a glyph VoiceOver reads as nothing. That was the finding an accessibility sweep
/// surfaced; the defect underneath it is that eleven near-copies of one control drifted apart in
/// three ways nobody chose, and this type is the fix for both halves.
///
/// What the copies disagreed about, and what this decides:
///
/// - **Focus.** Four of the eleven set the field focused again after clearing and seven did not.
///   That is not a design difference: clicking a SwiftUI `Button` takes key focus off the
///   `TextField` beside it, so at the seven the user cleared the query and then had to click back
///   into the field before typing. AppKit's own `NSSearchField` clear button keeps the field
///   focused; the four were fixing the bug and the seven had not noticed it. So the button always
///   restores focus, which is why `focus` is a required parameter rather than an option — a call
///   site cannot opt out of it, and two fields (the goal-timeline milestone filter and the bundle
///   picker) grew the `@FocusState` they were missing in the same change.
/// - **Tint.** Five drew `Theme.dim`, five `Theme.dim.opacity(0.5)`, one `0.55`. `Theme.dim` wins:
///   it is the plurality, it is what the `magnifyingglass` on the *other* end of every one of
///   those rows is already drawn in, and `Cadence/Shared/AGENTS.md` asks for a named ramp rather
///   than a one-off opacity.
/// - **Weight.** Ten drew the glyph at the default weight and one at `.semibold`. Default wins,
///   for the same reason: it is what the leading glyph in that row uses.
///
/// `glyphSize` is the one difference that was chosen and is kept. In nine of the eleven rows this
/// glyph is drawn at exactly the size of that row's own leading `magnifyingglass` — 11 in the
/// compact pickers, 12 in the popovers — so the size is the field's scale and not decoration. The
/// two that differ are the two whose leading glyph is *emphasised* rather than matched: Cmd+K
/// draws an 18pt `command` over a 22pt field and clears at 16, and the focus picker draws a 13pt
/// semibold magnifier and clears at 12. So it takes no default, the T-674 shape: the twelfth call
/// site must state the scale it sits in rather than inherit a number that is wrong half the time.
struct CadenceSearchFieldClearButton: View {
    /// The query this empties. The button draws nothing at all while it is empty, so call sites do
    /// not repeat the `if !query.isEmpty` guard that used to wrap every copy.
    @Binding var text: String

    /// The size of the field's own leading `magnifyingglass`. See the type's note.
    let glyphSize: CGFloat

    /// The field's focus, restored after the clear. Required: see the type's note.
    var focus: FocusState<Bool>.Binding

    /// Work beyond emptying `text`. Cmd+K is the only caller that needs it — its query is
    /// debounced, so clearing has to cancel the pending commit and empty the committed query too.
    var onClear: (() -> Void)?

    /// The accessible name, stated once for every search field rather than at eleven call sites
    /// that could each forget it. It names what activating the control does, not the glyph.
    static let accessibleName = "Clear search"

    var body: some View {
        if !text.isEmpty {
            Button {
                text = ""
                onClear?()
                focus.wrappedValue = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: glyphSize))
                    .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.cadencePlain)
            .accessibilityLabel(Self.accessibleName)
            .help(Self.accessibleName)
        }
    }
}
