import SwiftUI

/// The measurements that belong to **an editor sheet in this app**, rather than to any one of them.
///
/// Four surfaces host `iOSMarkdownEditingSurface` as a *well* — a box with a resting height that
/// then grows with its content — and they gave it four heights: the task inspector 340, the
/// Settings template editor 340, `iOSCalendarEventEditSheet` 300/240 and
/// `iOSCalendarQuickCreateSheet` 280/230. Two of the four also ramped that height by the width of
/// the screen behind the sheet. `notesMinHeight` is the one answer; see its comment for why 340.
///
/// The same sheets had independently written down the size of the title they edit, the margin
/// between their card and the host, and — in the two calendar sheets, byte for byte — the widths of
/// the two columns they split into at regular width. Each of those is one decision spelled two or
/// three times, which is how `titleSize` came to be 22 in two files and a `24 : 21` ramp in a third.
///
/// Deliberately **outside** `#if os(iOS)`, like `iOSTaskInspectorMetrics` and `iOSPageHeaderMetrics`
/// and for the same reason: these are decisions, and the macOS-built test target has to be able to
/// read them. Nothing in the enum draws.
///
/// An enum of constants rather than a `metrics(isRegularWidth:)` factory, for the reason
/// `iOSTaskInspectorMetrics` gives: exactly one figure here takes a width, and a factory would hand
/// every call site a value that *looks* width-dependent — which is how the ramps got there.
nonisolated enum iOSEditorSheetMetrics {

    // MARK: - The markdown well

    /// The resting height of a markdown well on an editor sheet, at every width and on every sheet.
    ///
    /// **340**, which is the height the two surfaces that never ramped — the task inspector and the
    /// Settings template editor — already agreed on, and the tallest of the four. The well is inside
    /// a scroll view and grows with its content, so the minimum's only job is to be a canvas worth
    /// tapping into; nothing is clipped by choosing the largest, and the smallest is the only choice
    /// that can make a well feel like a one-line field.
    ///
    /// It is not a split of 340/300/280/240. Averaging four numbers nobody chose produces a fifth
    /// number nobody chose. The two flat values were the ones written deliberately; the two ramps
    /// were the drift.
    ///
    /// The two calendar sheets do **not** have less room for it than the inspector does. All four
    /// surfaces scroll, so height is never a fit question, only a "how far down is what's under it"
    /// question — and what is under the well is: the inspector's status-action row, the event
    /// sheet's Delete button, nothing at all on quick-create (its Create button is in the sheet's
    /// own header), and nothing at all in the template editor. The event sheet's field stack above
    /// the well is also *shorter* than the inspector's, which carries a properties group, a schedule
    /// group and subtasks before it gets there. Both sheets keep their primary action — Save in the
    /// toolbar, Create in the header — pinned above the well regardless.
    static let notesMinHeight: CGFloat = 340

    // MARK: - The host

    /// The margin between the sheet's content and the edge of the host — **the one figure here that
    /// varies**, and the only one that is about the device rather than about the sheet. It is what
    /// is left over once a content column has stopped growing, so it is a real host fact.
    ///
    /// Shared by the task inspector and both calendar sheets, which is why it is stated once
    /// instead of being a `isRegularWidth ? 20 : 18` in each of them.
    static func gutter(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 20 : 18
    }

    // MARK: - The name of the thing being edited

    /// The task title, the event title, the quick-create title: the one field a sheet exists to fill
    /// in. All three sheets already draw it at 22pt bold — `iOSTaskInspectorMetrics.titleSize` was
    /// resolved to 22 *from* the two calendar sheets — but they drew it from three separate literals,
    /// so the agreement was a coincidence that any one of them could have ended.
    static let titleSize: CGFloat = 22

    /// A title wraps to three lines before it truncates. Not a width ramp: a long name is long on
    /// both devices, and past `gutter` the sheet's column is the same column.
    static let titleLineLimit = 3

    // MARK: - Splitting into two columns

    /// Both calendar sheets lay their groups out in two columns at regular width, and both had
    /// written the same five widths down. Naming them here is not a new layout — it is the same
    /// layout stated once, so the next sheet that splits copies a decision rather than a literal.
    ///
    /// The columns are deliberately uneven: the trailing one carries the markdown well, which wants
    /// the extra width more than a column of field rows does.
    static let primaryColumnMinWidth: CGFloat = 340
    static let primaryColumnMaxWidth: CGFloat = 440
    static let secondaryColumnMinWidth: CGFloat = 360
    static let secondaryColumnMaxWidth: CGFloat = 520

    /// The widest a two-column editor sheet is ever drawn. Past this it stops growing and centres,
    /// so a line of text never spans a full iPad.
    static let twoColumnMaxWidth: CGFloat = 980
}

#if os(iOS)

extension View {
    /// The resting shape of a markdown well on an editor sheet: one height, one radius, one border.
    ///
    /// Three surfaces drew this box themselves and drifted in all three respects — two heights, and
    /// a `.stroke` at 0.68 alpha against a `.strokeBorder` at full. `.stroke` centres the line on the
    /// clip path, so half of it was being clipped away: the two calendar sheets' wells had a border
    /// both thinner *and* fainter than the template editor's, for no reason either of them recorded.
    ///
    /// One layer at one radius, per the standing rule — the border is the only thing drawn over the
    /// surface, and it shares the radius the surface is clipped to.
    func iOSMarkdownWell() -> some View {
        frame(minHeight: iOSEditorSheetMetrics.notesMinHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            }
    }
}

#endif
