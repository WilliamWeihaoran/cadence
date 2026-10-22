import CoreGraphics
import SwiftUI

/// Every measurement the iOS calendar's three presentations are drawn with, and the short list of
/// figures that legitimately vary with the width of the host.
///
/// The calendar was the last big iPhone/iPad divergence in `Cadence/iOS/`: thirty-odd
/// `horizontalSizeClass` branches across the timed grid, the toolbar and the Board. Most of them
/// were not decisions. The same weekday label was set at 11pt on one device and 10 on the other; the
/// same day-number circle at 36 and 32; the same chip strip inset 7 and 5; the same toolbar band
/// padded *more* vertically on the phone than on the iPad, which is backwards from every other ramp
/// in the app. None of that is a fact about available space — it is one number written twice.
///
/// What survives is stated here, and the rule it survives under is the one the earlier slices used:
/// a figure may vary with width when it is about the **host** rather than about the thing being
/// drawn. Two do. The page gutter is the app's own, read straight off `CadencePageHeaderMetrics` rather
/// than re-invented here, so the calendar's top row and its Board share the margin All Tasks, Inbox
/// and Today already use. The other two — the hour rail's width and a day column's preferred width —
/// live in `CadenceCalendarWeekGridLayout`, where they are already tested, because they answer "how
/// much of a week fits in this pane".
///
/// Deliberately **outside** `#if os(iOS)`, like `CadencePageHeaderMetrics`, `iOSTaskCollectionMetrics`
/// and `iOSTaskInspectorMetrics`: `Cadence/iOS/` is invisible to the macOS-built test target, and
/// the part worth pinning is the decisions rather than the drawing. Nothing in this file draws.

// MARK: - The timed grid

