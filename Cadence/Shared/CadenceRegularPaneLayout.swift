import CoreGraphics

/// How a regular-width pane divides between a list column and the detail beside it.
///
/// Every split feature surface on iPad — Goals, Habits, Focus, Lists — declared its own geometry,
/// and three of the four declared a `minWidth`/`idealWidth` with **no maximum**. An `HStack` given
/// two flexible children splits the difference, so on a 13" iPad in portrait (844pt of pane after
/// the 188pt sidebar) the Goals list column took 422pt to draw one-line rows while the detail beside
/// it wrapped "Ship Cadence on iPad" onto two lines. The list column is a chooser; the detail is the
/// thing being read. The proportion should reflect that at every width, and the maximum is what
/// makes it.
///
/// The rule is the one `CadenceTodayLayoutSupport` settled on: a floor is a preference, and what is
/// actually available is the guarantee. `listPaneWidth(forPaneWidth:)` therefore ends by clamping to
/// half the pane — below about 790pt the fraction has already fallen under the 300pt floor, and
/// without that last clamp a "minimum" would start taking *more* than half of a narrow pane, which
/// is the same shape as the bug that made an 11" iPad split 632pt into 312 and 320.
enum CadenceRegularSplitLayout {
    /// The least a list column can be and still show an icon, a two-line row and a count badge.
    static let listPaneMinWidth: CGFloat = 300
    /// Past this a wider pane is better spent on the detail. `iOSListsView` already declared it;
    /// Goals, Habits and Focus did not, which is what let them take half of a 13" pane.
    static let listPaneMaxWidth: CGFloat = 380
    /// The share of the pane the list column asks for between those two bounds. Chosen so that a
    /// 13" iPad in portrait lands on 338 — within a couple of points of the 340 `idealWidth`
    /// `iOSListsView` had already settled on by hand, so the one surface that was **not** broken
    /// keeps the proportion it had.
    static let listPaneFraction: CGFloat = 0.40
    static let paneDividerWidth: CGFloat = 1

    static func listPaneWidth(forPaneWidth paneWidth: CGFloat) -> CGFloat {
        guard paneWidth > 0 else { return listPaneMinWidth }
        let preferred = min(max(paneWidth * listPaneFraction, listPaneMinWidth), listPaneMaxWidth)
        // Never more than the detail beside it. This is the guarantee; `preferred` is the wish.
        return min(preferred, (paneWidth - paneDividerWidth) / 2)
    }
}

/// The Week timeline's own width arithmetic: an hour rail, then one column per day, with all seven
/// of them on screen at once.
///
/// `iOSCalendarTimelineGrid` computed this inline as
/// `max(dates.count <= 7 ? available / count : 126, isRegular ? 112 : 104)` — a floor treated as a
/// guarantee, the same shape as the two bugs below, and the one that survived them. That `max`
/// means the grid needs `58 + 7 × 112 = 842pt` before a week fits without a horizontal scroller,
/// and no iPad pane is that wide once the day inspector has taken its 340: an 11" Pro in landscape
/// is 1022 and keeps 682, a 13" in portrait is 844 and keeps 503. So Week ran behind a scroller
/// showing roughly six of seven days on the primary target and four and a half on a 13" — the
/// seventh day off the right edge of the one view whose entire subject is the week. It starved
/// *below* the split too: an 11" in portrait gives the grid its whole 632pt pane and 632 is still
/// short of 842, so removing the inspector there had taken it from two visible days to five, not
/// to seven.
///
/// The inversion is the one the rest of this file already made: **seven columns on screen is the
/// guarantee and 112pt is the wish.** A pane that cannot pay for seven full-width columns gets
/// seven narrower ones rather than five and a scrollbar, down to `minimumDayColumnWidth`.
///
/// Compression alone was not enough, though, and the reason is worth keeping: at a 13" iPad's
/// 844pt pane the inspector's 340 leaves 445, which divides into seven columns of 63.6 — over the
/// touch floor, so it *fits*, and every block in it reads `[S…` over `3…`. Seven columns that say
/// nothing are not a week either. So `fullSizeWidth` is what
/// `CadenceCalendarPaneLayout.showsInspector(paneWidth:calendarMinimumWidth:)` gates on: the
/// inspector may only have space the week does not need to draw itself at full size. Compression is
/// for panes that are simply small, where the alternative is not a narrower inspector but a missing
/// day.
enum CadenceCalendarWeekGridLayout {
    static let daysInWeek = 7

