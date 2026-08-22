#if os(macOS)
import SwiftUI

struct TasksPanelDerivedState {
    let overdue: [AppTask]
    let dueTodayTasks: [AppTask]
    let doTodayTasks: [AppTask]
    let overdoTasks: [AppTask]
    let overdueListSummaries: [TodayOverdueListSummary]
    let overdueSectionSummaries: [TodayOverdueSectionSummary]
    let byDoDateBaseTasks: [AppTask]
    let byDoDateBaseSortedTasks: [AppTask]
    let doneTasks: [AppTask]

    init(
        allTasks: [AppTask],
        areas: [Area],
        projects: [Project],
        mode: TasksPanelMode,
        todayKey: String,
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) {
        overdue = allTasks.filter { !$0.isDone && !$0.isCancelled && !$0.dueDate.isEmpty && $0.dueDate < todayKey }
        dueTodayTasks = allTasks.filter { !$0.isDone && !$0.isCancelled && $0.dueDate == todayKey }

        let scheduledExclusions = Set(overdue.map(\.id)).union(dueTodayTasks.map(\.id))
        doTodayTasks = allTasks.filter {
            !$0.isDone && !$0.isCancelled && $0.scheduledDate == todayKey && !scheduledExclusions.contains($0.id)
        }
        // The over-do bucket, from `CadenceTodayRolloverSupport` rather than re-spelled here: the
        // banner that offers to roll these is shared now (T-195), and a predicate the banner and
        // its contents disagreed about would show a notice over a list that did not match it.
        // Same set as before — the exclusion set it derives is `scheduledExclusions`.
        overdoTasks = CadenceTodayRolloverSupport.pastDoTasks(from: allTasks, todayKey: todayKey)

        overdueListSummaries = projects
            .filter { $0.isActive && !$0.dueDate.isEmpty && $0.dueDate < todayKey }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.order < rhs.order
            }
            .map { project in
                TodayOverdueListSummary(
                    id: "project-\(project.id.uuidString)",
                    areaID: nil,
                    projectID: project.id,
                    title: project.name,
                    icon: project.icon,
                    color: Color(hex: project.colorHex),
                    dueDateKey: project.dueDate,
                    activeTaskCount: CadenceTaskQuerySupport.openTaskCount(for: project)
                )
            }

        let areaSummaries = areas
            .filter(\.isActive)
            .flatMap { area in
                area.sectionConfigs.compactMap { config -> TodayOverdueSectionSummary? in
                    guard !config.isArchived, !config.isCompleted, !config.dueDate.isEmpty, config.dueDate < todayKey else { return nil }
                    let tasks = (area.tasks ?? []).filter { $0.resolvedSectionName.caseInsensitiveCompare(config.name) == .orderedSame }
                    let openCount = CadenceTaskQuerySupport.openTaskCount(from: tasks)
                    let doneCount = CadenceTaskQuerySupport.completedTaskCount(from: tasks)
                    return TodayOverdueSectionSummary(
                        id: "area-\(area.id.uuidString)-section-\(config.id.uuidString)",
                        areaID: area.id,
                        projectID: nil,
                        sectionName: config.name,
                        parentName: area.name,
                        parentIcon: area.icon,
                        parentColor: Color(hex: area.colorHex),
                        dueDateKey: config.dueDate,
                        openTaskCount: openCount,
                        completedTaskCount: doneCount
                    )
                }
            }
        let projectSummaries = projects
            .filter(\.isActive)
            .flatMap { project in
                project.sectionConfigs.compactMap { config -> TodayOverdueSectionSummary? in
                    guard !config.isArchived, !config.isCompleted, !config.dueDate.isEmpty, config.dueDate < todayKey else { return nil }
                    let tasks = (project.tasks ?? []).filter { $0.resolvedSectionName.caseInsensitiveCompare(config.name) == .orderedSame }
                    let openCount = CadenceTaskQuerySupport.openTaskCount(from: tasks)
                    let doneCount = CadenceTaskQuerySupport.completedTaskCount(from: tasks)
                    return TodayOverdueSectionSummary(
                        id: "project-\(project.id.uuidString)-section-\(config.id.uuidString)",
                        areaID: nil,
                        projectID: project.id,
                        sectionName: config.name,
                        parentName: project.name,
                        parentIcon: project.icon,
                        parentColor: Color(hex: project.colorHex),
                        dueDateKey: config.dueDate,
                        openTaskCount: openCount,
                        completedTaskCount: doneCount
                    )
                }
            }
        overdueSectionSummaries = (areaSummaries + projectSummaries).sorted { lhs, rhs in
            if lhs.dueDateKey != rhs.dueDateKey { return lhs.dueDateKey < rhs.dueDateKey }
            if lhs.parentName != rhs.parentName { return lhs.parentName.localizedCaseInsensitiveCompare(rhs.parentName) == .orderedAscending }
            return lhs.sectionName.localizedCaseInsensitiveCompare(rhs.sectionName) == .orderedAscending
        }

        byDoDateBaseTasks = CadenceTaskQuerySupport.openTasks(from: allTasks)
        byDoDateBaseSortedTasks = byDoDateBaseTasks.taskSorted(by: sortField, direction: sortDirection)
        // Built once, not once per completed task: `DateFormatters.dateKey(from:)` was being
        // called for every completed task the user has ever created, on every rebuild. The
        // half-open day range is the same predicate — `dateKey(from:) == todayKey` is exactly
        // "falls inside today's calendar day" for the same calendar `todayKey` came from.
        let calendar = Calendar.current
        let todayRange: Range<Date>? = {
            guard let parsedToday = DateFormatters.date(from: todayKey) else { return nil }
            let dayStart = calendar.startOfDay(for: parsedToday)
            // `startOfDay` on both ends rather than `dayStart + 1 day`, so a DST day whose
            // midnight does not exist still ends on tomorrow's real first instant.
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            return dayStart..<calendar.startOfDay(for: nextDay)
        }()
        doneTasks = allTasks
            .filter { task in
                guard task.isDone || task.isCancelled else { return false }
                guard mode == .todayOverview else { return true }
                guard let completedAt = task.completedAt else { return false }
                guard let todayRange else {
                    // Unreachable in practice (`todayKey` is produced by the same formatter);
                    // keep the original per-task comparison as the safety net.
                    return DateFormatters.dateKey(from: completedAt) == todayKey
                }
                return todayRange.contains(completedAt)
            }
            .taskCompletionSorted()
    }

    var todayEligibleTasks: [AppTask] {
        uniqueTasks(from: overdue + overdoTasks + dueTodayTasks + doTodayTasks)
    }

    func todayGroupedTaskItems(showRolloverNotice: Bool) -> [AppTask] {
        CadenceTodayRolloverSupport.groupedTasks(
            from: todayEligibleTasks,
            withholding: overdoTasks,
            isNoticeVisible: showRolloverNotice
        )
    }

    func isEmptyState(for mode: TasksPanelMode) -> Bool {
        switch mode {
        case .todayOverview:
            return overdue.isEmpty &&
            overdoTasks.isEmpty &&
            dueTodayTasks.isEmpty &&
            doTodayTasks.isEmpty &&
            doneTasks.isEmpty
        case .byDoDate:
            return byDoDateBaseTasks.isEmpty && doneTasks.isEmpty
        }
    }

    private func uniqueTasks(from tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
    }
}
#endif
