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
        overdoTasks = allTasks.filter {
            !$0.isDone &&
            !$0.isCancelled &&
            !$0.scheduledDate.isEmpty &&
            $0.scheduledDate < todayKey &&
            !scheduledExclusions.contains($0.id)
        }

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
                    activeTaskCount: (project.tasks ?? []).filter { !$0.isDone && !$0.isCancelled }.count
                )
            }

        let areaSummaries = areas
            .filter(\.isActive)
            .flatMap { area in
                area.sectionConfigs.compactMap { config -> TodayOverdueSectionSummary? in
                    guard !config.isArchived, !config.isCompleted, !config.dueDate.isEmpty, config.dueDate < todayKey else { return nil }
                    let tasks = (area.tasks ?? []).filter { $0.resolvedSectionName.caseInsensitiveCompare(config.name) == .orderedSame }
                    let openCount = tasks.filter { !$0.isDone && !$0.isCancelled }.count
                    let doneCount = tasks.filter(\.isDone).count
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
                    let openCount = tasks.filter { !$0.isDone && !$0.isCancelled }.count
                    let doneCount = tasks.filter(\.isDone).count
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

        byDoDateBaseTasks = allTasks.filter { !$0.isDone && !$0.isCancelled }
        byDoDateBaseSortedTasks = byDoDateBaseTasks.taskSorted(by: sortField, direction: sortDirection)
        doneTasks = allTasks
            .filter { task in
                guard task.isDone || task.isCancelled else { return false }
                guard mode == .todayOverview else { return true }
                guard let completedAt = task.completedAt else { return false }
                return DateFormatters.dateKey(from: completedAt) == todayKey
            }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    var todayEligibleTasks: [AppTask] {
        uniqueTasks(from: overdue + overdoTasks + dueTodayTasks + doTodayTasks)
    }

    func todayGroupedTaskItems(showRolloverNotice: Bool) -> [AppTask] {
        uniqueTasks(from: showRolloverNotice ? (overdue + dueTodayTasks + doTodayTasks) : (overdue + overdoTasks + dueTodayTasks + doTodayTasks))
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