/// The hour canvas and the band of day headers above it.
///
/// **Nothing here takes a width.** The one figure that looks like it should — how tall an hour is —
/// is the clearest case: `iOSSchedulePanel`, Today's timeline, draws the *same*
/// `iOSTimelineTaskBlock` at a flat 58pt hour, having had its own unreachable
/// `regular ? 58 : 48` ramp deleted in the Today slice. The Calendar grid's `64 : 58`
/// therefore did not describe a phone against an iPad at all: it made the same scheduled task, in
/// the same block, occupy a different number of points on the two timed surfaces of a single iPad.
/// The grid also carries a 1×–3× pinch now, so the base height is a resting density the user can
/// leave whenever they want, not a budget the layout has to get right.
nonisolated enum iOSCalendarTimelineMetrics {

    // MARK: The hour ladder

    /// The resting height of one hour, before `CadenceCalendarZoom` multiplies it — the app's one
    /// answer to how tall an hour on an iOS timeline is, for both of the surfaces that ask.
    ///
    /// **This used to say "58 is `iOSSchedulePanel.rowHeight`", and it was not (T-588.)** No such
    /// reference existed: `iOSSchedulePanel.rowHeight` was a second hand-typed `58` in
    /// `iOSTodaySchedulePanel.swift`, and the sentence here was an invariant with nothing enforcing
    /// it. It is a real read now, and `theTodayTimelineReadsItsHourFiguresFromHere` fails the build
    /// if a third copy appears.
    static let hourHeight: CGFloat = 58

    /// The `12 AM` labels down the rail. The larger of the two it was, because the rail is a fixed
    /// column of chrome rather than something competing for room: at 11pt `12 AM` measures roughly
    /// 31pt, which clears `CadenceCalendarWeekGridLayout.timeRailWidth`'s narrow spelling of 48 with
    /// the inset below to spare.
    ///
    /// Today's timeline reads this too, having carried its own `rowHeight > 50 ? 11 : 10` — a ramp
    /// whose lower branch nothing could reach, because that pane's row is always this file's
    /// `hourHeight`.
    static let hourLabelSize: CGFloat = 11

    /// Between an hour label and the rail's closing hairline. The narrow rail is the one with no
    /// slack in it and it already used 8; the wide rail loses nothing by matching, since the label
    /// is right-aligned and the inset is measured from the same edge either way.
    ///
    /// **The one figure the duplication had already pulled apart (T-588):** Today's timeline drew
    /// its own `9` against this `8`, on the same rail, for the same label. 8 wins on evidence
    /// rather than on seniority — it is the value with a measurement behind it
    /// (`theHourLabelFitsTheNarrowRail` checks the label against the narrow rail's 48) and the
    /// value the Calendar grid draws at both widths, so keeping 9 would have meant moving the
    /// surface that measured to match the surface that did not.
    static let hourLabelTrailingInset: CGFloat = 8

    /// How far the now-line is held off each edge of a day column ([[T-1131]]).
    ///
    /// 4, which is `TimelineBlockStyle.calendar`'s `leadingInset`/`trailingInset` — the pair the
    /// Mac's Calendar page already draws the same rule between. The rule is the one mark on a timed
    /// grid allowed to be louder than the grid, so what it must not do is run edge to edge into the
    /// column hairline beside it and read as a border.
    ///
    /// Today's timeline passes 0 instead, and that is a layout difference rather than a second
    /// vocabulary: its lane already begins past a 50pt rail, and the hour hairline directly above
    /// the rule spans that lane exactly, so an inset here would leave the two lines starting at
    /// different x on the same row.
    static let nowLineInset: CGFloat = 4

    // MARK: The day header band

    /// `MON` over a day column.
    ///
    /// **This is now macOS's figure, and the 11 it replaces had a reason that did not hold.** It was
    /// documented here as "the same label the month grid sets over its own columns, at the same
    /// 11pt" — but `iOSCalendarMonthScrollingGrid` drew that row at 10 for the agenda and 11 for the
    /// full month, so the same view answered the question twice and there was nothing stable to
    /// agree with. The whole weekday-header band is stated once now, in
    /// `CadenceCalendarWeekdayHeaderMetrics`, which the Mac's `CalDayHeaderView` and both month
    /// grids read too; the reasoning for each figure is there. `docs/TODO.md` T-277.
    static var weekdaySize: CGFloat { CadenceCalendarWeekdayHeaderMetrics.labelSize }

    /// The day number, and the circle that fills behind it on today.
    ///
    /// 18-in-32 rather than 20-in-36. Neither was forced by room — a day column is at least
    /// `CadenceCalendarWeekGridLayout.preferredDayColumnWidth`, 104pt, at *both* widths — so the tie
    /// is broken by what the band is for: the number names the day, and the strip of chips under it
    /// previews the day. The larger circle was taking its extra 4pt straight out of that preview,
    /// which was already overflowing its stated minimum (see `dayHeaderHeight`). macOS had reached
    /// the same pair independently, which is why they are stated once now.
    static var dayNumberSize: CGFloat { CadenceCalendarWeekdayHeaderMetrics.dayNumberSize }
    static var dayCircleSize: CGFloat { CadenceCalendarWeekdayHeaderMetrics.dayCircleSize }

    /// Between the weekday label and the day number.
    static var dayLabelSpacing: CGFloat { CadenceCalendarWeekdayHeaderMetrics.labelSpacing }

    /// Above and below the weekday/number pair, inside the band.
    static let dateBlockVerticalPadding: CGFloat = 5

    /// The weekday label's line, as SwiftUI lays it out. Used only to size the block around it —
    /// the same derivation `iOSTaskInspectorMetrics.titleLineHeight` makes.
    static var weekdayLineHeight: CGFloat { weekdaySize * 1.2 }

    /// The top half of the band: weekday over day number.
    ///
    /// Derived, not stated, so the circle cannot be resized without the band following. The hand-set
    /// pair this replaces was `66 : 58`, and 58 is what this arithmetic comes back with — evidence
    /// that the compact spelling was the considered one and the regular an unexamined step above it.
    static var dateBlockHeight: CGFloat {
        dateBlockVerticalPadding * 2 + weekdayLineHeight + dayLabelSpacing + dayCircleSize
    }

    /// The strip of `iOSCalendarMiniChip`s under the date at its shortest. Since T-1474 the strip
    /// grows past this with the day's split (`previewHeight(for:)`); this is the floor.
    static let previewMinHeight: CGFloat = 42

    /// Around that strip. 6 is the inset the month grid gives the identical chips in its cells;
    /// the band was using 7 on one device and 5 on the other for the same component.
    static let previewInset: CGFloat = 6

    /// The whole band: the rail reserves it, each header fills it, and the initial scroll placement
    /// has to clear it.
    ///
    /// **Derived, and that is a fix rather than tidiness.** The band was a hand-set `112 : 101`
    /// against content that needs `dateBlockHeight + previewMinHeight + previewInset` — 105 at the
    /// compact spelling's own numbers. So the phone's header overflowed the height the grid had
    /// reserved for it by 4pt, every column, and the chip strip never actually got the 42pt it asks
    /// for. Computing the band from its parts is the only way that stays true when a part changes.
    static var dayHeaderHeight: CGFloat {
        dateBlockHeight + previewMinHeight + previewInset
    }

    // MARK: The strip's height follows what it draws (T-1474)

    /// One `iOSCalendarMiniChip` line in the strip — the chip's untimed form,
    /// `iOSCalendarMiniChip.height(hasTime: false)`. Restated here because that view sits inside
    /// `#if os(iOS)` and this arithmetic must be testable on the macOS-built target;
    /// `iOSCalendarMetricsTests` reads the chip's source to keep the two equal.
    static let bandChipHeight: CGFloat = 17

    /// Between lines of the strip — the chip `VStack`'s spacing.
    static let bandLineSpacing: CGFloat = 3

    /// The "+N more" line's point size, and the line it lays out in.
    static let overflowLabelSize: CGFloat = 9
    static var overflowLineHeight: CGFloat { overflowLabelSize * 1.2 }

    /// The chip strip for one day's split: its chip rows, then the "+N more" line if anything is
    /// hidden. Never shorter than `previewMinHeight`, so a quiet week keeps the band it always had.
    static func previewHeight(for split: CadenceCalendarMonthCellPriority.Split) -> CGFloat {
        let chips = max(0, split.visible)
        let hasOverflowLine = split.hidden > 0
        let lines = chips + (hasOverflowLine ? 1 : 0)
        guard lines > 0 else { return previewMinHeight }
        let content = CGFloat(chips) * bandChipHeight
            + (hasOverflowLine ? overflowLineHeight : 0)
            + CGFloat(lines - 1) * bandLineSpacing
        return max(previewMinHeight, content)
    }

    /// **The band is as tall as the busiest day in view needs, up to the strip's capacity.** The
    /// cap is on item COUNT (`CadenceCalendarAllDayBandPriority`); this turns the busiest visible
    /// day's split into points. Every row added pushes the hour grid down, which is the trade the
    /// owner accepted for 6 rows on iPhone and 8 on iPad: it is strip-versus-timeline, not
    /// events-versus-tasks. `dayHeaderHeight` above is the floor.
    static func dayHeaderHeight(for splits: [CadenceCalendarMonthCellPriority.Split]) -> CGFloat {
        let preview = splits.map(previewHeight(for:)).max() ?? previewMinHeight
        return dateBlockHeight + max(previewMinHeight, preview) + previewInset
    }
}

