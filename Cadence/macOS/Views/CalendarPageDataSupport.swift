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
        for task in tasks where task.scheduledStartMin >= 0 && !task.isCancelled {
            dict[task.scheduledDate, default: []].append(task)
        }
        return dict
    }

    static func unscheduledTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var dict: [String: [AppTask]] = [:]
        for task in tasks where task.scheduledStartMin == -1 && !task.scheduledDate.isEmpty && !task.isCancelled && !task.isDone {
            dict[task.scheduledDate, default: []].append(task)
        }
        return dict
    }

    static func monthTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var dict: [String: [AppTask]] = [:]
        for task in tasks where !task.isCancelled {
            if !task.scheduledDate.isEmpty {
                dict[task.scheduledDate, default: []].append(task)
            } else if !task.dueDate.isEmpty {
                dict[task.dueDate, default: []].append(task)
            }
        }
        return dict
    }

    static func handleViewModeChange(
        newMode: CalViewMode,
        visibleMonthIdx: inout Int,
        monthGridResetNonce: inout Int,
        didRestoreTimelineScroll: inout Bool
    ) {
        if newMode == .month {
            visibleMonthIdx = 60
            monthGridResetNonce += 1
        } else {
            didRestoreTimelineScroll = false
        }
    }
}
#endif
