#if os(macOS)
import SwiftUI

enum CalendarMonthGridInteractionSupport {
    /// Settle-delay used after a programmatic `scrollTo` before treating the scroll as
    /// finished, mirroring `CalendarPageStateSupport.restoreTimelineScrollIfNeeded`'s idiom
    /// for the timeline view.
    static let scrollSettleDelay: TimeInterval = 0.12

    /// The scroll's two products: the **block** the header is named from, and the **month the grid
    /// is tinted against**.
    ///
    /// Both come from this one callback on purpose. They are near-identical readings of the same
    /// scroll — the block that fills most of the viewport, and the month the middle of the viewport
    /// falls in — and computing them anywhere apart is how a header and a grid end up naming
    /// different months. `displayedMonth` is `nil` until the grid has placed itself, which is the
    /// caller's cue to fall back to the anchored block's own month.
    ///
    /// `visibleMonthIdx` stays a **block** index and keeps every property `CalendarPageStateSupport`
    /// documents for it — it is still what `handleAppear` scrolls to and what the month → timeline
    /// return path inverts. The displayed month is deliberately *not* derived from it: a block index
    /// cannot say which half of a block you are looking at, which is the whole difference this
    /// change is about.
    static func handleScroll(
        y: CGFloat,
        offsets: [CGFloat],
        totalMonths: Int,
        viewportHeight: CGFloat = 0,
        todayMonthIdx: Int = CalendarMonthGridMetrics.todayMonthIndex,
        currentMonthStart: Date,
        calendar: Calendar,
        visibleMonthIdx: inout Int,
        displayedMonth: inout Date?,
        didInitialPosition: Bool,
        isProgrammaticScroll: Bool
    ) {
        // While a programmatic scroll (initial position restore or a "Today" jump) is in
        // flight, scroll-geometry callbacks reflect the stale pre-jump offset — ignore them
        // so they can't stomp a value that was just set intentionally. The tint is under the same
        // guard as the header: adopting a pre-jump offset there would flash the wrong month across
        // the whole grid for as long as the jump takes.
        guard didInitialPosition, !isProgrammaticScroll else { return }
        let computed = dominantMonthIndex(
            topY: y,
            viewportHeight: viewportHeight,
            offsets: offsets,
            totalMonths: totalMonths
        )
        if visibleMonthIdx != computed {
            visibleMonthIdx = computed
        }

        let month = CalendarMonthGridSupport.displayedMonth(
            topY: y,
            viewportHeight: viewportHeight,
            offsets: offsets,
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            calendar: calendar
        )
        if displayedMonth.map({ !calendar.isDate($0, equalTo: month, toGranularity: .month) }) ?? true {
            displayedMonth = month
        }
    }

    static func handleAppear(
        proxy: ScrollViewProxy,
        visibleMonthIdx: Binding<Int>,
        todayMonthIdx: Int,
        setDidInitialPosition: @escaping (Bool) -> Void,
        setProgrammaticScroll: @escaping (Bool) -> Void
    ) {
        let targetMonthIdx = min(max(visibleMonthIdx.wrappedValue, 0), CalendarMonthGridMetrics.totalMonths - 1)
        setProgrammaticScroll(true)
        DispatchQueue.main.async {
            proxy.scrollTo(CalendarMonthGridIdentifiers.month(targetMonthIdx), anchor: .top)
            // Give the scroll time to actually settle before signaling "initial position
            // done" — a bare nested `.async` fires on the next runloop turn, not once the
            // scroll has visually settled, which is what let the header show a stale month
            // for far jumps (e.g. month 60 -> month 0 when restoring a saved position).
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollSettleDelay) {
                setDidInitialPosition(true)
                setProgrammaticScroll(false)
            }
        }
    }

    /// The two scroll ids a "Today" jump aims at, both keyed by the block that *renders* today.
    ///
    /// This used to key both off today's calendar-month index. For the ~3 days a month that fall
    /// before their month's first Sunday, today's cell is tagged with the *previous* block's
    /// index — so the day id built from the calendar month named no view in the hierarchy,
    /// `scrollTo` dropped it silently, and the month anchor parked the user on a block that does
    /// not contain today. Deriving both ids from `blockIndex(for:)` keeps them pointing at the
    /// same block the grid tagged the cell with.
    static func todayJumpTargets(
        todayKey: String,
        currentMonthStart: Date,
        todayMonthIdx: Int,
        calendar: Calendar
    ) -> (monthID: String, dayID: String) {
        let today = DateFormatters.date(from: todayKey, in: calendar) ?? Date()
        let renderingBlockIdx = blockIndex(
            for: today,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )
        return (
            CalendarMonthGridIdentifiers.month(renderingBlockIdx),
            CalendarMonthGridIdentifiers.day(monthIndex: renderingBlockIdx, dateKey: todayKey)
        )
    }

    static func handleTodayTrigger(
        proxy: ScrollViewProxy,
        todayMonthIdx: Int,
        todayKey: String,
        currentMonthStart: Date,
        calendar: Calendar,
        /// False once a month block is exactly one screen tall — then anchoring the month at
        /// the top already puts every one of its days on screen, and additionally centring
        /// today's row would only drag the viewport across a month boundary and leave the page
        /// showing two half months.
        centersTodayCell: Bool,
        setProgrammaticScroll: @escaping (Bool) -> Void
    ) {
        let targets = todayJumpTargets(
            todayKey: todayKey,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )

        // Guard the scroll so a scroll-geometry callback firing mid-jump can't recompute
        // `visibleMonthIdx` from the stale pre-jump offset and stomp the value the "Today"
        // jump just set.
        setProgrammaticScroll(true)
        proxy.scrollTo(targets.monthID, anchor: .top)

        guard centersTodayCell else {
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollSettleDelay) {
                setProgrammaticScroll(false)
            }
            return
        }

        DispatchQueue.main.async {
            proxy.scrollTo(targets.dayID, anchor: .center)
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollSettleDelay) {
                setProgrammaticScroll(false)
            }
        }
    }

    /// Re-pins the grid to the month the header is naming after the window resizes.
    ///
    /// Row heights are derived from the viewport, so a resize rescales every month block and
    /// the old scroll offset now points somewhere else entirely. Re-anchoring keeps the
    /// on-screen month stable instead of sliding an arbitrary distance.
    static func handleViewportHeightChange(
        proxy: ScrollViewProxy,
        visibleMonthIdx: Int,
        didInitialPosition: Bool,
        setProgrammaticScroll: @escaping (Bool) -> Void
    ) {
        guard didInitialPosition else { return }
        let targetMonthIdx = min(max(visibleMonthIdx, 0), CalendarMonthGridMetrics.totalMonths - 1)
        setProgrammaticScroll(true)
        DispatchQueue.main.async {
            proxy.scrollTo(CalendarMonthGridIdentifiers.month(targetMonthIdx), anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollSettleDelay) {
                setProgrammaticScroll(false)
            }
        }
    }
}
#endif
