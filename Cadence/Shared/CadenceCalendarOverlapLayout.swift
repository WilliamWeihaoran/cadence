import Foundation
import CoreGraphics

/// Where one block sits inside the cluster of blocks it overlaps.
///
/// `column` / `totalColumns` are the equal-column packing every timed surface has always drawn.
/// `cascadeDepth` is the second axis T-3161 added: how many blocks already drawn *in this same
/// column* this one is laid over. Depth 0 is an ordinary column block and is byte-for-byte the old
/// behaviour; depth >= 1 is indented from its column's leading edge and runs to that column's
/// trailing edge, drawn on top of the blocks it indented past.
nonisolated struct CadenceCalendarOverlapPlacement: Equatable, Sendable {
    let column: Int
    let totalColumns: Int
    let cascadeDepth: Int

    static let single = CadenceCalendarOverlapPlacement(column: 0, totalColumns: 1, cascadeDepth: 0)
}

/// The overlap layout for timed blocks: equal columns, plus Apple-Calendar-style cascade for blocks
/// that start far enough apart to be safely stacked.
///
/// **The rule, and why it is a measurement rather than a constant.** A later block may be drawn over
/// an earlier one only because the earlier one's time and title rows are already painted *above*
/// where the later block starts, and stay readable. So the start gap a cascade needs is exactly the
/// height of that two-row header converted into minutes: `headerHeight / (hourHeight / 60)`. That is
/// zoom-aware for free — zoom out and an hour is fewer points, so protecting the same text takes
/// more minutes — and it means the threshold can never be tuned away from the thing it protects.
///
/// Owner's reference screenshot (the acceptance test, pinned in
/// `CadenceCalendarOverlapLayoutTests`): 2:15–6:15 / 3:00–5:45 / 4:00–6:00 cascade (gaps 45 and 60
/// minutes), while 7:00–10:55 / 7:15–10:00 split into equal halves (gap 15). At the Mac block's
/// measured 29pt header the threshold is 24 minutes at `hourHeight` 75 — between the 15 that must
/// split and the 45 that must cascade, with room on both sides.
///
/// Pure arithmetic over start/end minutes, in `Shared/` rather than beside either platform's views,
/// because macOS's `TimelineMetricsSupport` and iOS's timed day column both read it and a second
/// copy is how the two surfaces come to disagree about which events overlap.
nonisolated enum CadenceCalendarOverlapLayout {

    // MARK: - Input

    /// One block offered to the solver.
    struct Slot: Equatable, Sendable {
        let startMin: Int
        let endMin: Int
        /// Whether this block is allowed to cascade, and to be cascaded over.
        ///
        /// **Who passes `true` is the caller's ruling, not this file's.** macOS passes it for
        /// calendar events alone, and so does iOS at regular width: tasks and bundles keep the
        /// equal-column behaviour they have always had, both halves of the cascade test fail
        /// closed for them, and a task never lays itself over an event. iOS at **compact** width
        /// passes it for all three kinds (T-3184), because two ~75pt columns truncate both titles
        /// where one indented stack truncates neither.
        ///
        /// The solver does not know or care which kind a slot is. That is deliberate: the
        /// precedence rule is the same for every pair — later start in front — so a kind-based
        /// precedence would have to live somewhere, and the only place it could live is here.
        let mayCascade: Bool

        init(startMin: Int, endMin: Int, mayCascade: Bool) {
            self.startMin = startMin
            self.endMin = endMin
            self.mayCascade = mayCascade
        }
    }

    // MARK: - The header the threshold protects

    /// Line height of the system font at `size`, as `NSLayoutManager.defaultLineHeight` reports it.
    ///
    /// Measured on this toolchain, every weight from regular to bold giving the same answer, which
    /// is why weight is not a parameter. The table covers the sizes the timed blocks actually draw;
    /// anything else falls back to the rounded 1.2x the table is close to, which is a documented
    /// approximation rather than a measurement and must not be relied on for a new row without
    /// extending the table (and `CadenceCalendarOverlapLayoutTests` walks the table against
    /// AppKit, so a toolchain that changes these numbers goes red here rather than quietly moving
    /// the cascade threshold).
    static func lineHeight(forSystemFontSize size: CGFloat) -> CGFloat {
        switch size {
        case 7: return 8
        case 8: return 10
        case 9: return 11
        case 10: return 12
        case 11: return 13
        case 12: return 15
        case 13: return 16
        case 14: return 17
        case 15: return 18
        case 16: return 18
        case 17: return 20
        default: return (size * 1.2).rounded()
        }
    }

    /// Height of the two label rows at the top of a timed event block — the time row and the title
    /// row, plus the padding above them.
    ///
    /// This is the thing a cascading block must not cover, so it is the thing the threshold is
    /// derived from. It is read out of the block body rather than guessed: the row sizes, the stack
    /// spacing and the vertical padding are the block's own, and the line heights are AppKit's.
    static func headerHeight(
        verticalPadding: CGFloat,
        rowSpacing: CGFloat,
        titleFontSize: CGFloat,
        timeFontSize: CGFloat
    ) -> CGFloat {
        verticalPadding
            + lineHeight(forSystemFontSize: titleFontSize)
            + rowSpacing
            + lineHeight(forSystemFontSize: timeFontSize)
    }

    // The label rows the two event blocks actually draw, mirrored from their bodies rather than
    // read at runtime (a layout solver cannot ask a SwiftUI `Text` how tall it will be, and the
    // threshold has to be known before the block is built). `CadenceCalendarOverlapLayoutTests`
    // pins each number to the literal in the view file, so an edit to those rows fails there rather
    // than silently moving the cascade threshold away from the text it protects.

    /// Both blocks draw the title at 11pt semibold and the time range at 9pt.
    static let eventTitleFontSize: CGFloat = 11
    static let eventTimeFontSize: CGFloat = 9

    /// macOS `TimelineEventBlock.eventBlockBody`: `VStack(alignment: .leading, spacing: 2)`.
    static let macEventLabelRowSpacing: CGFloat = 2

    /// macOS header height for a given `TimelineBlockStyle.verticalPadding`.
    ///
    /// `.calendar` pads 3 and `.schedule` pads 4, so the Calendar page's header is 29pt and the
    /// Schedule panel's 30pt — one point, and one minute of threshold, apart.
    static func macEventHeaderHeight(verticalPadding: CGFloat) -> CGFloat {
        CadenceCalendarOverlapLayout.headerHeight(
            verticalPadding: verticalPadding,
            rowSpacing: macEventLabelRowSpacing,
            titleFontSize: eventTitleFontSize,
            timeFontSize: eventTimeFontSize
        )
    }

    /// **29pt** — `TimelineBlockStyle.calendar`'s 3pt padding + the 11pt time row + 2pt of spacing
    /// + the 13pt title row. This is the number T-3161's threshold is derived from on the Mac.
    static let macCalendarEventHeaderHeight: CGFloat =
        CadenceCalendarOverlapLayout.macEventHeaderHeight(verticalPadding: 3)

    /// iOS `iOSCalendarEventBlock`: `.padding(.vertical, 5)`, `VStack(spacing: 3)`, an 11pt title
    /// row *above* a 9pt time row. 5 + 13 + 3 + 11 = **32pt**. The two platforms order the rows
    /// differently and pad differently; only the sum matters to the threshold, so they are measured
    /// separately rather than converged.
    static let iOSEventLabelRowSpacing: CGFloat = 3
    static let iOSEventVerticalPadding: CGFloat = 5
    static let iOSEventHeaderHeight: CGFloat = CadenceCalendarOverlapLayout.headerHeight(
        verticalPadding: iOSEventVerticalPadding,
        rowSpacing: iOSEventLabelRowSpacing,
        titleFontSize: eventTitleFontSize,
        timeFontSize: eventTimeFontSize
    )

    // MARK: - The threshold

    /// Minutes of start-gap a block needs before it may be drawn over one it overlaps.
    ///
    /// `headerHeight / pointsPerMinute`, rounded **up**: a gap that covers the header by a fraction
    /// of a point is not a gap that clears it.
    ///
    /// A non-positive `hourHeight` is not a zoom level, it is a canvas that has not been laid out
    /// yet; nothing may cascade there, so the threshold is unreachable rather than zero — zero would
    /// cascade every block in the cluster at depth 0 width.
    static func cascadeGapMinutes(headerHeight: CGFloat, hourHeight: CGFloat) -> Int {
        guard hourHeight > 0, headerHeight > 0 else { return .max }
        let pointsPerMinute = hourHeight / 60
        return Int((headerHeight / pointsPerMinute).rounded(.up))
    }

    // MARK: - The solver

    /// Column and cascade depth for every slot, returned **in the order the slots were handed in**
    /// so a caller can zip the result against its own array.
    ///
    /// Greedy, as before, with one change: when placing a block, an earlier overlapping block only
    /// blocks its column if the two may **not** be stacked. Two events that start at least
    /// `cascadeGapMinutes` apart may share a column, and the later one takes the depth of the
    /// deepest block it is stacking on, plus one.
    ///
    /// Ties are broken by input order rather than left to the sort. `Array.sort` is not stable here,
    /// so two blocks starting in the same minute used to be ordered arbitrarily — which for a
    /// cascade would mean an arbitrary answer to "which one is on top".
    static func solve(slots: [Slot], cascadeGapMinutes: Int) -> [CadenceCalendarOverlapPlacement] {
        guard !slots.isEmpty else { return [] }

        let order = slots.indices.sorted { lhs, rhs in
            if slots[lhs].startMin != slots[rhs].startMin {
                return slots[lhs].startMin < slots[rhs].startMin
            }
            return lhs < rhs
        }

        var columns = [Int](repeating: 0, count: slots.count)
        var depths = [Int](repeating: 0, count: slots.count)
        var placed: [Int] = []

        for index in order {
            let slot = slots[index]
            var blocked = Set<Int>()
            var stackedDepth: Int?

            for earlier in placed where overlaps(slots[earlier], slot) {
                if canStack(later: slot, over: slots[earlier], cascadeGapMinutes: cascadeGapMinutes) {
                    continue
                }
                blocked.insert(columns[earlier])
            }

            var column = 0
            while blocked.contains(column) { column += 1 }
            columns[index] = column

            for earlier in placed
            where columns[earlier] == column
                && overlaps(slots[earlier], slot)
                && canStack(later: slot, over: slots[earlier], cascadeGapMinutes: cascadeGapMinutes) {
                stackedDepth = max(stackedDepth ?? 0, depths[earlier] + 1)
            }
            depths[index] = stackedDepth ?? 0

            placed.append(index)
        }

        return slots.indices.map { index in
            var widest = columns[index]
            for other in slots.indices where overlaps(slots[other], slots[index]) {
                widest = max(widest, columns[other])
            }
            return CadenceCalendarOverlapPlacement(
                column: columns[index],
                totalColumns: widest + 1,
                cascadeDepth: depths[index]
            )
        }
    }

    /// Shortest slot anything timed may occupy — the same floor macOS's `TimelineDayRange` and the
    /// event/bundle constructors already clamp to, stated here so a caller building slots has one
    /// place to read it from.
    static let minimumSlotMinutes = 5

    /// Half-open overlap: a block that ends exactly where the next begins does not overlap it.
    static func overlaps(_ lhs: Slot, _ rhs: Slot) -> Bool {
        lhs.startMin < rhs.endMin && lhs.endMin > rhs.startMin
    }

    /// Whether `later` may be drawn over `earlier` instead of taking a column beside it.
    ///
    /// Both must be cascade-eligible (events), and `later` must start at least a header's worth of
    /// minutes after `earlier` — never before it, and never in the same minute.
    static func canStack(later: Slot, over earlier: Slot, cascadeGapMinutes: Int) -> Bool {
        guard later.mayCascade, earlier.mayCascade else { return false }
        guard cascadeGapMinutes != .max else { return false }
        let gap = later.startMin - earlier.startMin
        return gap > 0 && gap >= cascadeGapMinutes
    }

    // MARK: - The indent

    /// Fraction of the width still *remaining* to the trailing edge that one cascade step consumes.
    ///
    /// A fraction of the remainder rather than of the whole, for one geometric reason: it can never
    /// run out. `x(depth) = slotWidth * (1 - 0.8^depth)` approaches the trailing edge without ever
    /// reaching it, so a stack ten deep still draws ten visible blocks, where a fixed point offset
    /// or a fixed fraction of the whole width inverts the block somewhere around step five.
    ///
    /// Against the owner's screenshot (a column about 345pt wide, left edges measured at roughly
    /// 0%, ~23% and ~36%): this rule gives 0%, 20% and **36.0%** — the second step lands on the
    /// measurement exactly and the first is three points of percentage inside the owner's stated
    /// pixel error. A fixed fraction of the whole width would have put step two at 46% and a fixed
    /// point offset at the same place; the measured steps shrink (≈79pt then ≈45pt), which is what a
    /// decaying rule is.
    static let cascadeIndentFractionOfRemainingWidth: CGFloat = 0.2

    /// Narrowest a cascaded block may be squeezed to.
    ///
    /// `TimelineBlockGeometry.handleCapsuleWidth` returns its full 18pt at a block width of 28 and
    /// shrinks below that, so 28pt is the narrowest block that still draws a full-size resize grab.
    /// The decay above never reaches zero on its own; this is the ceiling the indent is clamped to
    /// so that a pathological stack on a narrow column does not squeeze the front block away.
    ///
    /// **It is a ceiling, and since T-3184 it is no longer the last word** — see
    /// `minimumVisibleLeadingEdge`, which outranks it. On a column where `slotWidth` is at or under
    /// this figure the old clamp returned an indent of **zero**, which is a "cascade" that covers
    /// the block behind edge to edge: T-3165's bug, reached by arithmetic rather than by paint.
    static let minimumCascadedWidth: CGFloat = 28

    /// The least of the block *behind* a cascade that must stay uncovered.
    ///
    /// **This is the whole safety property of a cascade, stated as a number.** A cascade is only
    /// allowed to be a cascade rather than a burial because the block underneath keeps its leading
    /// edge: its rail if it is an event, its rim and plate if it is a task or a bundle. Cover that
    /// and the result is indistinguishable from the full-width overpaint T-3165 removed, no matter
    /// what the solver called it.
    ///
    /// **4pt**, which is what the leading edge is made of rather than a round number:
    /// `CadenceCalendarEventStyle.railWidth` is 3 and both block bodies draw a 1pt `strokeBorder`
    /// outside it. Anything less shows part of a rail; this shows the whole marker.
    /// `CadenceCalendarOverlapLayoutTests` pins it against `railWidth` so the two cannot drift.
    ///
    /// It binds only on a slot narrower than about 32pt — at 20pt and up the decay already clears
    /// it, and `minimumCascadedWidth` only pushes below it under `slotWidth` 32 — so no column any
    /// shipped surface draws at changes shape because of it. It is the floor that makes the
    /// guarantee true by construction instead of by measurement.
    static let minimumVisibleLeadingEdge: CGFloat = 4

    /// Leading indent for a block drawn at `depth` inside a slot `slotWidth` points wide.
    ///
    /// Three rules, in priority order: the decay sets the shape of the stack, `minimumCascadedWidth`
    /// stops the front block being squeezed away, and `minimumVisibleLeadingEdge` outranks both
    /// because a block behind that shows nothing is the bug. On a slot too narrow to honour the
    /// floor outright the sliver takes half the slot and no more, so neither block can vanish.
    ///
    /// The result is strictly inside `0 ..< slotWidth` for any `depth > 0` and `slotWidth > 0`:
    /// the front block is always narrower than the slot, and the block behind always keeps
    /// something.
    static func cascadeIndent(slotWidth: CGFloat, depth: Int) -> CGFloat {
        guard depth > 0, slotWidth > 0 else { return 0 }
        let remainingFraction = pow(1 - cascadeIndentFractionOfRemainingWidth, CGFloat(depth))
        let decayed = slotWidth * (1 - remainingFraction)
        let squeezeCeiling = max(0, slotWidth - minimumCascadedWidth)
        let sliverFloor = min(minimumVisibleLeadingEdge, slotWidth / 2)
        return max(min(decayed, squeezeCeiling), sliverFloor)
    }
}
