#if os(macOS)
import SwiftUI

struct CalendarPageStateSupport {
    static func visibleMonthLabel(visibleMonthIdx: Int, calendar: Calendar) -> String {
        let currentMonthStart: Date = {
            var comps = calendar.dateComponents([.year, .month], from: Date())
            comps.day = 1
            return calendar.date(from: comps) ?? Date()
        }()
        let month = calendar.date(byAdding: .month, value: visibleMonthIdx - 60, to: currentMonthStart) ?? Date()
        return DateFormatters.monthYear.string(from: month)
    }

    static func rememberedTimelineDayIndex(
        rememberedDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> Int {
        guard let rememberedDate = DateFormatters.date(from: rememberedDateKey) else { return todayDayIdx }
        let day = calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: rememberedDate)).day ?? todayDayIdx
        return min(max(day, 0), calRenderDays - 1)
    }

    static func timelineDayIndexForMonthViewReturn(
        visibleMonthIdx: Int,
        todayMonthIdx: Int = 60,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar,
        today: Date = Date()
    ) -> Int {
        let targetDate: Date
        if visibleMonthIdx == todayMonthIdx {
            targetDate = calendar.startOfDay(for: today)
        } else {
            var currentMonthComponents = calendar.dateComponents([.year, .month], from: today)
            currentMonthComponents.day = 1
            let currentMonthStart = calendar.date(from: currentMonthComponents) ?? today
            targetDate = calendar.date(byAdding: .month, value: visibleMonthIdx - todayMonthIdx, to: currentMonthStart) ?? today
        }

        let day = calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: targetDate)).day ?? todayDayIdx
        return min(max(day, 0), calRenderDays - 1)
    }

    static func restoreTimelineScrollIfNeeded(
        didRestoreTimelineScroll: inout Bool,
        rememberedScrollHour: Int,
        rememberedDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        visibleTimelineDayIndex: inout Int?,
        visibleTimelineHour: inout Int?,
        timelineScrollState: CalendarTimelineScrollState,
        vProxy: ScrollViewProxy,
        hProxy: ScrollViewProxy,
        colWidth: CGFloat,
        setHorizontalRestoring: @escaping (Bool) -> Void,
        setVerticalRestoring: @escaping (Bool) -> Void
    ) {
        guard !didRestoreTimelineScroll else { return }

        let currentHour = Calendar.current.component(.hour, from: Date())
        let fallbackHour = max(calStartHour, currentHour - 1)
        let scrollHour = rememberedScrollHour >= calStartHour ? rememberedScrollHour : fallbackHour
        let targetDay = rememberedTimelineDayIndex(
            rememberedDateKey: rememberedDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: Calendar.current
        )

        didRestoreTimelineScroll = true
        setHorizontalRestoring(true)
        setVerticalRestoring(true)
        visibleTimelineDayIndex = targetDay
        visibleTimelineHour = scrollHour
        timelineScrollState.jumpHeaderOffset(to: -CGFloat(targetDay) * colWidth)

        DispatchQueue.main.async {
            hProxy.scrollTo("day_\(targetDay)", anchor: .leading)
            vProxy.scrollTo("tl_\(scrollHour)", anchor: .top)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                setHorizontalRestoring(false)
                setVerticalRestoring(false)
            }
        }
    }

    static func schedulePersistence<T: Equatable>(
        value: T,
        cancelPending: () -> Void,
        storePending: @escaping (DispatchWorkItem?) -> Void,
        delay: TimeInterval = 0.12,
        persist: @escaping (T) -> Void
    ) {
        cancelPending()
        let workItem = DispatchWorkItem {
            persist(value)
            storePending(nil)
        }
        storePending(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    static func timelineJumpTarget(
        request: CalendarNavigationManager.Request,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> (day: Int, hour: Int) {
        let day = min(max(
            calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: DateFormatters.date(from: request.dateKey) ?? Date())).day ?? todayDayIdx,
            0
        ), calRenderDays - 1)
        let hour = min(max(request.preferredHour - 1, calStartHour), calEndHour - 1)
        return (day, hour)
    }
}
#endif
