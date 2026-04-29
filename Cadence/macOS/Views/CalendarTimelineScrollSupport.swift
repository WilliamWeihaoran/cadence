#if os(macOS)
import SwiftUI

enum CalendarTimelineScrollSupport {
    static func clampedDayIndex(offsetX: CGFloat, colWidth: CGFloat) -> Int {
        let rawDay = Int(round(offsetX / max(colWidth, 1)))
        return min(max(rawDay, 0), calRenderDays - 1)
    }

    static func clampedHour(offsetY: CGFloat, hourHeight: CGFloat) -> Int {
        let rawHour = calStartHour + Int(offsetY / max(hourHeight, 1))
        return min(max(rawHour, calStartHour), calEndHour - 1)
    }

    static func applyTodayHorizontalJump(
        todayDayIdx: Int,
        colWidth: CGFloat,
        rememberedDateKey: Binding<String>,
        visibleTimelineDayIndex: Binding<Int?>,
        isRestoringHorizontalScroll: Binding<Bool>,
        timelineScrollState: CalendarTimelineScrollState,
        hProxy: ScrollViewProxy
    ) {
        rememberedDateKey.wrappedValue = DateFormatters.todayKey()
        visibleTimelineDayIndex.wrappedValue = todayDayIdx
        isRestoringHorizontalScroll.wrappedValue = true
        timelineScrollState.jumpHeaderOffset(to: -CGFloat(todayDayIdx) * colWidth)
        DispatchQueue.main.async {
            hProxy.scrollTo("day_\(todayDayIdx)", anchor: .leading)
            timelineScrollState.jumpHeaderOffset(to: -CGFloat(todayDayIdx) * colWidth)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isRestoringHorizontalScroll.wrappedValue = false
            }
        }
    }

    static func applyExternalHorizontalJump(
        day: Int,
        colWidth: CGFloat,
        visibleTimelineDayIndex: Binding<Int?>,
        isRestoringHorizontalScroll: Binding<Bool>,
        timelineScrollState: CalendarTimelineScrollState,
        hProxy: ScrollViewProxy
    ) {
        visibleTimelineDayIndex.wrappedValue = day
        isRestoringHorizontalScroll.wrappedValue = true
        timelineScrollState.jumpHeaderOffset(to: -CGFloat(day) * colWidth)
        withAnimation(.easeInOut(duration: 0.2)) {
            hProxy.scrollTo("day_\(day)", anchor: .leading)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            isRestoringHorizontalScroll.wrappedValue = false
        }
    }

    static func applyTodayVerticalJump(
        visibleTimelineHour: Binding<Int?>,
        rememberedScrollHour: Binding<Int>,
        isRestoringVerticalScroll: Binding<Bool>,
        vProxy: ScrollViewProxy
    ) {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let scrollHour = max(calStartHour, currentHour - 1)
        rememberedScrollHour.wrappedValue = scrollHour
        visibleTimelineHour.wrappedValue = scrollHour
        isRestoringVerticalScroll.wrappedValue = true
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