// MARK: - The hairlines

/// Every rule the calendar's grids are drawn with: the hour ladder, the lines between days, and the
/// edges of the chrome pinned around the canvas.
///
/// **`Theme.borderSubtle` was appearing at ten different opacities on one screen** (`docs/TODO.md`
/// T-595), which is what a token gets when each view decides for itself how much of it to use. The
/// sharpest instance was a single month cell whose right edge drew at 0.30 and whose bottom edge
/// drew at 0.42 — one cell, two weights, no reason for either — while the timed grid's day header,
/// four hundred lines away, set both of its own edges to one number and was right to.
///
/// Three weights survive, and each answers a question the others do not:
///
/// - **`dayEdge`** rules one day off from the next, inside a grid. The month cell's two edges and
///   the timed canvas's column edge are the same line in two presentations of the same screen.
/// - **`pinnedEdge`** closes the chrome that does *not* scroll — the day-header band along its
///   bottom and its columns, the hour rail down its trailing side. Those two lines **meet**, at the
///   top-left corner of the canvas, which is why one of them being lighter than the other was
///   visible rather than merely inconsistent.
/// The ladder itself used to be a third entry here — a major/minor pair, selected between by a
/// cadence stated a few lines up in this file. It is `CadenceCalendarHourLadderMetrics` now,
/// because [[T-1129]] gave the Mac the same rung and the cadence had to travel with its weights.
///
/// One calendar hairline is deliberately **not** here: the Board's column separator is
/// `iOSCalendarBoardMetrics`', because it already agrees with the Mac's Board rather than with this
/// screen.
nonisolated enum iOSCalendarHairlineMetrics {
    /// A hairline: the thinnest rule that still resolves on a 2x screen. The grids drew 0.5
    /// everywhere already; it is stated so the next one does not arrive at 1.
    static let width: CGFloat = 0.5

    /// One day against the next, inside a grid.
    ///
    /// **0.42, and neither of the three it replaces had a stated reason** — so this is decided the
    /// way T-588 decided the hour label's inset: by which value more of the repo already draws,
    /// rather than by inventing a fourth. 0.42 and 0.34 each appear at two sites app-wide and 0.30
    /// at one, so 0.30 loses outright; between the other two, 0.42 is the one that wins the pair
    /// the cell itself was drawing (0.30 against 0.42), and taking the timed canvas's 0.34 to it
    /// leaves the month grid's heavier edge where it was rather than moving both.
    static let dayEdgeOpacity: Double = 0.42

    /// The pinned chrome's closing edges: under the day-header band, and down the hour rail.
    ///
    /// **0.65 over the rail's 0.75**, on the same rule: it is the weight two of the three lines
    /// already drew, and the third is the one that meets them.
    static let pinnedEdgeOpacity: Double = 0.65

    /// The hour ladder is **not** here any more: its cadence and its two weights are
    /// `CadenceCalendarHourLadderMetrics`, which the Mac's timed canvas reads too ([[T-1129]]).
    /// The figures are unchanged — 0.46 against 0.20, every third hour — and the move is what
    /// stopped the Mac growing a second spelling of them.
}

