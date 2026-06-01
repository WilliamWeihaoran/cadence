import Foundation
import SwiftUI

enum CadenceCalendarViewMode: String, CaseIterable, Hashable {
    case week = "Week"
    case twoWeeks = "2 Weeks"
    case month = "Month"

    static let pickerCases: [CadenceCalendarViewMode] = [.week, .month]

    var daysCount: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 1
        }
    }
}

enum CadenceCalendarPresentation: String, CaseIterable, Hashable {
    case timeline = "Timeline"
    case board = "Board"
}

enum CadenceCalendarBoardMarkerKind: Hashable {
    case task
    case event
}

struct CadenceCalendarBoardMarker: Identifiable {
    let id: String
    let kind: CadenceCalendarBoardMarkerKind
    let color: Color
    let isCompleted: Bool
    let count: Int
}

struct CadenceCalendarBoardDaySummary: Identifiable {
    let dateKey: String
    let taskMarkers: [CadenceCalendarBoardMarker]
    let eventMarkers: [CadenceCalendarBoardMarker]
    let bundleCount: Int
    let overflowCount: Int

    var id: String { dateKey }

    var totalCount: Int {
        taskMarkers.reduce(0) { $0 + $1.count } + eventMarkers.count + bundleCount + overflowCount
    }
}

enum CadenceCalendarBoardSupport {
    static func monthSummaries(
        monthDate: Date,
        tasksByDate: [String: [AppTask]],
        bundlesByDate: [String: [TaskBundle]],
        calendar: Calendar = .current,
        eventMarkers: (Date, String) -> [CadenceCalendarBoardMarker] = { _, _ in [] }
    ) -> [String: CadenceCalendarBoardDaySummary] {
        var summaries: [String: CadenceCalendarBoardDaySummary] = [:]
        summaries.reserveCapacity(42)

        for date in CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar) {
            let key = DateFormatters.dateKey(from: date)
            summaries[key] = daySummary(
                dateKey: key,
                tasks: CadenceScheduleSupport.items(on: key, in: tasksByDate),
                bundles: CadenceScheduleSupport.items(on: key, in: bundlesByDate),
                eventMarkers: eventMarkers(date, key)
            )
        }

        return summaries
    }

    static func daySummary(
        dateKey: String,
        tasks: [AppTask],
        bundles: [TaskBundle],
        eventMarkers: [CadenceCalendarBoardMarker] = [],
        maxTaskMarkers: Int = 4,
        maxEventMarkers: Int = 5,
        maxBundleMarkers: Int = 1
    ) -> CadenceCalendarBoardDaySummary {
        let sortedTasks = CadenceTaskQuerySupport.sortedTasks(
            tasks.filter { !$0.isCancelled },
            sortMode: .priority
        )
        let taskGroups = taskGroupMarkers(from: sortedTasks)
        let visibleTaskGroups = Array(taskGroups.prefix(max(0, maxTaskMarkers)))
        let visibleEvents = Array(eventMarkers.prefix(max(0, maxEventMarkers)))
        let visibleBundleCount = min(max(0, maxBundleMarkers), bundles.count)
        let hiddenTaskCount = taskGroups.dropFirst(visibleTaskGroups.count).reduce(0) { $0 + $1.count }
        let hiddenEventCount = max(0, eventMarkers.count - visibleEvents.count)
        let hiddenBundleCount = max(0, bundles.count - visibleBundleCount)

        return CadenceCalendarBoardDaySummary(
            dateKey: dateKey,
            taskMarkers: visibleTaskGroups,
            eventMarkers: visibleEvents,
            bundleCount: visibleBundleCount,
            overflowCount: hiddenTaskCount + hiddenEventCount + hiddenBundleCount
        )
    }

    private static func taskGroupMarkers(from tasks: [AppTask]) -> [CadenceCalendarBoardMarker] {
        var groupOrder: [String] = []
        var groupedMarkers: [String: (color: Color, isCompleted: Bool, count: Int)] = [:]

        for task in tasks {
            let key = taskGroupKey(for: task)
            if groupedMarkers[key] == nil {
                groupOrder.append(key)
                groupedMarkers[key] = (Color(hex: task.containerColor), true, 0)
            }
            guard var marker = groupedMarkers[key] else { continue }
            marker.count += 1
            marker.isCompleted = marker.isCompleted && task.isDone
            groupedMarkers[key] = marker
        }

        return groupOrder.compactMap { key in
            guard let marker = groupedMarkers[key] else { return nil }
            return CadenceCalendarBoardMarker(
                id: key,
                kind: .task,
                color: marker.color,
                isCompleted: marker.isCompleted,
                count: marker.count
            )
        }
    }

    private static func taskGroupKey(for task: AppTask) -> String {
        if let area = task.area { return "area-\(area.id.uuidString)" }
        if let project = task.project { return "project-\(project.id.uuidString)" }
        return "inbox"
    }
}

enum CalendarBoardPlannerSupport {
    static let visibleDayCount = 7
    static let defaultRenderDayCount = 3650
    static let plannerRenderDayCount = 420
    static let plannerLeadingDayCount = plannerRenderDayCount / 2
    static let plannerRecenterThreshold = 42

