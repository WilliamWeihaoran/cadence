#if os(macOS)
import SwiftUI

enum CalendarMonthGridInteractionSupport {
    /// Settle-delay used after a programmatic `scrollTo` before treating the scroll as
    /// finished, mirroring `CalendarPageStateSupport.restoreTimelineScrollIfNeeded`'s idiom
    /// for the timeline view.
    static let scrollSettleDelay: TimeInterval = 0.12

    static func handleScroll(
        y: CGFloat,
        offsets: [CGFloat],
        totalMonths: Int,
        viewportHeight: CGFloat = 0,
        visibleMonthIdx: inout Int,
        didInitialPosition: Bool,
        isProgrammaticScroll: Bool
    ) {
        // While a programmatic scroll (initial position restore or a "Today" jump) is in
        // flight, scroll-geometry callbacks reflect the stale pre-jump offset — ignore them
        // so they can't stomp a value that was just set intentionally.
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

    static func handleTodayTrigger(
        proxy: ScrollViewProxy,
        todayMonthIdx: Int,
        todayKey: String,
        /// False once a month block is exactly one screen tall — then anchoring the month at
        /// the top already puts every one of its days on screen, and additionally centring
        /// today's row would only drag the viewport across a month boundary and leave the page
        /// showing two half months.
        centersTodayCell: Bool,
        setProgrammaticScroll: @escaping (Bool) -> Void
    ) {
        let monthID = CalendarMonthGridIdentifiers.month(todayMonthIdx)

        // Guard the scroll so a scroll-geometry callback firing mid-jump can't recompute
        // `visibleMonthIdx` from the stale pre-jump offset and stomp the value the "Today"
        // jump just set.
        setProgrammaticScroll(true)
        proxy.scrollTo(monthID, anchor: .top)

        guard centersTodayCell else {
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollSettleDelay) {
                setProgrammaticScroll(false)
            }
            return
        }

        let dayID = CalendarMonthGridIdentifiers.day(monthIndex: todayMonthIdx, dateKey: todayKey)
        DispatchQueue.main.async {
            proxy.scrollTo(dayID, anchor: .center)
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