// MARK: - The month grid

/// The month grid's cells, in both of the containers that hold one.
nonisolated enum iOSCalendarMonthMetrics {
    /// The shortest a full-size month cell may be squeezed to.
    ///
    /// This is the figure `CadenceCalendarMonthAgendaSupport` names in its own doc as the reason the old
    /// month view showed three weeks — "at a 104pt minimum cell" — while the only place it was
    /// actually written was a bare `max(104, …)` in a view body, where that doc could not read it.
    /// A cell needs it because it lists up to five `iOSCalendarMiniChip`s.
    static let minimumCellHeight: CGFloat = 104
}

// MARK: - The toolbar

/// The calendar's top row: the date title that is also the date control, and the presentation
/// switch.
///
/// This row **is** a page header, so its gutter and its row spacing are `CadencePageHeaderMetrics`'
/// rather than a fourth private spelling of them. It carries no identity tile — see `titleBlock` in
/// `iOSCalendarChromeViews.swift` for why the calendar is the one header without one. It used to
/// draw a private 34/15 tile, which is exactly the drift `CadencePageHeaderMetrics.iconSize` was
/// written to stop, and it drew it on iPad only, so the one page in the app whose header changed
/// identity depending on the device was this one.
nonisolated enum iOSCalendarToolbarMetrics {
    /// Above and below the row. One number, where it was `regular ? 10 : 12` — a ramp pointing the
    /// wrong way, giving the phone a *taller* band of chrome than the iPad above a day-header band
    /// that is itself over 100pt. Every other ramp in the app spends less at compact width.
    static let verticalPadding: CGFloat = 10

    /// Between the title block and the controls, and between the two control groups. The row was
    /// spelling this 12/8/10 depending on which of its three layouts you were in.
    static let controlSpacing: CGFloat = 8

    /// Between the title row and the control row when the two wrap.
    static let stackSpacing: CGFloat = 11

    /// The least the date title may be squeezed to at **regular** width. 208 was the iPad's, and it
    /// is the one with a reason on it — under it the title starts truncating.
    static let titleMinWidth: CGFloat = 208

    /// The same floor on a phone, where it is a different number because the title is drawn at a
    /// different size and the row has a third less of it to give.
    ///
    /// `iOSDateJumpTitleMetrics.page` draws this title at **18pt** compact against 21pt regular,
    /// and the longest label either timed surface produces is Month's `October 2026` — about 118pt
    /// at 18pt bold, plus the 4pt gap and the chevron. 140 clears that with room to spare, and
    /// `minimumScaleFactor` is the backstop under it rather than truncation, because this metrics
    /// set scales: "August 2026" losing its year names no month.
    ///
    /// **Carrying the iPad's 208 onto the phone is what cost the switcher its place on this row.**
    /// 208 + 8 + a 238pt standard-density mode group is 454 against 361pt of iPhone row, so
    /// `ViewThatFits` could never accept the single-row layout and always wrapped — spending a
    /// whole row of a 852pt screen on three pills, above a grid that was already too cramped to
    /// show an event's title.
    static let titleCompactMinWidth: CGFloat = 140

    /// The floor for the width the row is actually being laid out at. Overloads the constant above
    /// rather than renaming it, so `iOSCalendarMetricsTests`' pin on the regular figure still reads
    /// the same name the rest of the app does.
    static func titleMinWidth(isRegularWidth: Bool) -> CGFloat {
        let regular: CGFloat = titleMinWidth
        return isRegularWidth ? regular : titleCompactMinWidth
    }

    static let titleIdealWidth: CGFloat = 246

    /// What the title asks for on a phone — and **the number `ViewThatFits` actually reads.**
    ///
    /// Lowering `titleMinWidth` alone did not move the switcher onto the date's row, and the
    /// screenshot is what said so: on a 393pt iPhone the toolbar still drew `Oct 4` over a wrapped
    /// `Week | Month | Board`. `ViewThatFits` measures each candidate at its **ideal** width, not at
    /// its floor, so the single-row branch was asking for `titleIdealWidth` 246 + `controlSpacing` 8
    /// + a ~163pt `.compact` mode group = ~417 against 361pt of row, and went on taking the wrapped
    /// fallback while the floor arithmetic said it should not have. Measured on `Cadence-iPhone15`
    /// at 393x852, 2026-10-04.
    ///
    /// A phone's title asks for exactly its floor, so the row's slack belongs to the controls —
    /// the same priority `singleRowToolbar` already states with `layoutPriority(1)`. `titleMaxWidth`
    /// is untouched: the title still grows into whatever the controls leave.
    static let titleCompactIdealWidth: CGFloat = titleCompactMinWidth

    /// The ideal for the width the row is actually being laid out at. Overloads the constant above
    /// for the same reason `titleMinWidth(isRegularWidth:)` does.
    static func titleIdealWidth(isRegularWidth: Bool) -> CGFloat {
        let regular: CGFloat = titleIdealWidth
        return isRegularWidth ? regular : titleCompactIdealWidth
    }

    static let titleMaxWidth: CGFloat = 312

    /// The single-row layout's floor, so the row is a full touch target even with a short title.
    static let singleRowMinHeight: CGFloat = 48
}

