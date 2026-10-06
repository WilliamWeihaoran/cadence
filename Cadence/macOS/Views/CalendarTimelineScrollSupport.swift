#if os(macOS)
import SwiftUI

enum CalendarTimelineScrollSupport {
    static func clampedDayIndex(offsetX: CGFloat, colWidth: CGFloat) -> Int {
        let rawDay = Int(floor(max(offsetX, 0) / max(colWidth, 1)))
        return min(max(rawDay, 0), calRenderDays - 1)
    }

    /// The day index a horizontal scroll report should hand to persistence, or `nil` when it
    /// should hand it nothing.
    ///
    /// **T-1498, horizontal axis.** `onScrollGeometryChange(for: CGFloat.self) {
    /// $0.contentOffset.x }` runs its action whenever the transformed value changes, and a raw
    /// content offset changes on **every frame of a live scroll**. The caller's own gate was
    /// `didRestoreTimelineScroll` and nothing else, so every one of those frames formatted a date
    /// key, cancelled the pending work item, allocated a new one and scheduled it on the main
    /// queue — and stored it into a `@State` property of `CalendarPageView`.
    ///
    /// Passing `lastReportedDay: nil` at every report reproduces the old behaviour exactly,
    /// because the old code had no memory of the last day. That is what lets the before and the
    /// after numbers come out of one transcript through one code path.
    static func dayToPersist(
        clampedDay: Int,
        didRestoreTimelineScroll: Bool,
        lastReportedDay: Int?
    ) -> Int? {
        guard didRestoreTimelineScroll else { return nil }
        guard clampedDay != lastReportedDay else { return nil }
        return clampedDay
    }

    /// Adopt a horizontal scroll report and hand the day on, remembering it on the scroll state's
    /// reference box so the next frame's identical report costs nothing.
    ///
    /// `persist` is still the page's debounced writer — the guard collapses a fling to one call
    /// per day crossed, and the debounce behind `persist` collapses those to one `@AppStorage`
    /// write per settled gesture. Two mechanisms, each doing the half the other cannot.
    static func persistVisibleDay(
        clampedDay: Int,
        didRestoreTimelineScroll: Bool,
        state: CalendarTimelineScrollState,
        persist: (Int) -> Void
    ) {
        guard let day = dayToPersist(
            clampedDay: clampedDay,
            didRestoreTimelineScroll: didRestoreTimelineScroll,
            lastReportedDay: state.lastReportedDay
        ) else { return }

        state.lastReportedDay = day
        persist(day)
    }

    static func clampedHour(offsetY: CGFloat, hourHeight: CGFloat) -> Int {
        let rawHour = calStartHour + Int(offsetY / max(hourHeight, 1))
        return min(max(rawHour, calStartHour), calEndHour - 1)
    }

    static func applyTodayHorizontalJump(
        todayDayIdx: Int,
        visibleTimelineDayIndex: Binding<Int?>,
        isRestoringHorizontalScroll: Binding<Bool>,
        hProxy: ScrollViewProxy,
        scrollState: CalendarTimelineScrollState,
        colWidth: CGFloat
    ) {
        jumpHorizontally(
            to: todayDayIdx,
            visibleTimelineDayIndex: visibleTimelineDayIndex,
            isRestoringHorizontalScroll: isRestoringHorizontalScroll,
            hProxy: hProxy,
            scrollState: scrollState,
            colWidth: colWidth,
            animated: false
        )
    }

    static func applyExternalHorizontalJump(
        day: Int,
        visibleTimelineDayIndex: Binding<Int?>,
        isRestoringHorizontalScroll: Binding<Bool>,
        hProxy: ScrollViewProxy,
        scrollState: CalendarTimelineScrollState,
        colWidth: CGFloat
    ) {
        jumpHorizontally(
            to: day,
            visibleTimelineDayIndex: visibleTimelineDayIndex,
            isRestoringHorizontalScroll: isRestoringHorizontalScroll,
            hProxy: hProxy,
            scrollState: scrollState,
            colWidth: colWidth,
            animated: true
        )
    }

    static func jumpHorizontally(
        to day: Int,
        visibleTimelineDayIndex: Binding<Int?>,
        isRestoringHorizontalScroll: Binding<Bool>,
        hProxy: ScrollViewProxy,
        scrollState: CalendarTimelineScrollState,
        colWidth: CGFloat,
        animated: Bool
    ) {
        visibleTimelineDayIndex.wrappedValue = day
        isRestoringHorizontalScroll.wrappedValue = true
        // **T-1498.** A jump writes `anchorDateKey` itself, so what persistence last *saw* is now
        // stale: without this, scrolling one column back onto that remembered day would report a
        // value the box already holds, the guard would refuse it, and the anchor the jump wrote
        // would never be corrected. Dropping the memory costs exactly one report after a jump and
        // is what keeps the remembered day honest.
        scrollState.lastReportedDay = nil
        syncHeaderOffset(to: day, scrollState: scrollState, colWidth: colWidth)

        let scroll = {
            scrollHorizontally(to: day, hProxy: hProxy)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18), scroll)
        } else {
            scroll()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.22 : 0.08)) {
            syncHeaderOffset(to: day, scrollState: scrollState, colWidth: colWidth)
            isRestoringHorizontalScroll.wrappedValue = false
        }
    }

    static func shouldFinishHorizontalJump(
        offsetX: CGFloat,
        targetDay: Int?,
        colWidth: CGFloat
    ) -> Bool {
        guard let targetDay else { return false }
        let targetX = CGFloat(targetDay) * max(colWidth, 1)
        return abs(offsetX - targetX) <= max(1, colWidth * 0.01)
    }

    private static func scrollHorizontally(to day: Int, hProxy: ScrollViewProxy) {
        hProxy.scrollTo("day_\(day)", anchor: .leading)
    }

    static func syncHeaderOffset(to day: Int, scrollState: CalendarTimelineScrollState, colWidth: CGFloat) {
        scrollState.jumpHeaderOffset(to: -CGFloat(day) * max(colWidth, 1))
    }

    static func applyTodayVerticalJump(
        isRestoringVerticalScroll: Binding<Bool>,
        vProxy: ScrollViewProxy
    ) {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let scrollHour = max(calStartHour, currentHour - 1)
        DispatchQueue.main.async {
            vProxy.scrollTo("tl_\(scrollHour)", anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isRestoringVerticalScroll.wrappedValue = false
            }
        }
    }

    static func applyExternalVerticalJump(
        hour: Int,
        visibleTimelineHour: Binding<Int?>,
        isRestoringVerticalScroll: Binding<Bool>,
        vProxy: ScrollViewProxy
    ) {
        visibleTimelineHour.wrappedValue = hour
        isRestoringVerticalScroll.wrappedValue = true
        withAnimation(.easeInOut(duration: 0.2)) {
            vProxy.scrollTo("tl_\(hour)", anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            isRestoringVerticalScroll.wrappedValue = false
        }
    }
}
#endif