    /// The hour rail down the left of the canvas, as `iOSCalendarTimelineGrid` already had it.
    static func timeRailWidth(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 58 : 48
    }

    /// What a day column asks for when the pane can pay for it — wide enough for a block to label
    /// itself with a title *and* a time range. This is the number that used to be spelled `max(…)`.
    static func preferredDayColumnWidth(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 112 : 104
    }

    /// A timeline block is inset this far from each edge of its column — `colWidth - 18` in
    /// `iOSCalendarTimelineDayColumn`, at `x: 9`.
    static let blockHorizontalInset: CGFloat = 9
    /// The floor any control has to clear to stay usable.
    static let minimumTouchTarget: CGFloat = 44

    /// The least a day column can be. Derived, not picked: a column's widest hard requirement is
    /// that the block drawn inside it stays tappable, and that block is inset by
    /// `blockHorizontalInset` on both sides. Below this a column stops being *usable* rather than
    /// merely tight, so there is nothing left to buy by compressing further and the grid scrolls
    /// instead. The narrowest iPad pane, 632pt of 11" portrait, lands at 82 — comfortably clear.
    static var minimumDayColumnWidth: CGFloat {
        minimumTouchTarget + blockHorizontalInset * 2
    }

    /// A span longer than a week scrolls by design: fourteen columns cannot be a fortnight and a
    /// legible day at the same time on any iPad. `.twoWeeks` is not in `pickerCases`, so this is
    /// only reachable from a value persisted by an older build.
    static let multiWeekDayColumnWidth: CGFloat = 126

    /// The width at which every day column is the size it asks for — the rail plus seven columns at
    /// `preferredDayColumnWidth`. 842pt at regular width.
    ///
    /// This is what the grid claims before an inspector may take anything, so it is the number that
    /// decides where Week splits: 842 + 340 + 1 = 1183pt of pane. On the target iPad in landscape
    /// that is reached with the shell sidebar **folded** (1210pt of pane — seven 112.6pt columns
    /// *and* an inspector) and not with it out (1022pt, which gives the week the whole pane at
    /// 137.7pt a column). Either way the week is legible, which is the trade this makes and the
    /// reason the gate is stated as "the inspector may only have space the week does not need".
    static func fullSizeWidth(isRegularWidth: Bool) -> CGFloat {
        timeRailWidth(isRegularWidth: isRegularWidth)
            + preferredDayColumnWidth(isRegularWidth: isRegularWidth) * CGFloat(daysInWeek)
    }

    /// The width of one day column in `availableWidth` (the grid less its hour rail).
    ///
    /// Wider than the preference where there is room — a week is meant to fill its pane — and
    /// narrower where there is not, down to `minimumDayColumnWidth`. Under that there is nothing to
    /// be gained by shrinking further, so the grid falls back to the preferred width and scrolls,
    /// which is what a phone does and has always done: 393pt of iPhone leaves 49pt a column.
    ///
    /// **`dayCount` is how many columns are meant to be *visible*, not how many exist.** It used to
    /// be `dates.count`, which was the same number only because the grid rendered exactly one week
    /// and stopped. The grid now scrolls through hundreds of columns
    /// (`CadenceCalendarTimelineWindow`), so a column width divided by the number of columns in
    /// existence would come out at a fraction of a point. Dividing by the *visible* count is what
    /// makes the width fixed — the pane decides how many columns fit, not how many there are — and
    /// it is also what keeps `545f429`'s guarantee true: at `visibleDayCount(for: .week)` the
    /// arithmetic is "seven columns fill the pane exactly", so seven is what is on screen at every
    /// width, with the rest a scroll away.
    static func dayColumnWidth(
        availableWidth: CGFloat,
        dayCount: Int,
        isRegularWidth: Bool
    ) -> CGFloat {
        let preferred = preferredDayColumnWidth(isRegularWidth: isRegularWidth)
        guard dayCount > 0 else { return preferred }
        guard dayCount <= daysInWeek else { return max(multiWeekDayColumnWidth, preferred) }
        let fitted = availableWidth / CGFloat(dayCount)
        return fitted >= minimumDayColumnWidth ? fitted : preferred
    }

    /// How many day columns a view mode wants on screen at once.
    ///
    /// This is the whole of what a timed view mode means now. It used to also decide which days
    /// existed — Week built seven `Date`s and the chevrons rebuilt them a week at a time — and with
    /// the grid scrolling through a wide window that half of the job is gone.
    static func visibleDayCount(for viewMode: CadenceCalendarViewMode) -> Int {
        switch viewMode {
        case .week:     return daysInWeek
        case .twoWeeks: return daysInWeek * 2
        // Month does not use the timed grid at all; it has its own. Answering with a week keeps
        // this total rather than trapping, and nothing reaches it.
        case .month:    return daysInWeek
        }
    }