    static func date(at dayIndex: Int, bufferStart: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: dayIndex, to: bufferStart) ?? bufferStart)
    }

    static func plannerWindowStart(for anchorDate: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -plannerLeadingDayCount, to: anchorDate) ?? anchorDate
        )
    }

    static func dayIndex(
        for date: Date,
        bufferStart: Date,
        calendar: Calendar = .current,
        renderDays: Int = defaultRenderDayCount
    ) -> Int {
        let raw = calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: date)).day ?? 0
        return min(max(raw, 0), max(0, renderDays - 1))
    }

    static func shouldRecenter(dayIndex: Int, renderDays: Int = plannerRenderDayCount) -> Bool {
        guard renderDays > plannerRecenterThreshold * 2 else { return false }
        return dayIndex <= plannerRecenterThreshold || dayIndex >= renderDays - plannerRecenterThreshold - 1
    }

    static func title(for anchorDate: Date, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: anchorDate)
        let end = calendar.date(byAdding: .day, value: visibleDayCount - 1, to: start) ?? start
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(DateFormatters.monthAbbrev.string(from: start)) \(DateFormatters.dayNumber.string(from: start))-\(DateFormatters.dayNumber.string(from: end))"
        }
        return "\(DateFormatters.monthAbbrev.string(from: start)) \(DateFormatters.dayNumber.string(from: start)) - \(DateFormatters.monthAbbrev.string(from: end)) \(DateFormatters.dayNumber.string(from: end))"
    }

    static func dateByMovingWindow(_ date: Date, by delta: Int, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: delta * visibleDayCount, to: date) ?? date)
    }

    static func tasks(on dateKey: String, from allTasks: [AppTask]) -> [AppTask] {
        allTasks
            .filter { task in
                guard !task.isCancelled, task.bundle == nil else { return false }
                return task.scheduledDate == dateKey || (task.scheduledDate.isEmpty && task.dueDate == dateKey)
            }
            .sorted { lhs, rhs in
                boardTaskSort(lhs, rhs)
            }
    }

    static func tasksByBoardDate(from allTasks: [AppTask]) -> [String: [AppTask]] {
        var grouped: [String: [AppTask]] = [:]

        for task in allTasks {
            guard !task.isCancelled, task.bundle == nil else { continue }

            if !task.scheduledDate.isEmpty {
                grouped[task.scheduledDate, default: []].append(task)
            } else if !task.dueDate.isEmpty {
                grouped[task.dueDate, default: []].append(task)
            }
        }

        return grouped.mapValues { tasks in
            tasks.sorted { lhs, rhs in
                boardTaskSort(lhs, rhs)
            }
        }
    }

    static func boardTaskSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let lhsTimed = lhs.scheduledStartMin >= 0
        let rhsTimed = rhs.scheduledStartMin >= 0
        if lhsTimed != rhsTimed { return lhsTimed }

        if lhsTimed, lhs.scheduledStartMin != rhs.scheduledStartMin {
            return lhs.scheduledStartMin < rhs.scheduledStartMin
        }

        let lhsPlanned = !lhs.scheduledDate.isEmpty
        let rhsPlanned = !rhs.scheduledDate.isEmpty
        if lhsPlanned != rhsPlanned { return lhsPlanned }

        let lhsPriority = priorityRank(lhs.priority)
        let rhsPriority = priorityRank(rhs.priority)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }

        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}

enum CadenceScheduleSupport {
    static let calendarStartHour = 6
    static let calendarEndHour = 23

    static func tasks(on dateKey: String, from tasks: [AppTask], includeCompleted: Bool = true) -> [AppTask] {
        tasks
            .filter { task in
                guard !task.isCancelled else { return false }
                guard includeCompleted || !task.isDone else { return false }
                return task.scheduledDate == dateKey || task.dueDate == dateKey
            }
            .sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
    }

    static func scheduledTasks(
        on dateKey: String,
        from tasks: [AppTask],
        includeCompleted: Bool = false,
        excludeBundled: Bool = false
    ) -> [AppTask] {
        tasks
            .filter {
                !$0.isCancelled &&
                (includeCompleted || !$0.isDone) &&
                (!excludeBundled || $0.bundle == nil) &&
                $0.scheduledDate == dateKey &&
                $0.scheduledStartMin >= 0
            }
            .sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
    }

    static func bundles(on dateKey: String, from bundles: [TaskBundle], includeCompleted: Bool = true) -> [TaskBundle] {
        bundles
            .filter { $0.dateKey == dateKey && (includeCompleted || !$0.isCompleted) }
            .sorted { $0.startMin < $1.startMin }
    }

    static func tasks(in hour: Int, from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { $0.scheduledStartMin / 60 == hour }
    }

    static func bundles(in hour: Int, from bundles: [TaskBundle]) -> [TaskBundle] {
        bundles.filter { $0.startMin / 60 == hour }
    }

