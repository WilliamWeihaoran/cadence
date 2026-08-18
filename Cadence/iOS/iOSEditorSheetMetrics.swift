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
/// A fifth surface, `iOSTrackingEditorShell`, hosts no well but is the same kind of sheet, and had
/// its own copies of the gutter ramp, the two-column cap and the gap between groups. It reads them
/// from here now. "Editor sheet" is the unit these figures belong to, not "sheet with a markdown
/// well in it".
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
    /// Shared by the task inspector, both calendar sheets and `iOSTrackingEditorShell`, which is why
    /// it is stated once instead of being a `isRegularWidth ? 20 : 18` in each of them.
    static func gutter(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 20 : 18
    }

    /// Inside a sheet's own card, around the whole form. The task inspector said 14 and
    /// `iOSCalendarQuickCreateSheet` said 16 for the same box — one card, at `Theme.radiusPanel`,
    /// holding one form.
    ///
    /// It is `groupSpacing`, deliberately and not by coincidence: both sheets had already set their
    /// card's padding equal to the gap between the groups inside it, independently, so the frame
    /// around the form reads as one more gap of the same size rather than as a second margin.
    static var cardPadding: CGFloat { groupSpacing }

    // MARK: - The gap between two groups of fields

    /// Between the top-level groups of an editor form — the inspector's identity/schedule/subtasks
    /// stack, the two calendar sheets' cards, and the tracking editors' sections, in one column or
    /// two.
    ///
    /// **16.** Three of the five surfaces already said 16 and two said 14, but the count is not the
    /// argument — the argument is that the two families this splits along do not line up with it.
    /// `iOSCalendarQuickCreateSheet` is the inspector's structural twin (ruled sections inside one
    /// sheet card, six groups apiece) and it says 16; `iOSCalendarEventEditSheet` and
    /// `iOSTrackingEditorShell` are the other shape (free-standing `.card` sections on `Theme.bg`)
    /// and they also say 16. Whichever way the surfaces are grouped, 14 is the odd one out.
    ///
    /// The density theory does not survive being checked, either. The inspector is not denser than
    /// the sheets that say 16 — it draws six groups and quick-create draws six — and the number it
    /// sets is not the gap the eye sees: `iOSEditorSection(style: .ruled)` adds 12pt of its own
    /// above every group's hairline, so the inspector's visible gap was 26 against quick-create's
    /// 28. Two points on a 26-point gap is drift, not a decision.
    ///
    /// The two families still land on different gaps after this — 28 between ruled groups, 16
    /// between cards — because the rule needs air around it and a card edge does not. That
    /// difference belongs to `iOSEditorSection`, which is the thing that knows which style it is.
    /// The sheet's job is only to say how far apart two groups are, and there is one answer to that.
    static let groupSpacing: CGFloat = 16

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
    /// All four surfaces drew this box themselves and drifted in every respect. Three of them
    /// differed over the border — a `.stroke` at 0.68 alpha against a `.strokeBorder` at full, and
    /// `.stroke` centres the line on the clip path, so half of it was being clipped away: the two
    /// calendar sheets' wells had a border both thinner *and* fainter than the template editor's,
    /// for no reason either of them recorded.
    ///
    /// The task inspector's was a fourth spelling with a defect of its own:
    /// `.cadenceCard(background: Theme.surfaceElevated.opacity(0.35), cornerRadius:
    /// Theme.radiusCard, shadowRadius: 10, shadowY: 4)`. That box had **no border at all** — it was
    /// meant to be told apart by its fill — and the fill never rendered, because
    /// `iOSMarkdownEditingSurface` paints an opaque `Theme.surface` of its own and `cadenceCard`
    /// puts its background *behind* that. So the one thing distinguishing the well from the sheet
    /// around it was a drop shadow, at a radius (18) no other well used, and a wash that had been
    /// carefully chosen and was never once drawn.
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