// MARK: - The Board

/// The Board's day columns.
///
/// Two of its branches are real and stay — see `iOSCalendarBoardPlanner`. What is here is the one
/// that was not: a bespoke `20 : 14` page gutter sitting under a toolbar that used `18 : 16`, so the
/// two halves of one screen were inset by different amounts at both widths.
nonisolated enum iOSCalendarBoardMetrics {
    /// Between one day column and the next. Also the figure
    /// `CalendarBoardPlannerSupport.compactColumnWidth` subtracts when it sizes a column to leave
    /// the next day peeking.
    static let columnSpacing: CGFloat = 10

    /// Between one day column's lane and the next.
    ///
    /// **Deliberately not `iOSCalendarHairlineMetrics`'.** This one weight of the ten T-595 found
    /// was not adrift: `CalendarBoardDayColumnSupportViews` draws the Mac's Board lane at the same
    /// 0.28, at the same 1pt, so the figure to keep agreeing with is the other platform's Board
    /// rather than the other presentations of this screen. It is a full point rather than a
    /// hairline because a lane is a region and not a grid rule.
    static let columnSeparatorOpacity: Double = 0.28
    static let columnSeparatorWidth: CGFloat = 1

    /// The board's leading inset, which is the calendar page's gutter — the same one the toolbar
    /// above it and every other iOS page uses.
    static func horizontalPadding(isRegularWidth: Bool) -> CGFloat {
        iOSCalendarPageMetrics.horizontalPadding(isRegularWidth: isRegularWidth)
    }
}

// MARK: - The page

/// The one figure on the calendar that is genuinely about the host rather than about the calendar.
nonisolated enum iOSCalendarPageMetrics {
    /// The margin between the calendar's content and the edge of its pane.
    ///
    /// Ramped, and deliberately not re-decided here: it is `CadencePageHeaderMetrics`' page gutter, so
    /// the calendar is inset by the same amount as All Tasks, Inbox and Today rather than by a
    /// number of its own. The calendar had two of its own — 18/16 on the toolbar and 20/14 on the
    /// Board — which is how one screen came to have two left edges.
    static func horizontalPadding(isRegularWidth: Bool) -> CGFloat {
        CadencePageHeaderMetrics.metrics(role: .page, isRegularWidth: isRegularWidth).horizontalPadding
    }
}

// MARK: - The timed grid's side-by-side layout

