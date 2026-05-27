#if os(macOS)
import SwiftUI

struct CalendarPageStateSupport {
    static let todayMonthIndex = 60

    static func visibleMonthLabel(visibleMonthIdx: Int, calendar: Calendar) -> String {
        let currentMonthStart: Date = {
            var comps = calendar.dateComponents([.year, .month], from: Date())
            comps.day = 1
            return calendar.date(from: comps) ?? Date()
        }()
        let month = calendar.date(byAdding: .month, value: visibleMonthIdx - todayMonthIndex, to: currentMonthStart) ?? Date()
        return DateFormatters.monthYear.string(from: month)
    }

    static func timelineDayIndex(
        anchorDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> Int {
        guard let anchorDate = DateFormatters.date(from: anchorDateKey) else { return todayDayIdx }
        let day = calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: anchorDate)).day ?? todayDayIdx
        return min(max(day, 0), calRenderDays - 1)
    }

    static func rememberedTimelineDayIndex(
        rememberedDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> Int {
        timelineDayIndex(
            anchorDateKey: rememberedDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: calendar
        )
    }

    static func monthIndexForTimelineAnchor(
        anchorDateKey: String,
        currentMonthStart: Date,
        todayMonthIdx: Int = todayMonthIndex,
        calendar: Calendar
    ) -> Int {
        guard let anchorDate = DateFormatters.date(from: anchorDateKey) else { return todayMonthIdx }
        return monthIndex(
            for: anchorDate,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )
    }

    static func dateKeyForVisibleMonth(
        visibleMonthIdx: Int,
        todayMonthIdx: Int = todayMonthIndex,
        currentMonthStart: Date,
        calendar: Calendar,
        today: Date = Date()
    ) -> String {
        if visibleMonthIdx == todayMonthIdx {
            return DateFormatters.dateKey(from: today)
        }

        let targetMonth = calendar.date(
            byAdding: .month,
            value: visibleMonthIdx - todayMonthIdx,
            to: currentMonthStart
        ) ?? currentMonthStart
        return DateFormatters.dateKey(from: targetMonth)
    }

    static func boardAnchorDateKey(
        viewMode: CadenceCalendarViewMode,
        visibleMonthIdx: Int,
        visibleTimelineDayIndex: Int?,
        anchorDateKey: String,
        bufferStart: Date,
        currentMonthStart: Date,
        calendar: Calendar
    ) -> String {
        if viewMode == .month {
            return dateKeyForVisibleMonth(
                visibleMonthIdx: visibleMonthIdx,
                currentMonthStart: currentMonthStart,
                calendar: calendar
            )
        }

        if let visibleTimelineDayIndex,
           let visibleDate = calendar.date(byAdding: .day, value: visibleTimelineDayIndex, to: bufferStart) {
            return DateFormatters.dateKey(from: visibleDate)
        }

        return anchorDateKey
    }

    static func boardDateByMovingMonth(_ date: Date, by delta: Int, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        guard let shiftedMonth = calendar.date(byAdding: .month, value: delta, to: startOfDay) else {
            return startOfDay
        }

        var targetComponents = calendar.dateComponents([.year, .month], from: shiftedMonth)
        let currentDay = calendar.component(.day, from: startOfDay)
        let monthStart = calendar.date(from: targetComponents) ?? shiftedMonth
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        targetComponents.day = min(currentDay, dayRange?.count ?? currentDay)

        return calendar.startOfDay(for: calendar.date(from: targetComponents) ?? shiftedMonth)
    }

    static func timelineDayIndexForMonthViewReturn(
        visibleMonthIdx: Int,
        todayMonthIdx: Int = todayMonthIndex,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar,
        today: Date = Date()
    ) -> Int {
        let currentMonthStart = monthStart(for: today, calendar: calendar)
        let targetDate = visibleMonthIdx == todayMonthIdx
            ? today
            : (calendar.date(
                byAdding: .month,
                value: visibleMonthIdx - todayMonthIdx,
                to: currentMonthStart
            ) ?? currentMonthStart)
        let day = calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: targetDate)).day ?? todayDayIdx
        return min(max(day, 0), calRenderDays - 1)
    }

    static func restoreTimelineScrollIfNeeded(
        didRestoreTimelineScroll: inout Bool,
        rememberedScrollHour: Int,
        anchorDateKey: String,
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
            rememberedDateKey: anchorDateKey,
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
