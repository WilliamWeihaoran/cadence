import SwiftUI

/// The figures behind the board card's metadata chip, in a value type outside every platform
/// conditional so `CadenceTests` can pin them.
nonisolated struct CadenceBoardMetadataChipMetrics: Sendable {
    /// **10 wins, and iOS had it.** macOS drew the glyph at 9 against an 11pt label. An SF Symbol
    /// set two points under the text it labels stops reading as a label for that text and starts
    /// reading as a smudge before it, which matters here because the glyph — clock / sun / repeat /
    /// checklist — is the only part of the chip you can identify without reading it. One point
    /// under the label is the relationship every other icon-and-label pair in the app draws.
    static let iconSize: CGFloat = 10

    /// The fixed column the glyph sits in, so a `clock` and a `repeat` put their labels on the same
    /// x. One point over `iconSize`, as it was on both platforms before (9/10 and 10/11).
    static let iconColumnWidth: CGFloat = 11

    static let labelSize: CGFloat = 11
    static let spacing: CGFloat = 5
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6

    /// Below this the label shrinks rather than truncating: a time range that reads "9:00 – 9:30 AM"
    /// is worth 2pt of scale and worthless with its end cut off.
    static let minimumScale: CGFloat = 0.78

    /// The 1pt of card left outside the chip's own corner, which is what stops the two arcs from
    /// touching.
    static let cardInset: CGFloat = 1

    /// **A kept difference, expressed as one rule instead of two literals.**
    ///
    /// macOS's chip was 6 and iOS's was `Theme.radiusControl` (10), and that is *not* drift: the
    /// cards differ. A macOS board card is `kanbanCardCornerRadius` (7) — dense, containerless
    /// boards where the card barely rounds — and an iOS board card is `Theme.radiusCard` (18). A
    /// chip cannot be rounder than the card it sits inside; a 10pt chip in a 7pt card reads as a
    /// capsule crammed into a rectangle. So the chip takes the control radius *unless* its card is
    /// tighter than that, in which case it follows the card in.
    ///
    /// This reproduces both platforms' current values exactly — `min(10, 7 - 1) == 6` and
    /// `min(10, 18 - 1) == 10` — from one rule, which is the difference between a difference and a
    /// fork.
    static func cornerRadius(inCardOfRadius cardRadius: CGFloat) -> CGFloat {
        min(Theme.radiusControl, max(0, cardRadius - cardInset))
    }
}

/// The board card's read-only metadata chip: a glyph and a label, both in the chip's own tint, over
/// a wash of the same colour.
///
/// Deliberately **not** a `KanbanMetaChip`: an event or a bundle has no completion circle, no list
/// and no estimate, and cannot be edited field-by-field from the card, so its chips stay read-only
/// and carry the calendar's own colour. It borrows the task chip's geometry — same padding, same
/// icon and label sizes — so the two read as one family without pretending an event is a task.
///
/// The tint applies to the glyph *and* the label rather than to the glyph alone, because a tinted
/// glyph beside grey text on a grey pill made every chip read as disabled. Both platforms had
/// already learned that separately, which is exactly how you end up with two of these.
///
/// This was `CalendarBoardMetadataChip` on macOS and a `private iOSCalendarBoardMetadataChip` in
/// `iOSBoardCards.swift` whose doc comment read "Matches macOS's `CalendarBoardMetadataChip`" —
/// a copy that documented its own obligation to stay in step and had no mechanism for doing so.
struct CadenceBoardMetadataChip: View {
    let title: String
    let systemImage: String
    let tint: Color
    /// The corner radius of the card this chip is drawn inside. The chip derives its own from it —
    /// see `CadenceBoardMetadataChipMetrics.cornerRadius(inCardOfRadius:)`.
    let cardCornerRadius: CGFloat
    /// Whether the chip stretches to its container's width.
    ///
    /// A genuine per-surface difference rather than a token one, and it is not a platform switch:
    /// iOS lays its task chips out in a two-column `LazyVGrid`, where a cell that does not fill
    /// leaves a ragged right edge, and macOS lays its two event chips in an intrinsic-width
    /// `HStack`, where filling would stretch "Repeats" across half a 306pt column.
    var fillsWidth: Bool = false

    var body: some View {
        HStack(spacing: CadenceBoardMetadataChipMetrics.spacing) {
            Image(systemName: systemImage)
                .font(.system(size: CadenceBoardMetadataChipMetrics.iconSize, weight: .semibold))
                .frame(width: CadenceBoardMetadataChipMetrics.iconColumnWidth)

            Text(title)
                .font(.system(size: CadenceBoardMetadataChipMetrics.labelSize, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(CadenceBoardMetadataChipMetrics.minimumScale)

            if fillsWidth {
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, CadenceBoardMetadataChipMetrics.horizontalPadding)
        .padding(.vertical, CadenceBoardMetadataChipMetrics.verticalPadding)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(tint.opacity(CadenceCalendarEventStyle.chipTintOpacity()))
        .clipShape(
            RoundedRectangle(
                cornerRadius: CadenceBoardMetadataChipMetrics.cornerRadius(inCardOfRadius: cardCornerRadius),
                style: .continuous
            )
        )
    }
}
