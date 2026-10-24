#if os(macOS)
import SwiftUI

enum CalendarPageDataSupport {
    /// Column 0 of the Day/Week timeline: 1825 days before `anchorDay`.
    ///
    /// **[[T-5352]]: `anchorDay` is the day the page was opened, held by the page, never "now".**
    /// Measured from today on every body pass, the buffer slid forward one day at midnight while
    /// the horizontal scroll offset stayed put, so every column silently took the next day's date
    /// (Oct 18–24 became Oct 19–25 with no gesture). `todayDayIndex` is what moves instead.
    static func bufferStart(calendar: Calendar, anchorDay: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: -1825, to: calendar.startOfDay(for: anchorDay)) ?? anchorDay
    }

    static func todayDayIndex(bufferStart: Date, calendar: Calendar, today: Date = Date()) -> Int {
        calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: today)).day ?? 1825
    }

    static func tasksByScheduledDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        CadenceScheduleSupport.tasksByScheduledDate(tasks, includeCompleted: true)
    }

    static func unscheduledTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        CadenceScheduleSupport.unscheduledTasksByDate(tasks)
    }

    static func monthTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        CadenceScheduleSupport.monthTasksByDate(tasks)
    }

    static func handleViewModeChange(
        oldMode: CadenceCalendarViewMode,
        newMode: CadenceCalendarViewMode,
        visibleMonthIdx: inout Int,
        monthGridResetNonce: inout Int,
        didRestoreTimelineScroll: inout Bool,
        visibleTimelineDayIndex: inout Int?,
        anchorDateKey: inout String,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar,
        currentMonthStart: Date? = nil,
        today: Date = Date()
    ) {
        let resolvedCurrentMonthStart = currentMonthStart ?? CalendarMonthGridSupport.currentMonthStart(calendar: calendar)

        if oldMode != .month,
           let visibleTimelineDayIndex,
           let visibleDate = calendar.date(byAdding: .day, value: visibleTimelineDayIndex, to: bufferStart) {
            anchorDateKey = DateFormatters.dateKey(from: visibleDate)
        }

        if newMode == .month {
            visibleMonthIdx = CalendarPageStateSupport.monthIndexForTimelineAnchor(
                anchorDateKey: anchorDateKey,
                currentMonthStart: resolvedCurrentMonthStart,
                calendar: calendar
            )
            monthGridResetNonce += 1
            return
        }

        if oldMode == .month {
            anchorDateKey = CalendarPageStateSupport.dateKeyForVisibleMonth(
                visibleMonthIdx: visibleMonthIdx,
                currentMonthStart: resolvedCurrentMonthStart,
                calendar: calendar,
                today: today
            )
            let targetDay = CalendarPageStateSupport.timelineDayIndex(
                anchorDateKey: anchorDateKey,
                bufferStart: bufferStart,
                todayDayIdx: todayDayIdx,
                calendar: calendar
            )
            visibleTimelineDayIndex = targetDay
        }

        didRestoreTimelineScroll = false
    }
}
#endif
