import SwiftUI

/// The chrome shared by a family of free-text search rows in the app: an 11pt `magnifyingglass`
/// in `Theme.dim`, laid out in an `HStack(spacing: 6)` with `.padding(.horizontal, 12)` /
/// `.padding(.vertical, 8)`, and the shared clear button (T-672) at the trailing edge.
///
/// **T-790.** `ContainerPickerSupportViews`, `TasksPanelSupportViews`, `TaskTitleInlineTagPicker`,
/// and `TildeContainerPicker` each hand-spelled this row, and outside the `TextField` itself the
/// four copies were byte-for-byte identical — same glyph, same size, same tint, same spacing, same
/// padding. u1 (2026-09-04) had already read every `magnifyingglass` search row in the app,
/// including these four, and judged the differences between them real: two distinct interaction
/// families, different result types, different escape hatches. That judgement stands — this does
/// not touch the `TextField`. Its placeholder, its `onSubmit`, and the `onKeyPress` family beside
/// it (two handlers at some call sites, five at others) stay exactly where they were, supplied by
/// the caller as `field`. Only the part that was genuinely one thing across all four — the icon
/// and the row's own layout — moved here. A row that also tried to own the field, parameterising
/// its placeholder and every `onKeyPress` case, would have been the eight-parameter row that is
/// worse than four honest copies (T-935); this shares nothing beyond what actually matched.
///
/// Other `magnifyingglass` rows in the app (the calendar picker, the goal/commitment pickers, the
/// focus picker, the tag popover, the bundle picker) were read and left alone: their spacing runs
/// 7–10 rather than 6, their glyph sizes run 10–18 with weights this family does not use, and the
/// bundle picker swaps the glyph for a back chevron. Those differences are real too, so this type
/// is scoped to the four call sites that actually matched, not generalised past them.
struct CadenceSearchFieldRow<Field: View>: View {
    /// The query the trailing clear button empties. `field` is expected to bind to the same value.
    @Binding var query: String

    /// The field's focus, restored by the clear button after it empties `query`.
    var focus: FocusState<Bool>.Binding

    /// The search `TextField`, fully configured by the caller: placeholder, styling, `onSubmit`,
    /// and whichever `onKeyPress` handlers that call site's interaction model needs.
    let field: Field

    init(query: Binding<String>, focus: FocusState<Bool>.Binding, @ViewBuilder field: () -> Field) {
        self._query = query
        self.focus = focus
        self.field = field()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
            field
            CadenceSearchFieldClearButton(text: $query, glyphSize: 11, focus: focus)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
