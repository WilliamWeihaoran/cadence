#if os(macOS)
import SwiftUI

enum CalendarPageDataSupport {
    static func bufferStart(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1825, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    static func todayDayIndex(bufferStart: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: Date())).day ?? 1825
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

    static func bundlesByDate(_ bundles: [TaskBundle]) -> [String: [TaskBundle]] {
        CadenceScheduleSupport.bundlesByDate(bundles)
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
        currentMonthStart: Date? = nil
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
                calendar: calendar
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