    static func itemCount(on dateKey: String, tasks: [AppTask], bundles: [TaskBundle]) -> Int {
        let taskCount = tasks.filter { !$0.isCancelled && ($0.scheduledDate == dateKey || $0.dueDate == dateKey) }.count
        let bundleCount = bundles.filter { $0.dateKey == dateKey }.count
        return taskCount + bundleCount
    }

    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func dates(containing anchorDate: Date, mode: CadenceCalendarViewMode, calendar: Calendar = .current) -> [Date] {
        let start: Date
        switch mode {
        case .week, .twoWeeks:
            start = startOfWeek(containing: anchorDate, calendar: calendar)
        case .month:
            start = calendar.startOfDay(for: anchorDate)
        }

        return (0..<mode.daysCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    static func shiftedDate(_ date: Date, mode: CadenceCalendarViewMode, by value: Int, calendar: Calendar = .current) -> Date {
        switch mode {
        case .week:
            return calendar.date(byAdding: .day, value: value * 7, to: date) ?? date
        case .twoWeeks:
            return calendar.date(byAdding: .day, value: value * 14, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: value, to: date) ?? date
        }
    }

    static func monthGridDays(for monthDate: Date, calendar: Calendar = .current) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate),
              let gridStart = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)?.start,
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let gridEnd = calendar.dateInterval(of: .weekOfMonth, for: lastDay)?.end
        else { return [] }

        var result: [Date] = []
        var cursor = gridStart
        while cursor < gridEnd {
            result.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd
        }
        return result
    }

    static func calendarTitle(for anchorDate: Date, mode: CadenceCalendarViewMode, calendar: Calendar = .current) -> String {
        switch mode {
        case .month:
            return DateFormatters.monthYear.string(from: anchorDate)
        case .week, .twoWeeks:
            let days = dates(containing: anchorDate, mode: mode, calendar: calendar)
            guard let first = days.first, let last = days.last else {
                return DateFormatters.monthYear.string(from: anchorDate)
            }
            if calendar.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(DateFormatters.monthAbbrev.string(from: first)) \(DateFormatters.dayNumber.string(from: first))-\(DateFormatters.dayNumber.string(from: last))"
            }
            return "\(DateFormatters.monthAbbrev.string(from: first)) \(DateFormatters.dayNumber.string(from: first)) - \(DateFormatters.monthAbbrev.string(from: last)) \(DateFormatters.dayNumber.string(from: last))"
        }
    }

    static func tasksByScheduledDate(_ tasks: [AppTask], includeCompleted: Bool = false) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil &&
            task.scheduledStartMin >= 0 &&
            !task.scheduledDate.isEmpty &&
            !task.isCancelled &&
            (includeCompleted || !task.isDone) {
            result[task.scheduledDate, default: []].append(task)
        }
        return result.mapValues { tasks in
            tasks.sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
        }
    }

    static func unscheduledTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil &&
            task.scheduledStartMin == -1 &&
            !task.scheduledDate.isEmpty &&
            !task.isCancelled &&
            !task.isDone {
            result[task.scheduledDate, default: []].append(task)
        }
        return result.mapValues { CadenceTaskQuerySupport.sortedTasks($0, sortMode: .priority) }
    }

    static func monthTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil && !task.isCancelled {
            if !task.scheduledDate.isEmpty {
                result[task.scheduledDate, default: []].append(task)
            } else if !task.dueDate.isEmpty {
                result[task.dueDate, default: []].append(task)
            }
        }
        return result.mapValues { CadenceTaskQuerySupport.sortedTasks($0, sortMode: .priority) }
    }

    static func bundlesByDate(_ bundles: [TaskBundle], includeCompleted: Bool = false) -> [String: [TaskBundle]] {
        var result: [String: [TaskBundle]] = [:]
        for bundle in bundles where includeCompleted || !bundle.isCompleted {
            result[bundle.dateKey, default: []].append(bundle)
        }
        return result.mapValues { $0.sorted { $0.startMin < $1.startMin } }
    }

    static func items<T>(on dateKey: String, in itemsByDate: [String: [T]]) -> [T] {
        itemsByDate[dateKey] ?? []
    }

    static func dueOnlyTasks(on dateKey: String, from tasks: [AppTask]) -> [AppTask] {
        CadenceTaskQuerySupport.sortedTasks(
            tasks.filter {
                !$0.isCancelled &&
                !$0.isDone &&
                $0.dueDate == dateKey &&
                $0.scheduledDate != dateKey
            },
            sortMode: .priority
        )
    }

    static func calendarDayTasks(on dateKey: String, from tasks: [AppTask]) -> [AppTask] {
        CadenceTaskQuerySupport.sortedTasks(
            tasks.filter {
                !$0.isCancelled &&
                ($0.scheduledDate == dateKey || $0.dueDate == dateKey)
            },
            sortMode: .priority
        )
    }

    static func blockRange(startMinute: Int, fallbackDuration: Int) -> (start: Int, end: Int) {
        let start = max(calendarStartHour * 60, startMinute)
        let duration = max(15, fallbackDuration)
        let end = min(calendarEndHour * 60, start + duration)
        return (start, max(start + 15, end))
    }

    static func timeRangeLabel(startMinute: Int, endMinute: Int) -> String {
        TimeFormatters.timeRange(startMin: startMinute, endMin: endMinute)
    }
}
