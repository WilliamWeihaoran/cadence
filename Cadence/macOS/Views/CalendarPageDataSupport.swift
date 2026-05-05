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
        var dict: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil && task.scheduledStartMin >= 0 && !task.isCancelled {
            dict[task.scheduledDate, default: []].append(task)
        }
        return dict
    }

    static func unscheduledTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var dict: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil && task.scheduledStartMin == -1 && !task.scheduledDate.isEmpty && !task.isCancelled && !task.isDone {
            dict[task.scheduledDate, default: []].append(task)
        }
        return dict
    }

    static func monthTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var dict: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil && !task.isCancelled {
            if !task.scheduledDate.isEmpty {
                dict[task.scheduledDate, default: []].append(task)
            } else if !task.dueDate.isEmpty {
                dict[task.dueDate, default: []].append(task)
            }
        }
        return dict
    }

    static func bundlesByDate(_ bundles: [TaskBundle]) -> [String: [TaskBundle]] {
        var dict: [String: [TaskBundle]] = [:]
        for bundle in bundles where !bundle.isCompleted {
            dict[bundle.dateKey, default: []].append(bundle)
        }
        return dict
    }

    static func handleViewModeChange(
        oldMode: CalViewMode,
        newMode: CalViewMode,
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
