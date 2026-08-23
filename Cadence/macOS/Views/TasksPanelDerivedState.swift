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
        // Today's Completed section is `CadenceTaskQuerySupport.completedTodayTasks` on both
        // platforms now (T-229). This used to be a second, hand-rolled spelling of it — the same
        // `completedAt`-inside-today test with the day range precomputed — sitting beside an iOS
        // one that *also* admitted anything do-dated or due-dated today, so the same day's finished
        // work differed by platform under one shared heading. The precompute moved into the shared
        // function rather than being given up. The `.byDoDate` logbook is a different thing —
        // everything ever settled — and keeps no date test at all.
        doneTasks = mode == .todayOverview
            ? CadenceTaskQuerySupport.completedTodayTasks(from: allTasks, todayKey: todayKey)
            : CadenceTaskQuerySupport.completedTasks(from: allTasks)
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
