#if os(macOS)
import SwiftUI

enum CalendarTimelineScrollSupport {
    static func clampedDayIndex(offsetX: CGFloat, colWidth: CGFloat) -> Int {
        let rawDay = Int(floor(max(offsetX, 0) / max(colWidth, 1)))
        return min(max(rawDay, 0), calRenderDays - 1)
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
