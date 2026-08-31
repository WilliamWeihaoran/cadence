#if os(macOS)
import SwiftUI

struct TasksPanelDerivedState {
    let overdue: [AppTask]
    let dueTodayTasks: [AppTask]
    let doTodayTasks: [AppTask]
    let overdoTasks: [AppTask]
    let overdueListSummaries: [CadenceTodayOverdueListSummary]
    let overdueSectionSummaries: [CadenceTodayOverdueSectionSummary]
    let doneTasks: [AppTask]

    init(
        allTasks: [AppTask],
        areas: [Area],
        projects: [Project],
        mode: TasksPanelMode,
        todayKey: String
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

        // `byDoDateBaseTasks` and `byDoDateBaseSortedTasks` were derived here, unconditionally —
        // a filter over every task and a full sort of the result on **every Today render**, for a
        // mode nothing could reach. Both went with `.byDoDate` (T-487), and with them the
        // `sortField`/`sortDirection` parameters that existed only to feed the sort.
        //
        // Today's Completed section is `CadenceTaskQuerySupport.completedTodayTasks` on both
        // platforms now (T-229). This used to be a second, hand-rolled spelling of it — the same
        // `completedAt`-inside-today test with the day range precomputed — sitting beside an iOS
        // one that *also* admitted anything do-dated or due-dated today, so the same day's finished
        // work differed by platform under one shared heading. The precompute moved into the shared
        // function rather than being given up. The other arm was the `.byDoDate` logbook —
        // everything ever settled, no date test at all — and went with the mode (T-487);
        // `CadenceTaskQuerySupport.completedTasks` is still read by the surfaces that want it.
        switch mode {
        case .todayOverview:
            doneTasks = CadenceTaskQuerySupport.completedTodayTasks(from: allTasks, todayKey: todayKey)
        }
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

    /// **The past-due summaries count as content.** They are the one thing on this page not drawn
    /// from the task buckets: `CadenceTodayOverdueSummarySupport` filters *projects* and *columns*
    /// by their own `dueDate` and never looks at a task. So a day with nothing planned but three
    /// lists whose deadlines have gone by read "Nothing planned for today" directly under three
    /// cards saying otherwise (T-592).
    ///
    /// The rollover banner needs no clause of its own here, unlike iOS's: while it is up the
    /// grouped list is deliberately missing the rows it is offering, but those rows are
    /// `overdoTasks` and this already counts them.
    ///
    /// iOS guards the same way and says the same thing — `iOSTodayTaskSections.isEmpty`.
    func isEmptyState(for mode: TasksPanelMode) -> Bool {
        switch mode {
        case .todayOverview:
            return overdue.isEmpty &&
            overdoTasks.isEmpty &&
            dueTodayTasks.isEmpty &&
            doTodayTasks.isEmpty &&
            doneTasks.isEmpty &&
            overdueListSummaries.isEmpty &&
            overdueSectionSummaries.isEmpty
        }
    }

    private func uniqueTasks(from tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
    }
}
#endif