    /// How many whole columns of `columnWidth` fit in `availableWidth`.
    ///
    /// The restated form of the seven-column guarantee: `545f429` fixed a Week that put four and a
    /// half of its seven days behind a scroller, and with an infinitely scrolling grid the way to
    /// state that is no longer "the content is not wider than the pane" — the content is always
    /// wider than the pane now — but "at least this many columns are on screen".
    static func visibleColumnCount(availableWidth: CGFloat, columnWidth: CGFloat) -> Int {
        guard columnWidth > 0, availableWidth > 0 else { return 0 }
        // A hair of tolerance, because the fitted width is `available / 7` and floating point can
        // land the seventh column a ten-thousandth of a point over the edge.
        return Int(((availableWidth + 0.01) / columnWidth).rounded(.down))
    }
}

/// How the Calendar pane divides between the calendar itself and the day inspector.
///
/// `iOSCalendarView.regularInspectorWidth(for:)` was `min(max(width * 0.30, 340), 430)` — a floor
/// treated as a guarantee, and the same mistake `CadenceTodayLayoutSupport.taskPaneWidth` (then
/// spelled on `iPadTodayView`) was carrying.
/// On an 11" iPad in portrait the pane is 632pt: 30% of it is 190, the `max` raised that to 340, and
/// the inspector took **54% of the pane** away from the surface it annotates. What was left ran the
/// week grid at its 112pt minimum column width behind a horizontal scroller, so a week view showed
/// two of its seven days.
///
/// The inspector is a companion to the calendar, so the rule is simply that it never takes more than
/// the calendar does, and that below the width where two panes each clear its own minimum there is
/// no inspector at all — the calendar takes the pane, exactly as it does on a phone. The floor is
/// derived from the minimum rather than picked, so the two cannot drift apart.
enum CadenceCalendarPaneLayout {
    /// The least the day inspector will accept before its own rows start clipping. This was already
    /// the `max(...)` floor in `regularInspectorWidth(for:)`; it is a gate now instead of a promise.
    static let inspectorMinWidth: CGFloat = 340
    /// There is no maximum. `min(…, 430)` used to close this expression, and it needed 1434pt of
    /// pane to bind — 430 is 30% of 1433 — where the widest pane a target device produces is 1210:
    /// an 11" Pro in landscape with the shell sidebar folded. What actually bounds the inspector at
    /// every reachable width is the second clamp in `inspectorWidth`, which is what the calendar
    /// beside it needs.
    static let inspectorFraction: CGFloat = 0.30
    static let paneDividerWidth: CGFloat = 1

    /// 681pt of pane, for a calendar that states no minimum of its own. A 13" iPad in portrait
    /// (844pt) keeps the inspector at exactly the width it had before; an 11" in portrait (632pt)
    /// gives the whole pane to the calendar.
    static var splitMinimumWidth: CGFloat {
        inspectorMinWidth * 2 + paneDividerWidth
    }

    /// The inspector's share of the pane — never more than what is left once the calendar has taken
    /// the width it needs to draw itself.
    ///
    /// `calendarMinimumWidth` defaults to `inspectorMinWidth`, which is the stand-in the original
    /// `min(preferred, (paneWidth - paneDividerWidth) / 2)` amounted to: absent a real number from
    /// the surface being annotated, "at least as much as the thing annotating it" is the honest
    /// guess, and it is still the one Month's grid uses, which flexes. Week is the case where the
    /// guess was short by 500pt — see `CadenceCalendarWeekGridLayout`. At the default this returns
    /// exactly what it always did at every pane width where `showsInspector` is true.
    ///
    /// The Board no longer asks: its day columns each carry their own date header and their own
    /// items, so an inspector beside them restated a column already on screen. It takes the pane.
    ///
    /// Only meaningful where `showsInspector(paneWidth:calendarMinimumWidth:)` is true.
    static func inspectorWidth(
        forPaneWidth paneWidth: CGFloat,
        calendarMinimumWidth: CGFloat = inspectorMinWidth
    ) -> CGFloat {
        let preferred = max(paneWidth * inspectorFraction, inspectorMinWidth)
        return min(preferred, paneWidth - paneDividerWidth - calendarMinimumWidth)
    }

