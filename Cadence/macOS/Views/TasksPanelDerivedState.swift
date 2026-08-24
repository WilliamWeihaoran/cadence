#if os(macOS)
import SwiftUI

struct TasksPanelDerivedState {
    let overdue: [AppTask]
    let dueTodayTasks: [AppTask]
    let doTodayTasks: [AppTask]
    let overdoTasks: [AppTask]
    let overdueListSummaries: [CadenceTodayOverdueListSummary]
    let overdueSectionSummaries: [CadenceTodayOverdueSectionSummary]
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

        // The two past-due summaries, and the `sectionConfigs` walk behind them, are
        // `CadenceTodayOverdueSummarySupport` rather than re-spelled here (T-195, second half):
        // both were declared and derived under `macOS/Views/` with zero readers under
        // `Cadence/iOS/`, and neither the project due-date filter nor the column walk touches
        // AppKit. `CadenceTodayOverdueSummarySurfaceTests` recomputes both with the old inline
        // expressions and asserts they are identical, member for member and in order.
        overdueListSummaries = CadenceTodayOverdueSummarySupport.listSummaries(
            projects: projects,
            todayKey: todayKey
        )
        overdueSectionSummaries = CadenceTodayOverdueSummarySupport.sectionSummaries(
            areas: areas,
            projects: projects,
            todayKey: todayKey
        )

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