/// Where each block in one iOS day column sits **across** the column: tasks and events laid out
/// against each other by the one shared solver, as macOS's
/// `TimelineMetricsSupport.computeUnifiedLayouts` does (T-3165).
///
/// **Why this exists.** T-3161 gave the iOS day column an overlap layout for EVENTS ONLY. Tasks
/// kept drawing full width on top of whatever they overlapped, so a scheduled task at 12:45-1:30
/// was painted straight across a 12:30-1:30 event, cutting through its title and hiding its time
/// row, while the Mac drew the same pair as two columns. Both kinds now go through one
/// `CadenceCalendarOverlapLayout.solve` pass, so each reserves a column against the other.
/// At **regular** width only events cascade, exactly as on the Mac: a task never lays itself over
/// an event and an event never lays itself over a task. At **compact** width every kind cascades
/// (T-3184) — see `Kind.mayCascade(isCompactWidth:)` for the owner's ruling and for why that is
/// not T-3165's bug coming back.
///
/// Outside `#if os(iOS)` for the reason the rest of this file is: the macOS-built test target can
/// read the decision, and the view in `iOSCalendarTimelineViews.swift` only draws what it says.
nonisolated enum iOSCalendarTimelineBlockLayout {

    /// The two kinds of timed block a day column draws.
    ///
    /// **There used to be a third, `.bundle`** ([[T-3170]]). The Block feature is gone from every
    /// iOS surface, and with it the one kind that took a different inset.
    enum Kind: Equatable, Sendable {
        case task
        case event

        /// Whether a block of this kind may cascade, and be cascaded over, at this width.
        ///
        /// **Regular width is macOS's answer and T-3165's: events only.** A regular day column is
        /// at least `CadenceCalendarWeekGridLayout.preferredDayColumnWidth`, so splitting a task
        /// off an event costs a column each and both still label themselves;
        /// `computeUnifiedLayouts` passes the same answer and the two surfaces agree.
        ///
        /// **Compact width is T-3184's: every kind.** The owner ruled that a task and an event
        /// overlapping on a phone-width column cascade rather than split, under the one rule
        /// [[T-3161]] already applies to events against each other — later start in front, no
        /// kind-based precedence anywhere.
        ///
        /// This is **not** a return to T-3165's bug, and the thing that makes it not one is
        /// `CadenceCalendarOverlapLayout.minimumVisibleLeadingEdge`: the block behind always keeps
        /// its leading edge and its rail, where T-3165's task was drawn full width on top.
        func mayCascade(isCompactWidth: Bool) -> Bool { isCompactWidth || self == .event }

        /// Leading and trailing inset of this kind's strip inside the day column. The figure this
        /// column has always drawn for both kinds it still draws, so a day with no overlaps keeps
        /// exactly the blocks it had. The 7 a Block's strip took went with the Block ([[T-3170]]).
        var inset: CGFloat { 9 }
    }

    /// One block offered to the layout, under whatever key the caller draws it by.
    struct Block<Key: Hashable> {
        let key: Key
        let kind: Kind
        let startMin: Int
        let endMin: Int
    }

    /// Gutter between two blocks that split a column, matching the Mac canvas's
    /// `TimelineBlockStyle.columnSpacing`. Not applied when there is only one column.
    static let columnSpacing: CGFloat = 2

    /// Column and cascade depth for every block, keyed the way the caller identifies it.
    ///
    /// Blocks are solved in the order given, which is the order the column draws them in, so a tie
    /// at the same start minute is broken the same way every pass. A block shorter than
    /// `CadenceCalendarOverlapLayout.minimumSlotMinutes` is widened to it, as macOS does.
    ///
    /// `isCompactWidth` is **required rather than defaulted**, for the reason
    /// `computeUnifiedLayouts` requires its threshold: a silently-absent width is indistinguishable
    /// from "regular", which is the branch that does not cascade, which is the bug T-3184 exists
    /// to fix. See `Kind.mayCascade(isCompactWidth:)`.
    static func placements<Key: Hashable>(
        for blocks: [Block<Key>],
        hourHeight: CGFloat,
        isCompactWidth: Bool
    ) -> [Key: CadenceCalendarOverlapPlacement] {
        let slots = blocks.map { block in
            CadenceCalendarOverlapLayout.Slot(
                startMin: block.startMin,
                endMin: max(block.endMin, block.startMin + CadenceCalendarOverlapLayout.minimumSlotMinutes),
                mayCascade: block.kind.mayCascade(isCompactWidth: isCompactWidth)
            )
        }
        let solved = CadenceCalendarOverlapLayout.solve(
            slots: slots,
            cascadeGapMinutes: CadenceCalendarOverlapLayout.cascadeGapMinutes(
                headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight,
                hourHeight: hourHeight
            )
        )
        return Dictionary(
            zip(blocks.map(\.key), solved),
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Draw order

    /// Everything the column draws *over* its blocks — the in-place draft and the now-line. Blocks
    /// are given z values strictly below this, so raising them above the background layers cannot
    /// raise them above the two marks that have to stay on top.
    static let overlayZIndex: Double = 2

    /// `zIndex` for every block in a day column: **start order, later start in front.**
    ///
    /// **This is half of the cascade, and without it the compact cascade is upside down.** A
    /// cascaded block is indented past the one it is laid over and must be *painted over* it as
    /// well — macOS gets that for free, because its blocks layer renders one array sorted by start
    /// minute at a single `zIndex` and only events ever cascade. The iOS column draws two separate
    /// `ForEach`es, events then tasks, so a task was painted over every event in the column
    /// whatever the clock said. Let a task cascade in that arrangement and the event
    /// it indented past is drawn back over it at full width: exactly T-3165's bug, from the fix for
    /// it. Draw order is now the solver's own order, so the pair the solver put in front is the
    /// pair on top — and, because SwiftUI hit-tests topmost first, the one that takes the tap where
    /// a cascade overlaps.
    ///
    /// Ties at one start minute fall back to the order handed in, which is the order the column
    /// builds its blocks in, so a redraw cannot swap two blocks' z between passes.
    ///
    /// Values land in `1 ..< overlayZIndex`: above the grid lines, the work-hours band and the day
    /// wash, which are declared before the blocks and keep SwiftUI's default 0, and below the
    /// draft and the now-line, which take `overlayZIndex`.
    static func zIndexes<Key: Hashable>(for blocks: [Block<Key>]) -> [Key: Double] {
        guard !blocks.isEmpty else { return [:] }
        let order = blocks.indices.sorted { lhs, rhs in
            if blocks[lhs].startMin != blocks[rhs].startMin {
                return blocks[lhs].startMin < blocks[rhs].startMin
            }
            return lhs < rhs
        }
        let span = Double(blocks.count)
        var result: [Key: Double] = [:]
        for (rank, index) in order.enumerated() {
            result[blocks[index].key] = 1 + Double(rank) / span
        }
        return result
    }

    /// Leading offset and width of one placed block inside a day column `columnWidth` wide.
    ///
    /// The kind's own strip, split into `totalColumns` equal columns with a `columnSpacing` gutter,
    /// then indented by the cascade if the block is stacked over an earlier event. A single
    /// un-overlapped block gets its strip back whole.
    static func horizontalFrame(
        for placement: CadenceCalendarOverlapPlacement,
        kind: Kind,
        columnWidth: CGFloat
    ) -> (x: CGFloat, width: CGFloat) {
        let usable = max(0, columnWidth - kind.inset * 2)
        let columns = max(placement.totalColumns, 1)
        let slotColumnWidth = usable / CGFloat(columns)
        let slotWidth = max(0, slotColumnWidth - (columns > 1 ? columnSpacing : 0))
        let indent = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: slotWidth, depth: placement.cascadeDepth)
        return (kind.inset + CGFloat(placement.column) * slotColumnWidth + indent, max(0, slotWidth - indent))
    }
}

/// Geometry for the converted calendar. Padding stays fixed; text line gains reserve space.
nonisolated enum iOSCalendarTypographyMetrics {
    static func lineGain(_ base: CGFloat, role: CadenceTypographyRole = .metadata,
                         at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        CadenceTypeScale.growth(role, base: base, at: size, scaling: scaling) * CadenceTypeScale.lineHeightRatio
    }

    static func chipHeight(hasTime: Bool, at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        (hasTime ? 29 : iOSCalendarTimelineMetrics.bandChipHeight) + lineGain(10, at: size, scaling: scaling)
            + (hasTime ? lineGain(8, at: size, scaling: scaling) : 0)
    }

    static func dayCircle(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        iOSCalendarTimelineMetrics.dayCircleSize + lineGain(iOSCalendarTimelineMetrics.dayNumberSize, at: size, scaling: scaling)
    }

    static func dateBlock(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        iOSCalendarTimelineMetrics.dateBlockHeight
            + lineGain(iOSCalendarTimelineMetrics.weekdaySize, role: .sectionLabel, at: size, scaling: scaling)
            + lineGain(iOSCalendarTimelineMetrics.dayNumberSize, at: size, scaling: scaling)
    }

    /// Preserve the base row budget, spending it on fewer readable rows as labels grow.
    /// The priority helper carries every omitted item into the overflow count.
    static func bandCapacity(isRegularWidth: Bool, at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> Int {
        let base = CadenceCalendarAllDayBandPriority.capacity(isRegularWidth: isRegularWidth)
        let multiplier = max(1, CadenceTypeScale.multiplier(.metadata, at: size, scaling: scaling))
        return max(1, Int(CGFloat(base) / multiplier))
    }

    static func bandHeight(for splits: [CadenceCalendarMonthCellPriority.Split],
                           at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        let previews = splits.map { split in
            let lines = split.visible + (split.hidden > 0 ? 1 : 0)
            return CGFloat(split.visible) * chipHeight(hasTime: false, at: size, scaling: scaling)
                + (split.hidden > 0 ? CadenceTypeScale.lineHeight(.metadata, base: iOSCalendarTimelineMetrics.overflowLabelSize, at: size, scaling: scaling) : 0)
                + CGFloat(max(0, lines - 1)) * iOSCalendarTimelineMetrics.bandLineSpacing
        }
        return dateBlock(at: size, scaling: scaling)
            + max(iOSCalendarTimelineMetrics.previewMinHeight, previews.max() ?? 0)
            + iOSCalendarTimelineMetrics.previewInset
    }

    /// **The strip's height on a grid that draws no date block** — the single-day pane's band
    /// ([[T-3163]]).
    ///
    /// `bandHeight(for:at:scaling:)` above is the scrolling grid's figure and it always pays for a
    /// `dateBlock` and a `previewMinHeight` floor, because every column of a week has a weekday and
    /// a day number over it and the pinned row has to be one height. A single-day pane has neither:
    /// the date is the page's own title, and a day with nothing all-day on it must come back
    /// **zero** so the hour ladder starts exactly where it always did. That is why this is a second
    /// function rather than a flag on the first — the floor is the thing that cannot be shared.
    ///
    /// The strip's own inset is paid on both edges here; the day header pays it once because the
    /// date block above it carries the top one.
    static func allDayStripHeight(for split: CadenceCalendarMonthCellPriority.Split,
                                  at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        let lines = split.visible + (split.hidden > 0 ? 1 : 0)
        guard lines > 0 else { return 0 }
        let content = CGFloat(split.visible) * chipHeight(hasTime: false, at: size, scaling: scaling)
            + (split.hidden > 0 ? CadenceTypeScale.lineHeight(.metadata, base: iOSCalendarTimelineMetrics.overflowLabelSize, at: size, scaling: scaling) : 0)
            + CGFloat(max(0, lines - 1)) * iOSCalendarTimelineMetrics.bandLineSpacing
        return content + iOSCalendarTimelineMetrics.previewInset * 2
    }

    static func hourHeight(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        let scaled = iOSCalendarTimelineMetrics.hourHeight * CadenceTypeScale.multiplier(.metadata, at: size, scaling: scaling)
        guard scaling == .enabled, size > .large else { return scaled }
        // A quarter-hour gets one title line plus 2pt above/below and the 4pt inter-block gap.
        // All minute-to-Y and drag math consumes this same hour height.
        let title = CadenceTypeScale.lineHeight(.metadata, base: 11, at: size, scaling: scaling)
        let completion = CadenceTypeScale.size(.metadata, base: 13, at: size, scaling: scaling) + 2
        let content = max(title, completion)
        return max(scaled, 4 * max(28, content + 8))
    }

    static func railWidth(_ base: CGFloat, at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        base * max(1, CadenceTypeScale.multiplier(.metadata, at: size, scaling: scaling))
    }

    static func monthColumnWidth(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        guard scaling == .enabled, CadenceTypeScale.isAccessibilitySize(size) else { return 0 }
        // Three weekday glyphs, a day badge and fixed side padding must fit in each column.
        return max(44, CadenceTypeScale.lineHeight(.metadata, base: 15, at: size, scaling: scaling) * 2 + 14)
    }

    static func compactRowHeight(_ base: CGFloat, at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        guard scaling == .enabled else { return base }
        return max(base, 32 + lineGain(15, at: size, scaling: scaling) + 12)
    }
}
