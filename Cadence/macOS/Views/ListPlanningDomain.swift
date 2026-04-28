#if os(macOS)
import CoreGraphics
import Foundation

// MARK: - Planning Scale

enum PlanningScale: String, CaseIterable {
    case oneWeek    = "1W"
    case twoWeeks   = "2W"
    case month      = "M"

    var days: Int {
        switch self {
        case .oneWeek:  return 7
        case .twoWeeks: return 14
        case .month:    return 30
        }
    }

    var dayWidth: CGFloat {
        switch self {
        case .oneWeek:  return 96
        case .twoWeeks: return 64
        case .month:    return 32
        }
    }
}

// MARK: - Planning Models

struct PlanningTimelineSpan {
    let startIndex: Int
    let endIndex: Int
    let hasScheduledDate: Bool
    let hasDueDate: Bool
    let isBlocked: Bool

    func shifted(by dayOffset: Int, clampedTo dayCount: Int) -> PlanningTimelineSpan {
        guard dayCount > 0 else { return self }
        let newStart = max(0, min(dayCount - 1, startIndex + dayOffset))
        let newEnd = max(newStart, min(dayCount - 1, endIndex + dayOffset))
        return PlanningTimelineSpan(
            startIndex: newStart,
            endIndex: newEnd,
            hasScheduledDate: hasScheduledDate,
            hasDueDate: hasDueDate,
            isBlocked: isBlocked
        )
    }
}

struct PlanningConnector {
    let fromRow: Int
    let toRow: Int
    let fromSpan: PlanningTimelineSpan
    let toSpan: PlanningTimelineSpan
}

struct PlanningTimelineSnapshot {
    let startDate: Date
    let dates: [Date]
    let openTasks: [AppTask]
    let readyTasks: [AppTask]
    let blockedTasks: [AppTask]
    let recurringTasks: [AppTask]
    let timelineTasks: [AppTask]
    let unscheduledTasks: [AppTask]

    private let spansByTaskID: [UUID: PlanningTimelineSpan]
    private let dependentCountsByTaskID: [UUID: Int]

    init(
        startDate: Date,
        dates: [Date],
        openTasks: [AppTask],
        readyTasks: [AppTask],
        blockedTasks: [AppTask],
        recurringTasks: [AppTask],
        timelineTasks: [AppTask],
        unscheduledTasks: [AppTask],
        spansByTaskID: [UUID: PlanningTimelineSpan],
        dependentCountsByTaskID: [UUID: Int]
    ) {
        self.startDate = startDate
        self.dates = dates
        self.openTasks = openTasks
        self.readyTasks = readyTasks
        self.blockedTasks = blockedTasks
        self.recurringTasks = recurringTasks
        self.timelineTasks = timelineTasks
        self.unscheduledTasks = unscheduledTasks
        self.spansByTaskID = spansByTaskID
        self.dependentCountsByTaskID = dependentCountsByTaskID
    }

    var windowLabel: String {
        guard let end = dates.last else { return "" }
        return "\(DateFormatters.shortDate.string(from: startDate)) – \(DateFormatters.shortDate.string(from: end))"
    }

    var noDateLabel: String {
        unscheduledTasks.isEmpty ? "No date" : "No date (\(unscheduledTasks.count))"
    }

    var connectors: [PlanningConnector] {
        let rowByTaskID = Dictionary(uniqueKeysWithValues: timelineTasks.enumerated().map { ($0.element.id, $0.offset) })

        return timelineTasks.flatMap { task in
            guard let toRow = rowByTaskID[task.id], let toSpan = spansByTaskID[task.id] else {
                return [PlanningConnector]()
            }
            return task.dependencyTaskIDs.compactMap { blockerID in
                guard let fromRow = rowByTaskID[blockerID], let fromSpan = spansByTaskID[blockerID] else {
                    return nil
                }
                return PlanningConnector(fromRow: fromRow, toRow: toRow, fromSpan: fromSpan, toSpan: toSpan)
            }
        }
    }

    func span(for task: AppTask) -> PlanningTimelineSpan? {
        spansByTaskID[task.id]
    }

    func dependentCount(for task: AppTask) -> Int {
        dependentCountsByTaskID[task.id, default: 0]
    }
}

// MARK: - Planner

struct ListPlanningPlanner {
    let tasks: [AppTask]
    let allTasks: [AppTask]
    let scale: PlanningScale
    var calendar: Calendar = .current
    var referenceDate: Date = Date()

    private var startDate: Date {
        calendar.startOfDay(for: referenceDate)
    }

    func makeSnapshot() -> PlanningTimelineSnapshot {
        let openTasks = tasks.filter { !$0.isDone && !$0.isCancelled }
        let dates = makeTimelineDates()
        let spansByTaskID = Dictionary(uniqueKeysWithValues: openTasks.compactMap { task in
            planningSpan(for: task).map { (task.id, $0) }
        })
        let dependentCountsByTaskID = makeDependentCounts(for: openTasks)
        let timelineTasks = openTasks
            .filter { spansByTaskID[$0.id] != nil }
            .sorted { planningTimelineSort($0, $1, openTasks: openTasks, dependentCounts: dependentCountsByTaskID) }
        let unscheduledTasks = openTasks
            .filter { spansByTaskID[$0.id] == nil }
            .sorted(by: roadmapSort)

        return PlanningTimelineSnapshot(
            startDate: startDate,
            dates: dates,
            openTasks: openTasks,
            readyTasks: openTasks.filter { !$0.isBlocked(in: allTasks) },
            blockedTasks: openTasks.filter { $0.isBlocked(in: allTasks) },
            recurringTasks: openTasks.filter(\.isRecurring),
            timelineTasks: timelineTasks,
            unscheduledTasks: unscheduledTasks,
            spansByTaskID: spansByTaskID,
            dependentCountsByTaskID: dependentCountsByTaskID
        )
    }

