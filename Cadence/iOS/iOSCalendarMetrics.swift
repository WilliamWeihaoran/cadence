import CoreGraphics

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
/// `iOSTimelineTaskBlock` and `iOSTimelineBundleBlock` at a flat 58pt hour, having had its own
/// unreachable `regular ? 58 : 48` ramp deleted in the Today slice. The Calendar grid's `64 : 58`
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

    /// How often the ladder says the hour louder: every third label, and every third line.
    ///
    /// Stated once because **both** timed surfaces already count to three — Today's timeline and the
    /// Calendar grid spell the identical `% 3` and then disagree about what the emphasis *is* (see
    /// `iOSCalendarHairlineMetrics`). A cadence and the weights it selects between belong together;
    /// splitting them is how one of the two got copied without the other.
    static let hourEmphasisInterval: Int = 3

    /// The `12 AM` label on an emphasised hour, and on the two between.
    ///
    /// The one part of the ladder the two surfaces already agreed on, to the digit. Named so the
    /// agreement is a read rather than a coincidence that survived.
    static let hourLabelOpacity: Double = 0.9
    static let hourLabelMutedOpacity: Double = 0.45

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

    /// The strip of `iOSCalendarMiniChip`s under the date — two unscheduled tasks, a "N timed"
    /// count, an overflow line. Already one figure for both widths before this sweep.
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
/// - **`hourMajor`/`hourMinor`** are the ladder, selected between by
///   `iOSCalendarTimelineMetrics.hourEmphasisInterval`.
///
/// Two calendar hairlines are deliberately **not** here. The Board's column separator is
/// `iOSCalendarBoardMetrics`', because it already agrees with the Mac's Board rather than with this
/// screen; and the bundle sheet's row rule is the app's row-separator weight (`CadenceFieldRows`,
/// the task inspector, Today's schedule panel all draw 0.35), so pulling it in here would break the
/// agreement it already has.
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

    /// The hour ladder. Every third line reads as a rung and the two between it as texture; the
    /// gap between the two weights is the whole effect, so they are stated as a pair.
    static let hourMajorOpacity: Double = 0.46
    static let hourMinorOpacity: Double = 0.20
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

    /// The least the date title may be squeezed to. 208 was the iPad's, and it is the one with a
    /// reason on it — under it the title starts truncating, which is as true on a phone in landscape
    /// (where the single-row layout is now reachable) as it is on an iPad.
    static let titleMinWidth: CGFloat = 208
    static let titleIdealWidth: CGFloat = 246
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
