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
        visibleMonthIdx: inout Int,
        didInitialPosition: Bool,
        isProgrammaticScroll: Bool
    ) {
        // While a programmatic scroll (initial position restore or a "Today" jump) is in
        // flight, scroll-geometry callbacks reflect the stale pre-jump offset — ignore them
        // so they can't stomp a value that was just set intentionally.
        guard didInitialPosition, !isProgrammaticScroll else { return }
        let visibleTopY = max(y, 0)
        let computedFromTop = monthIndexForOffset(y: visibleTopY, offsets: offsets, totalMonths: totalMonths)
        if visibleMonthIdx != computedFromTop {
            visibleMonthIdx = computedFromTop
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
        setProgrammaticScroll: @escaping (Bool) -> Void
    ) {
        let monthID = CalendarMonthGridIdentifiers.month(todayMonthIdx)
        let dayID = CalendarMonthGridIdentifiers.day(monthIndex: todayMonthIdx, dateKey: todayKey)

        // Guard the two-step scroll (month, then day) so a scroll-geometry callback firing
        // in the gap between them can't recompute `visibleMonthIdx` from the stale
        // pre-jump offset and stomp the value the "Today" jump just set.
        setProgrammaticScroll(true)
        proxy.scrollTo(monthID, anchor: .top)
        DispatchQueue.main.async {
            proxy.scrollTo(dayID, anchor: .center)
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollSettleDelay) {
                setProgrammaticScroll(false)
            }
        }
    }
}
#endif
