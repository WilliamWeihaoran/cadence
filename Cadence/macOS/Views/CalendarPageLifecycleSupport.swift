#if os(macOS)
import SwiftUI

enum CalendarPageLifecycleSupport {
    static func calendarTitleLabel(
        viewMode: CalViewMode,
        visibleMonthIdx: Int,
        visibleTimelineDayIndex: Int?,
        rememberedDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> String {
        if viewMode == .month {
            return CalendarPageStateSupport.visibleMonthLabel(
                visibleMonthIdx: visibleMonthIdx,
                calendar: calendar
            )
        }

        let dayIndex = visibleTimelineDayIndex ?? CalendarPageStateSupport.rememberedTimelineDayIndex(
            rememberedDateKey: rememberedDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: calendar
        )
        let visibleDate = calendar.date(byAdding: .day, value: dayIndex, to: bufferStart) ?? Date()
        return DateFormatters.monthYear.string(from: visibleDate)
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
        CalendarPageStateSupport.restoreTimelineScrollIfNeeded(
            didRestoreTimelineScroll: &didRestoreTimelineScroll,
            rememberedScrollHour: rememberedScrollHour,
            rememberedDateKey: rememberedDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            visibleTimelineDayIndex: &visibleTimelineDayIndex,
            visibleTimelineHour: &visibleTimelineHour,
            timelineScrollState: timelineScrollState,
            vProxy: vProxy,
            hProxy: hProxy,
            colWidth: colWidth,
            setHorizontalRestoring: setHorizontalRestoring,
            setVerticalRestoring: setVerticalRestoring
        )
    }
}
#endif
