import CoreGraphics
import Foundation

/// The logic behind the compact **Month** view: a month grid on top, a live agenda underneath.
///
/// Month was the last calendar mode still carrying the shared chrome block `ecaf80f` removed from
/// Week and Board — the four "0 total / 0 timed / 0 tasks / 0 events" chips, the selected-day card,
/// and the oversized empty state. It was left deliberately: the grid alone lists nothing, so
/// stripping the inspector without building an agenda first would have left a month you could look
/// at but not read. This type is that agenda's half of the work — which days it lists, what each
/// day's heading says, how tall the grid may grow, and the two rules that keep tapping a grid day
/// and scrolling the agenda from driving each other in a loop.
///
/// It lives in `Shared/` rather than beside the view because `Cadence/iOS/` is inside
/// `#if os(iOS)` and invisible to the macOS-built `CadenceTests`.
enum CadenceCalendarMonthAgendaSupport {

    // MARK: - Which days the agenda lists

    /// The days the agenda **considers**, in order: exactly the days the grid draws.
    ///
    /// Not the calendar month — the grid pads out to whole weeks, so its leading and trailing
    /// cells belong to the neighbouring months and still need somewhere to jump to. This is the
    /// candidate list; what the agenda actually *draws* is this list minus the quiet days, and the
    /// difference is `nearestListedDayKey`'s whole reason to exist.
    static func agendaDays(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> [Date] {
        CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar)
    }

