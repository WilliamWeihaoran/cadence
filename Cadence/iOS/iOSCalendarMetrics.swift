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

    /// The resting height of one hour, before `CadenceCalendarZoom` multiplies it. 58 is
    /// `iOSSchedulePanel.rowHeight` — the app's one answer to how tall an hour on an iOS timeline
    /// is, now given to both of the surfaces that ask.
    static let hourHeight: CGFloat = 58

    /// The `12 AM` labels down the rail. The larger of the two it was, because the rail is a fixed
    /// column of chrome rather than something competing for room: at 11pt `12 AM` measures roughly
    /// 31pt, which clears `CadenceCalendarWeekGridLayout.timeRailWidth`'s narrow spelling of 48 with
    /// the inset below to spare.
    static let hourLabelSize: CGFloat = 11

    /// Between an hour label and the rail's closing hairline. The narrow rail is the one with no
    /// slack in it and it already used 8; the wide rail loses nothing by matching, since the label
    /// is right-aligned and the inset is measured from the same edge either way.
    static let hourLabelTrailingInset: CGFloat = 8

    // MARK: The day header band

    /// `MON` over a day column — the same label the month grid sets over its own columns, at the
    /// same 11pt. That agreement is the reason for the number: the two calendar surfaces name a
    /// weekday for the same purpose, and the month grid has never asked the device.
    static let weekdaySize: CGFloat = 11

    /// The day number, and the circle that fills behind it on today.
    ///
    /// 18-in-32 rather than 20-in-36. Neither was forced by room — a day column is at least
    /// `CadenceCalendarWeekGridLayout.preferredDayColumnWidth`, 104pt, at *both* widths — so the tie
    /// is broken by what the band is for: the number names the day, and the strip of chips under it
    /// previews the day. The larger circle was taking its extra 4pt straight out of that preview,
    /// which was already overflowing its stated minimum (see `dayHeaderHeight`).
    static let dayNumberSize: CGFloat = 18
    static let dayCircleSize: CGFloat = 32

    /// Between the weekday label and the day number.
    static let dayLabelSpacing: CGFloat = 3

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

// MARK: - The toolbar

/// The calendar's top row: the date title that is also the date control, and the presentation
/// switch.
///
/// This row **is** a page header — it leads with the feature's identity tile and the page's title —
/// so its gutter, its row spacing and its tile are `CadencePageHeaderMetrics`' rather than a fourth
/// private spelling of them. It had one: a 34/15 icon tile, which is exactly the drift
/// `CadencePageHeaderMetrics.iconSize` was written to stop, and it drew that tile on iPad only, so the
/// one page in the app whose header changed identity depending on the device was this one.
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