    func commitDrag(task: AppTask, dayOffset: Int) {
        guard dayOffset != 0 else { return }
        if let scheduledDate = shiftedDateKey(from: task.scheduledDate, by: dayOffset) {
            task.scheduledDate = scheduledDate
        }
        if let dueDate = shiftedDateKey(from: task.dueDate, by: dayOffset) {
            task.dueDate = dueDate
        }
    }

    private func makeTimelineDates() -> [Date] {
        (0..<scale.days).compactMap {
            calendar.date(byAdding: .day, value: $0, to: startDate)
        }
    }

    private func makeDependentCounts(for openTasks: [AppTask]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for task in openTasks {
            for blockerID in task.dependencyTaskIDs {
                counts[blockerID, default: 0] += 1
            }
        }
        return counts
    }

    private func planningTimelineSort(
        _ lhs: AppTask,
        _ rhs: AppTask,
        openTasks: [AppTask],
        dependentCounts: [UUID: Int]
    ) -> Bool {
        if lhs.dependencyTaskIDs.contains(rhs.id) { return false }
        if rhs.dependencyTaskIDs.contains(lhs.id) { return true }
        let lhsDepth = dependencyDepth(for: lhs, openTasks: openTasks)
        let rhsDepth = dependencyDepth(for: rhs, openTasks: openTasks)
        if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
        let lhsDependentCount = dependentCounts[lhs.id, default: 0]
        let rhsDependentCount = dependentCounts[rhs.id, default: 0]
        if lhsDependentCount != rhsDependentCount { return lhsDependentCount > rhsDependentCount }
        let lhsBlocked = lhs.isBlocked(in: allTasks)
        let rhsBlocked = rhs.isBlocked(in: allTasks)
        if lhsBlocked != rhsBlocked { return !lhsBlocked }
        return roadmapSort(lhs, rhs)
    }

    private func roadmapSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let lhsKey = anchorDateKey(for: lhs)
        let rhsKey = anchorDateKey(for: rhs)
        if lhsKey != rhsKey {
            switch (lhsKey, rhsKey) {
            case (.none, .some):
                return false
            case (.some, .none):
                return true
            case let (.some(lhsValue), .some(rhsValue)):
                return lhsValue < rhsValue
            case (.none, .none):
                break
            }
        }
        if lhs.scheduledStartMin != rhs.scheduledStartMin {
            if lhs.scheduledStartMin < 0 { return false }
            if rhs.scheduledStartMin < 0 { return true }
            return lhs.scheduledStartMin < rhs.scheduledStartMin
        }
        return lhs.order < rhs.order
    }

    private func anchorDateKey(for task: AppTask) -> String? {
        if !task.scheduledDate.isEmpty { return task.scheduledDate }
        if !task.dueDate.isEmpty { return task.dueDate }
        return nil
    }

    private func planningSpan(for task: AppTask) -> PlanningTimelineSpan? {
        guard let windowEnd = calendar.date(byAdding: .day, value: scale.days - 1, to: startDate) else {
            return nil
        }

        let scheduled = task.scheduledDate.isEmpty ? nil : DateFormatters.date(from: task.scheduledDate)
        let due = task.dueDate.isEmpty ? nil : DateFormatters.date(from: task.dueDate)
        guard var start = scheduled ?? due else { return nil }
        var end = due ?? scheduled ?? start
        if end < start { end = start }
        if start > windowEnd || end < startDate { return nil }
        if start < startDate { start = startDate }
        if end > windowEnd { end = windowEnd }

        guard let startIndex = calendar.dateComponents([.day], from: startDate, to: start).day,
              let endIndex = calendar.dateComponents([.day], from: startDate, to: end).day else {
            return nil
        }

        return PlanningTimelineSpan(
            startIndex: startIndex,
            endIndex: max(startIndex, endIndex),
            hasScheduledDate: scheduled != nil,
            hasDueDate: due != nil,
            isBlocked: task.isBlocked(in: allTasks)
        )
    }

    private func dependencyDepth(for task: AppTask, openTasks: [AppTask], visited: Set<UUID> = []) -> Int {
        guard !visited.contains(task.id) else { return 0 }
        let blockers = task.unresolvedDependencies(in: openTasks)
        guard !blockers.isEmpty else { return 0 }
        let nextVisited = visited.union([task.id])
        return 1 + (blockers.map { dependencyDepth(for: $0, openTasks: openTasks, visited: nextVisited) }.max() ?? 0)
    }

    private func shiftedDateKey(from dateKey: String, by dayOffset: Int) -> String? {
        guard !dateKey.isEmpty,
              let date = DateFormatters.date(from: dateKey),
              let shifted = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
            return nil
        }
        return DateFormatters.dateKey(from: shifted)
    }
}
#endif