    static func agendaDayKeys(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> [String] {
        agendaDays(forMonthContaining: monthDate, calendar: calendar).map {
            DateFormatters.dateKey(from: $0, calendar: calendar)
        }
    }

    // MARK: - Quiet days

    /// The section a tap on `dayKey` resolves to, given the days the agenda actually lists.
    ///
    /// A quiet day draws nothing at all now, so most of the grid's cells have no section of their
    /// own — and `.scrollPosition(id:)` drops a scroll to an id the stack does not contain,
    /// silently, leaving the lit cell and the parked agenda pointing at different days with no
    /// gesture that reconciles them. That is the same failure `scrollTarget`'s containment guard
    /// catches; this is what turns "no section" from a dead tap into a live one.
    ///
    /// **Forward first.** A tap on a quiet day is a question about what is happening around it, and
    /// the next thing on the calendar is the more useful answer than the last one — the agenda
    /// reads forward, so landing before what you asked about would scroll away from it. The
    /// preceding day is the fallback for a tap after the last populated day, where there is no
    /// following one; `nil` only for a month holding nothing at all, which draws no scroll view.
    ///
    /// `listedDayKeys` must be ascending, which `yyyy-MM-dd` keys are lexicographically — that is
    /// the whole reason this repo stores dates that way.
    static func nearestListedDayKey(to dayKey: String, listedDayKeys: [String]) -> String? {
        guard !listedDayKeys.isEmpty else { return nil }
        return listedDayKeys.first { $0 >= dayKey } ?? listedDayKeys.last
    }

    /// What a **selection change** does to the agenda once quiet days draw nothing: resolve the day
    /// to a section that exists, then apply the ordinary loop guard.
    ///
    /// One function rather than two steps at the call site, because the two steps compose in an
    /// order that matters — resolving after the guard would compare a key against a list it is not
    /// in and always answer `nil`, which is the dead tap this exists to remove.
    static func scrollTarget(
        forSelectedDay dayKey: String,
        scrolledKey: String?,
        listedDayKeys: [String]
    ) -> String? {
        guard let resolved = nearestListedDayKey(to: dayKey, listedDayKeys: listedDayKeys) else { return nil }
        return scrollTarget(selectedKey: resolved, scrolledKey: scrolledKey, agendaDayKeys: listedDayKeys)
    }

    /// The section the agenda **opens** on, resolved the same way.
    static func initialScrollTarget(forSelectedDay dayKey: String, listedDayKeys: [String]) -> String? {
        guard let resolved = nearestListedDayKey(to: dayKey, listedDayKeys: listedDayKeys) else { return nil }
        return initialScrollTarget(selectedKey: resolved, agendaDayKeys: listedDayKeys)
    }

    /// A day section's heading — `Sat · Aug 15`, which the shared board column header uppercases to
    /// `SAT · AUG 15`. Same shape as a Calendar Board day column's heading, because it is the same
    /// thing: the label over one day's items.
    static func dayHeaderLabel(for date: Date) -> String {
        "\(DateFormatters.dayOfWeek.string(from: date)) · \(DateFormatters.shortDate.string(from: date))"
    }

    // MARK: - Two-way selection sync

    /// The section the agenda **opens** on.
    ///
    /// The selected day, but only where the agenda actually lists it. `.scrollPosition(id:)` drops a
    /// scroll to an id that is not in the stack, and a dropped scroll leaves the grid lit on one day
    /// and the agenda parked on another with no gesture that reconciles them — the same failure
    /// `scrollTarget` guards for a *later* selection, which the opening position had no equivalent
    /// of. A selection outside this month opens on the month's first listed day instead.
    ///
    /// `nil` only for a month with no days at all, which no calendar produces.
    static func initialScrollTarget(selectedKey: String, agendaDayKeys: [String]) -> String? {
        agendaDayKeys.contains(selectedKey) ? selectedKey : agendaDayKeys.first
    }

    /// The agenda section a **selection change** should scroll to, or `nil` to leave the agenda
    /// where it is.
    ///
    /// `nil` in the two cases that would otherwise close the loop between the grid and the agenda:
    /// the agenda already sits at that section — which is what a selection arriving *from* a scroll
    /// looks like, so re-issuing the scroll would fight the finger — and a day the agenda does not
    /// list, where the scroll would be dropped on the floor and leave the two out of step with no
    /// way back.
    static func scrollTarget(selectedKey: String, scrolledKey: String?, agendaDayKeys: [String]) -> String? {
        guard scrolledKey != selectedKey else { return nil }
        guard agendaDayKeys.contains(selectedKey) else { return nil }
        return selectedKey
    }

    /// The day a **scrolled-to section** should select, or `nil` to leave the selection alone.
    ///
    /// The mirror of `scrollTarget`: a scroll that lands back on the already-selected day — which is
    /// what the scroll *caused by* a grid tap settles into — changes nothing, so the tap does not
    /// bounce back through the selection a second time.
    static func selectionTarget(scrolledKey: String?, selectedKey: String) -> String? {
        guard let scrolledKey, scrolledKey != selectedKey else { return nil }
        return scrolledKey
    }

    // MARK: - Grid geometry

    /// How many week rows the grid draws for this month — 4, 5 or 6 depending on where the first of
    /// the month falls.
    static func weekRowCount(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> Int {
        let days = agendaDays(forMonthContaining: monthDate, calendar: calendar).count
        return max(0, days / 7)
    }

    /// The least the detail under the grid is left with, whatever the grid would like — a heading
    /// and the top of the first row under it. The detail is the half of this view that lists
    /// anything.
    ///
    /// It is one number for both readings. The day inspector used to reserve 168 because it opened
    /// with a fixed 63pt bar carrying the date and an add button; that bar is gone, so the inspector
    /// now opens on its first section heading — the same shape the agenda opens on, and the same
    /// claim. Leaving 168 behind would have had the grid buy the detail 72pt it no longer needs out
    /// of its own cell height, on the one view whose subject is a whole month of cells.
    static let agendaMinimumHeight: CGFloat = 96

    /// The height of one week row, so that **every** week of the month is on screen at once — and so
    /// that the agenda under it is on screen *at all*.
    ///
    /// The compact month used to give the grid the bottom ~40% of a pane it shared with a day
    /// inspector, at a 104pt minimum cell — three weeks fitted and the rest were below the fold, on
    /// the one view whose entire job is showing a whole month. Rows are sized to a share of the
    /// pane instead, so the row *count* is what the grid honours and the row *height* is what gives.
    ///
    /// The 44pt touch floor is a floor on the grid's **share of the pane**, not a claim against the
    /// pane itself. It used to be applied last and unconditionally, which quietly made it outrank
    /// the agenda: at six rows the grid asked for `weekdayHeader + 6 × 44 + padding` — 294pt — no
    /// matter how little there was, its `VStack` gave the fixed-height grid what it asked for, and
    /// the agenda's `ScrollView`, the flexible sibling, got whatever remained. On a pane shorter
    /// than ~390pt that remainder is nothing, and a zero-height scroll view is not an empty list:
    /// it is a pane that draws its grid and then shows no day headings, no rows, and no scroll in
    /// either direction that brings any back, because there is nowhere for them to be. So the grid
    /// is capped at `availableHeight - agendaMinimumHeight` first and the touch floor applies inside
    /// that cap. Every pane that can hold both still gets its 44pt cells; a pane that cannot hold
    /// both gives up cell height rather than giving up the agenda.
    static func gridRowHeight(
        availableHeight: CGFloat,
        rowCount: Int,
        weekdayHeaderHeight: CGFloat,
        gridBottomPadding: CGFloat = 8,
        agendaMinimumHeight: CGFloat = Self.agendaMinimumHeight,
        gridHeightFraction: CGFloat = 0.46,
        minimumRowHeight: CGFloat = 44,
        maximumRowHeight: CGFloat = 58
    ) -> CGFloat {
        guard rowCount > 0 else { return minimumRowHeight }
        let fraction = min(max(gridHeightFraction, 0), 1)
        let preferred = max(0, availableHeight * fraction - weekdayHeaderHeight) / CGFloat(rowCount)
        let ceiling = max(
            0,
            availableHeight - agendaMinimumHeight - weekdayHeaderHeight - gridBottomPadding
        ) / CGFloat(rowCount)
        let floor = min(minimumRowHeight, ceiling)
        return min(max(min(preferred, ceiling), floor), max(floor, maximumRowHeight))
    }
}

// MARK: - Which reading of the month, and where it goes

/// The two ways Month can say what is on a day, as a **choice** rather than a consequence of how
/// wide the window happens to be.
///
/// Both already existed. Which one you got was decided by `hasInspector`, i.e. by the pane clearing
/// 681pt: an 11" iPad in portrait showed the agenda and the same iPad in landscape showed the day
/// inspector, so rotating the device silently swapped the mechanism — two different answers to
/// "what is on the 14th", neither reachable from the other.
enum CadenceCalendarMonthDetail: String, CaseIterable, Hashable {
    /// Every day of the month in sequence, scrolling, two-way synced with the grid.
    case agenda
    /// The selected day on its own, in sections: blocks, Apple Calendar, timed, do date, due.
    case day

    var title: String {
        switch self {
        case .agenda: return "Agenda"
        case .day: return "Day"
        }
    }

    var systemImage: String {
        switch self {
        case .agenda: return "list.bullet"
        case .day: return "calendar.day.timeline.left"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .agenda: return "List every day of the month"
        case .day: return "Show only the selected day"
        }
    }
}

/// Month's two axes: the **toggle** picks what is shown beside or under the grid, and the pane
/// width picks which of those two it is.
///
/// Keeping them apart is the whole point. The stored preference is written from a tap and from
/// nothing else — a persisted value written from a measured one compounds across launches, which
/// `ecaf80f` had already paid for once — while placement is derived every layout pass and never
/// stored.
enum CadenceCalendarMonthLayout {
    /// Where the chosen detail sits relative to the month grid.
    ///
    /// `nonisolated` so its synthesized `Equatable` is too: this project builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which otherwise makes comparing two placements
    /// from a `nonisolated` context — a test, say — a Swift 6 error.
    nonisolated enum Placement: Hashable {
        /// A column beside the grid. What a landscape iPad already did with the day inspector.
        case beside
        /// A pane under the grid. What a phone, and a narrow iPad pane, already did with the agenda.
        case below
    }

    /// What a compact pane shows whatever is stored. The phone's Month has one shape and no toggle,
    /// so the stored value is a regular-width preference that a phone neither reads nor writes.
    static let compactDetail: CadenceCalendarMonthDetail = .agenda

    /// The agenda is the default because it is the reading that actually lists the month, and
    /// because it is what every phone shows — so a cold launch looks the same on all of them.
    static let defaultDetail: CadenceCalendarMonthDetail = .agenda

    static func detail(storedRawValue: String, isCompact: Bool = false) -> CadenceCalendarMonthDetail {
        guard !isCompact else { return compactDetail }
        return CadenceCalendarMonthDetail(rawValue: storedRawValue) ?? defaultDetail
    }

    /// Beside the grid exactly where a 340pt side column fits — 681pt of pane, the width
    /// `CadenceCalendarPaneLayout` has always split at. Below that the detail goes under the grid
    /// instead of disappearing: the inspector's 340pt floor against a 646pt pane would leave ~43pt
    /// per weekday column, which is the starvation `CadenceCalendarPaneLayout` exists to prevent.
    ///
    /// Month is now the only surface that splits at this width. Week claims the whole grid before an
    /// inspector may take anything and so splits at 1183, and the Board does not split at all.
    static func placement(paneWidth: CGFloat) -> Placement {
        CadenceCalendarPaneLayout.showsInspector(paneWidth: paneWidth) ? .beside : .below
    }

    /// Month-only, regular-width-only. Week and Board have one detail each and would gain a control
    /// with nothing to switch between; a phone has no room to place either one beside the grid.
    static func showsDetailControl(
        isCompact: Bool,
        presentation: CadenceCalendarPresentation,
        viewMode: CadenceCalendarViewMode
    ) -> Bool {
        !isCompact && presentation == .timeline && viewMode == .month
    }

    // Month has no day-summary strip in any placement or reading, and neither does any other
    // calendar surface — the band and the gate that placed it are both gone. The note on why is in
    // `CadenceRegularPaneLayout.swift`, where the gate used to be.
}

// MARK: - Month grid: the week rows it scrolls through

/// The week rows a month grid renders, and how a **vertical** scroll position maps to a date.
///
/// Month was the last calendar surface that stepped rather than scrolled: a fixed 4/5/6-row grid of
/// one month, rebuilt by the toolbar's `‹ ›`. This is the same trade the timed grids made in
/// `cf785a8`, turned ninety degrees — a wide run of week rows with the anchor near its middle,
/// recentred when a scroll approaches either end, and the **top** row reported back so the toolbar's
/// date title can name the month you are looking at.
///
/// The row axis is weeks rather than days because that is the unit a month grid is built from: seven
/// day cells across, one week per row. Scrolling by anything finer would put a row of a week
/// half-off the top edge with its day numbers clipped.
enum CadenceCalendarMonthWindow {
    /// Week rows rendered at once — eight years either way, the same span as the day windows the
    /// Board and the timed grids scroll through, and windowed by hand the same way.
    static let renderRowCount = CalendarBoardPlannerSupport.plannerRenderDayCount
    static let leadingRowCount = renderRowCount / 2
    static let daysPerRow = 7

    /// How many week rows a month grid shows at once.
    ///
    /// Fixed at six, which is the most any month needs. It used to be
    /// `CadenceCalendarMonthAgendaSupport.weekRowCount(forMonthContaining:)` — 4, 5 or 6 for the
    /// month on screen — and the compact grid divided its share of the pane by it. With one month on
    /// screen at a time that was right; with the rows scrolling continuously it means the row height
    /// changes as you scroll from a five-week month into a six-week one, so the grid jumps under the
    /// finger. Six rows always is the height that never moves.
    static let visibleRowCount = 6

    /// The first week row rendered: half the window above the anchor's own week.
    static func windowStart(for anchorDate: Date, calendar: Calendar = .current) -> Date {
        let weekStart = CadenceScheduleSupport.startOfWeek(containing: anchorDate, calendar: calendar)
        return calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -leadingRowCount * daysPerRow, to: weekStart) ?? weekStart
        )
    }

