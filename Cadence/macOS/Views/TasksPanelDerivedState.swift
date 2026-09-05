#if os(macOS)
import SwiftUI

struct TasksPanelDerivedState {
    let overdue: [AppTask]
    let dueTodayTasks: [AppTask]
    let doTodayTasks: [AppTask]
    let overdoTasks: [AppTask]
    let doneTasks: [AppTask]

    /// `areas` and `projects` were parameters here, read by nothing but the two past-due summary
    /// bands — a *column*'s due date lives in `sectionConfigsRaw` on the list, so no query over
    /// `AppTask` can find one. The bands are gone from macOS Today with the Overdue section, and
    /// the parameters went with them rather than being left to be threaded in by the next caller.
    init(allTasks: [AppTask], todayKey: String) {
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
        // The `switch mode` that used to wrap this line went with the enum itself (T-564(a)).
        doneTasks = CadenceTaskQuerySupport.completedTodayTasks(from: allTasks, todayKey: todayKey)
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

    /// **Two clauses fewer than T-592 left here, and the reason is that the thing they guarded is
    /// gone.** They counted the past-due list and column summaries as content, because those were
    /// the one thing on this page not drawn from the task buckets — so a day with nothing planned
    /// but three lists whose deadlines had gone by read "Nothing planned for today" directly under
    /// three cards saying otherwise. macOS Today no longer draws those cards, so the day is empty
    /// exactly when its task buckets are. **iOS still draws them and still guards on them** —
    /// `iOSTodayTaskSections.isEmpty` keeps its clause, and the two Todays disagree here until that
    /// band is decided for the phone too.
    ///
    /// The rollover banner needs no clause of its own, unlike iOS's: while it is up the grouped
    /// list is deliberately missing the rows it is offering, but those rows are `overdoTasks` and
    /// this already counts them.
    ///
    /// A property rather than `isEmptyState(for:)`: the `TasksPanelMode` it switched over had one
    /// case and is gone (T-564(a)).
    var isEmptyState: Bool {
        overdue.isEmpty &&
        overdoTasks.isEmpty &&
        dueTodayTasks.isEmpty &&
        doTodayTasks.isEmpty &&
        doneTasks.isEmpty
    }

    private func uniqueTasks(from tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
    }
}
#endif