    /// What the calendar keeps when the inspector sits beside it.
    static func calendarWidth(
        forPaneWidth paneWidth: CGFloat,
        calendarMinimumWidth: CGFloat = inspectorMinWidth
    ) -> CGFloat {
        paneWidth - paneDividerWidth
            - inspectorWidth(forPaneWidth: paneWidth, calendarMinimumWidth: calendarMinimumWidth)
    }

    /// Whether both sides clear their own minimum — which is what this type always claimed to check
    /// and, until Week supplied a minimum, never did on the calendar's side.
    static func showsInspector(
        paneWidth: CGFloat,
        calendarMinimumWidth: CGFloat = inspectorMinWidth
    ) -> Bool {
        inspectorWidth(forPaneWidth: paneWidth, calendarMinimumWidth: calendarMinimumWidth)
            >= inspectorMinWidth
    }

    /// Whether the Calendar page draws the day inspector as a column beside the calendar.
    ///
    /// **Timeline only.** The Board is a row of day columns, each already headed with its own date
    /// and each already listing that day's items; an inspector beside it spent 340pt restating a
    /// column that was on screen a finger's width away, and cost the board a column and a half of
    /// the days it exists to show. The Board takes the whole pane.
    ///
    /// **Month is not routed through here.** It has two readings and two placements of its own and
    /// asks `CadenceCalendarMonthLayout` instead. Week supplies a `calendarMinimumWidth` that puts
    /// its split at 1183pt, which the target iPad reaches only in landscape with the shell sidebar
    /// folded — so `Day` is where the inspector usually lives.
    static func showsDayInspector(
        isCompact: Bool,
        presentation: CadenceCalendarPresentation,
        viewMode: CadenceCalendarViewMode,
        paneWidth: CGFloat
    ) -> Bool {
        guard !isCompact, presentation == .timeline, viewMode != .month else { return false }
        return showsInspector(
            paneWidth: paneWidth,
            calendarMinimumWidth: calendarMinimumWidth(for: viewMode)
        )
    }

    /// Whether the Calendar page carries the one-line day summary band under its toolbar.
    ///
    /// **Never on the Board.** The Board is a row of day columns; the leading one is the selected
    /// day, and it already carries that date in its own header, its own count badge, and every item
    /// the band would be counting, listed individually a finger's width below. With the day
    /// inspector gone (`42de745`) the band became a full-width strip reading "Wednesday, August 19"
    /// directly above a column headed `WED · AUG 19` — and on an empty day the date was the only
    /// thing left in it, because `CadenceCalendarDaySummary.line` returns nil at zero. The counts do
    /// not earn the band on their own either: they are a finer breakdown of one column's badge, over
    /// the column that spells the same items out.
    ///
    /// Week and 2 Weeks keep it. There the band is the only place the *selected* day is named or
    /// counted at all — a grid of seven columns says which days exist, not which one you are on.
    ///
    /// Month asks `CadenceCalendarMonthLayout`, which has two readings and two placements to weigh.
    ///
    /// There is no `isCompact` here any more. It used to carry the Board's exclusion — the rule read
    /// `!isCompact || presentation == .timeline`, which is "no strip on a compact Board" — and once
    /// the Board is excluded at every width the size class decides nothing left. A parameter no
    /// input can change the answer through is a parameter a test cannot kill.
    static func showsDaySummaryStrip(
        presentation: CadenceCalendarPresentation,
        viewMode: CadenceCalendarViewMode,
        monthPlacement: CadenceCalendarMonthLayout.Placement,
        monthDetail: CadenceCalendarMonthDetail
    ) -> Bool {
        guard presentation != .board else { return false }
        guard viewMode != .month else {
            return CadenceCalendarMonthLayout.showsDaySummaryStrip(
                placement: monthPlacement,
                detail: monthDetail
            )
        }
        return true
    }

    /// What has to fit beside the inspector before there is one.
    ///
    /// Week is the mode that can answer this with a real number: an hour rail and seven day columns,
    /// none of which can be dropped, at the width a column needs to label a block with more than an
    /// ellipsis. The only other mode that reaches it is `.twoWeeks`, whose fourteen columns scroll
    /// by design and which the picker no longer offers, so it keeps the inspector's own width — the
    /// stand-in every mode used to use.
    static func calendarMinimumWidth(for viewMode: CadenceCalendarViewMode) -> CGFloat {
        viewMode == .week
            ? CadenceCalendarWeekGridLayout.fullSizeWidth(isRegularWidth: true)
            : inspectorMinWidth
    }
}