    static func date(at index: Int, windowStart: Date, calendar: Calendar = .current) -> Date {
        let clamped = min(max(index, 0), max(0, renderRowCount - 1))
        return calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: clamped * daysPerRow, to: windowStart) ?? windowStart
        )
    }

    static func index(for date: Date, windowStart: Date, calendar: Calendar = .current) -> Int {
        let weekStart = CadenceScheduleSupport.startOfWeek(containing: date, calendar: calendar)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: windowStart),
            to: weekStart
        ).day ?? 0
        return min(max(days, 0) / daysPerRow, max(0, renderRowCount - 1))
    }

    /// The week row a month grid should **open** on when Month is entered on `date`: the first row of
    /// that day's month grid, so the six visible rows are that month rather than a window straddling
    /// two.
    static func topRow(forMonthContaining date: Date, calendar: Calendar = .current) -> Date {
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start else {
            return CadenceScheduleSupport.startOfWeek(containing: date, calendar: calendar)
        }
        return CadenceScheduleSupport.startOfWeek(containing: monthStart, calendar: calendar)
    }

    /// The month a window of `visibleRowCount` rows starting at `topRowStart` is *showing*.
    ///
    /// Not the top row's own month: a six-row window aligned to August starts on the week containing
    /// July 27, so naming the top row would print "July" over a grid that is plainly August. The
    /// middle of the window is the reading that agrees with what is on screen, and it changes over
    /// at the point where half the rows have become the next month.
    static func displayedMonth(
        topRowStart: Date,
        visibleRowCount: Int = visibleRowCount,
        calendar: Calendar = .current
    ) -> Date {
        let rows = max(1, visibleRowCount)
        let middle = (rows * daysPerRow) / 2
        return calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: middle, to: topRowStart) ?? topRowStart
        )
    }

    // MARK: Recentring, and when it is allowed to happen

    /// Whether the window is owed a recentre, and whether **now** is the moment to perform one.
    ///
    /// Recentring is the most expensive thing this grid does: it reassigns `windowStart`, which
    /// re-dates every row in the lazy stack, and then writes the scroll position to the row's new
    /// index. Both of those inside a scroll callback means SwiftUI relaying out the whole stack and
    /// having its scroll position reassigned underneath live momentum — a visible hitch, on the one
    /// gesture where a dropped frame reads as the app stalling.
    ///
    /// So it waits. **`isScrolling` is a signal, not a delay** — it is `ScrollPhase.isScrolling`,
    /// which the scroll view reports, and the settle that follows is the scroll view saying it has
    /// stopped rather than a timer guessing that it has. `ecaf80f` had already paid for the guess:
    /// a 0.08s guard expired before the settle arrived and wrote a garbage day into persisted
    /// state. `CadenceLazyScrollAnchor` is emphatic about this and it applies here unchanged.
    ///
    /// Waiting is only safe while there is runway. Inside `hardEdgeRowCount` of either end of the
    /// rendered run the scroll is about to hit the end of the content and stop dead at a date the
    /// user did not choose to stop at — the failure mode of deferring forever — so there the
    /// recentre happens mid-gesture and a hitch is the better of the two.
    ///
    /// Note the ordering: `.none` outranks everything, so a grid resting in the middle of its
    /// window — where every ordinary fling lives, the soft threshold being 168 rows away — never
    /// reaches either of the other two cases at all.
    nonisolated enum RecenterTiming: Equatable {
        /// The window is fine where it is.
        case none
        /// Owed, but the scroll is live and there is runway. Perform it when the scroll settles.
        case whenScrollSettles
        /// Perform it now.
        case now
    }

    /// How close to an end of the rendered run "about to run out" is. Comfortably more than a
    /// single fling can cover from the point the soft threshold first answers true, so the wait is
    /// almost always allowed to end at the settle instead.
    static let hardEdgeRowCount = 8

    static func recenterTiming(
        topIndex: Int,
        isScrolling: Bool,
        renderRowCount: Int = renderRowCount,
        visibleRowCount: Int = visibleRowCount
    ) -> RecenterTiming {
        guard CalendarBoardPlannerSupport.shouldRecenter(
            dayIndex: topIndex,
            renderDays: renderRowCount
        ) else { return .none }
        guard isScrolling else { return .now }
        return isAgainstWindowEdge(
            topIndex: topIndex,
            renderRowCount: renderRowCount,
            visibleRowCount: visibleRowCount
        ) ? .now : .whenScrollSettles
    }

    /// Rows of scrolling left before the run is exhausted, in whichever direction is closer.
    ///
    /// Measured against the *bottom* of the viewport at the trailing end, not the top row: the last
    /// `visibleRowCount` rows cannot become the top row at all, so counting them as runway would
    /// promise a screenful of scrolling that does not exist.
    static func rowsOfRunway(
        topIndex: Int,
        renderRowCount: Int = renderRowCount,
        visibleRowCount: Int = visibleRowCount
    ) -> Int {
        let lastTopRow = max(0, renderRowCount - max(1, visibleRowCount))
        return max(0, min(topIndex, lastTopRow - topIndex))
    }

    static func isAgainstWindowEdge(
        topIndex: Int,
        renderRowCount: Int = renderRowCount,
        visibleRowCount: Int = visibleRowCount
    ) -> Bool {
        rowsOfRunway(
            topIndex: topIndex,
            renderRowCount: renderRowCount,
            visibleRowCount: visibleRowCount
        ) <= hardEdgeRowCount
    }

    /// The window to adopt when the top row nears an end of the rendered run, or `nil` to leave it
    /// alone. Same threshold and the same no-op guard as the Board and the timed grids — without the
    /// guard the grid re-scrolls under a finger that is still moving.
    ///
    /// This answers *whether*; `recenterTiming` answers *when*. Callers ask both.
    static func recenteredWindowStart(
        topIndex: Int,
        topDate: Date,
        currentWindowStart: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard CalendarBoardPlannerSupport.shouldRecenter(
            dayIndex: topIndex,
            renderDays: renderRowCount
        ) else { return nil }
        let recentered = windowStart(for: topDate, calendar: calendar)
        guard !calendar.isDate(recentered, inSameDayAs: currentWindowStart) else { return nil }
        return recentered
    }

    // The grid does **not** convert a scroll offset into a row index by hand. The timed grids do,
    // because their columns sit inside two nested scroll views and a `LazyHStack` there would be
    // driven by whichever of the two SwiftUI decided owned it. This is a single scroll view, so it
    // uses `.scrollPosition(id:)` over a `LazyVStack` — the Board's shape — and `index` / `date(at:)`
    // are all the arithmetic there is.

    // MARK: Event fetching

    /// Days of calendar events a month grid holds at once — twelve weeks, starting three weeks
    /// before the displayed month's own grid.
    ///
    /// The grid renders hundreds of rows and cannot ask EventKit about all of them; it also cannot
    /// ask about exactly what is on screen, because the top row changes on every week scrolled past
    /// and each change would re-run the whole fetch mid-gesture. So the window is keyed on the
    /// **displayed month** and is wide enough to cover every top row that can name that month
    /// (roughly `monthStart − 3 weeks` through `monthEnd + 3 weeks`) plus its six visible rows.
    static let eventWindowRowCount = 12
    static let eventWindowLeadRows = 3

    static func eventWindowStart(displayedMonth: Date, calendar: Calendar = .current) -> Date {
        let gridStart = topRow(forMonthContaining: displayedMonth, calendar: calendar)
        return calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -eventWindowLeadRows * daysPerRow, to: gridStart) ?? gridStart
        )
    }

    static func eventWindowDates(displayedMonth: Date, calendar: Calendar = .current) -> [Date] {
        let start = eventWindowStart(displayedMonth: displayedMonth, calendar: calendar)
        return (0..<(eventWindowRowCount * daysPerRow)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
}
