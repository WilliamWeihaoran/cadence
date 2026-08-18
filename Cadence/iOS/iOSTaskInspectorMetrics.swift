import SwiftUI

/// Every measurement the iOS task inspector draws itself with, and the one that legitimately
/// varies with the host's width.
///
/// The inspector is a **sheet**, which makes it the clearest case in the app of something whose
/// width is its own: its content column is capped at `contentMaxWidth` at every width, and the card
/// inside that column is the same card on both devices. It carried six `horizontalSizeClass`
/// branches anyway — 24pt vs 21pt of title, a 26pt vs 24pt completion circle, the indent under the
/// title restating the circle's size a third time, a 5pt vs 3pt nudge on the circle, and a 360 vs
/// 340 notes well — so the same task, opened from the same row, introduced itself at two volumes
/// depending on which device you were holding. None of those five was chosen; each was a number
/// written twice.
///
/// What survives is the sheet **gutter**: the margin between the card and the edge of the host,
/// which is a fact about the host and not about the card.
///
/// The gutter, the card padding, the gap between groups, the title size and line limit, and the
/// notes well now come from `iOSEditorSheetMetrics`, because none of them was ever the *inspector's*
/// decision — they are what an editor sheet in this app is, and the calendar sheets had written each
/// of them down again. What is left here is what only this sheet has: the width its form stops
/// growing at, a completion circle at the head of its title, and the figures derived from it.
///
/// Deliberately **outside** `#if os(iOS)`, like `iOSPageHeaderMetrics` and for the same reason: a
/// type ramp is a decision, and the macOS-built test target has to be able to read it. Nothing here
/// draws.
///
/// It is an enum of constants rather than a `metrics(isRegularWidth:)` factory because only one
/// figure takes a width. A factory would hand every call site a value that *looks* width-dependent,
/// which is how the branches got there in the first place.
nonisolated enum iOSTaskInspectorMetrics {

    // MARK: - The card

    /// Inside the card, around the whole form — one figure for every editor sheet's card, so see
    /// `iOSEditorSheetMetrics.cardPadding`. It was 14 here against quick-create's 16.
    static var cardPadding: CGFloat { iOSEditorSheetMetrics.cardPadding }

    /// The widest the form is ever drawn, at any width. This cap is why nothing below it needs to
    /// consult the screen: past ~640pt the sheet stops growing and the layout is identical.
    static let contentMaxWidth: CGFloat = 640

    /// Between the identity block, the wells, and the action row. The same gap every other editor
    /// sheet leaves between two groups; `iOSEditorSheetMetrics.groupSpacing` argues the 16, and why
    /// the 14 that used to be here was not the density decision it looked like.
    static var sectionSpacing: CGFloat { iOSEditorSheetMetrics.groupSpacing }

    /// The margin between the card and the edge of the sheet — **the one figure that varies**, and
    /// the only one that is about the host rather than about the inspector. One gutter for every
    /// sheet in the app, which is why it now lives in `iOSEditorSheetMetrics`.
    static func sheetGutter(isRegularWidth: Bool) -> CGFloat {
        iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth)
    }

    // MARK: - The title row

    /// The task's own name, in the sheet that edits it — the same size as the event title in
    /// `iOSCalendarEventEditSheet` and the draft title in `iOSCalendarQuickCreateSheet`, because it
    /// is the same thing: the one field the sheet exists to fill in. That agreement used to be three
    /// literals that happened to match; it is now one value the three of them read.
    static var titleSize: CGFloat { iOSEditorSheetMetrics.titleSize }

    /// A title wraps to three lines before it truncates. Not a width ramp: a task with a long name
    /// has a long name on both devices, and the card is the same width on both past `sheetGutter`.
    static var titleLineLimit: Int { iOSEditorSheetMetrics.titleLineLimit }

    /// The completion circle at the head of the title row — drawn at this size, not merely framed
    /// at it, because in the sheet the circle *is* the control rather than a glyph inside a target.
    ///
    /// 24 is `CadenceTaskRowMetrics.regularWidth.completionGlyphSize`, the largest completion glyph
    /// the app already draws, so the inspector's sits at the top of the existing scale instead of
    /// inventing a step above it. The 26 it used on iPad was that invented step.
    static let completionGlyphSize: CGFloat = 24

    /// Between the completion circle, the title column, and the estimate chip.
    static let titleRowSpacing: CGFloat = 12

    /// How far the tags and the placement breadcrumb are indented so they line up with the title
    /// text rather than with the circle beside it.
    ///
    /// Derived, not stated: the indent *is* the circle plus the gap, and writing it out again is
    /// how `(isRegularWidth ? 26 : 24) + 12` came to restate a ramp that lived in another file.
    /// Same lesson as `iOSPageHeaderMetrics.iconSize` — a tile can never be resized without its
    /// glyph following.
    static var titleColumnInset: CGFloat {
        completionGlyphSize + titleRowSpacing
    }

    /// The first line of a title, as SwiftUI lays it out. Used only to place the circle against it.
    static var titleLineHeight: CGFloat {
        titleSize * 1.2
    }

    /// The nudge that centres the completion circle on the **first** line of a title that may wrap
    /// to three, since the row is `.top`-aligned.
    ///
    /// Derived from the two sizes it sits between, so neither can be changed without it following.
    /// It was a hand-set 5 on one device and 3 on the other, against title sizes that differed by
    /// 3pt and a circle that differed by 2 — three independent numbers describing one alignment.
    static var completionTopPadding: CGFloat {
        max(0, (titleLineHeight - completionGlyphSize) / 2)
    }

    // MARK: - Notes

    /// The resting height of the notes well before there is anything in it — one number, and now
    /// the *same* number as every other markdown well on a sheet. See
    /// `iOSEditorSheetMetrics.notesMinHeight`.
    static var notesMinHeight: CGFloat { iOSEditorSheetMetrics.notesMinHeight }
}
