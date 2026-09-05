import Foundation
import SwiftData
import Testing
@testable import Cadence

/// "Is this task overdue" existed six times, and three of the copies left out the `isDone` half,
/// so whether a finished task with a past due date rendered red depended on which screen you were
/// on. `AppTask.isOverdue(todayKey:)` is now the one answer; these tests pin it and pin the
/// spellings that forward to it, because a forwarder that quietly stops forwarding is exactly how
/// the six copies happened in the first place.
@MainActor
struct TaskOverdueSupportTests {
    private let todayKey = "2026-08-11"

    private func task(due: String, status: TaskStatus = .todo) -> AppTask {
        let task = AppTask(title: "T")
        task.dueDate = due
        task.status = status
        return task
    }

    @Test func aTaskIsOverdueOnlyWhenItHasAPastDeadlineAndIsNotFinished() {
        #expect(task(due: "2026-08-10").isOverdue(todayKey: todayKey))
        #expect(task(due: "2026-08-11").isOverdue(todayKey: todayKey) == false)
        #expect(task(due: "2026-08-12").isOverdue(todayKey: todayKey) == false)

        // No deadline cannot be a missed deadline.
        #expect(task(due: "").isOverdue(todayKey: todayKey) == false)

        // The half three copies of this predicate forgot.
        #expect(task(due: "2026-08-10", status: .done).isOverdue(todayKey: todayKey) == false)

        // Cancelled is a different status from done, and no copy has ever excluded it. Pinned so
        // the decision is a decision rather than an accident of whichever copy was consulted.
        #expect(task(due: "2026-08-10", status: .cancelled).isOverdue(todayKey: todayKey))
    }

    /// The deadline-only spelling is for callers holding a date key rather than a task
    /// (`CadenceDueUrgency`, which takes `isDone` separately). It must not answer the `isDone`
    /// half, and it must agree with the task-level one on everything else.
    @Test func theDeadlineOnlySpellingIsTheSameComparisonWithoutTheDoneGuard() {
        #expect(AppTask.isDueDateOverdue("2026-08-10", todayKey: todayKey))
        #expect(AppTask.isDueDateOverdue("2026-08-11", todayKey: todayKey) == false)
        #expect(AppTask.isDueDateOverdue("", todayKey: todayKey) == false)

        for key in ["", "2026-08-10", "2026-08-11", "2026-08-12"] {
            #expect(
                CadenceFocusSupport.isOverdue(dueDateKey: key, todayKey: todayKey)
                    == AppTask.isDueDateOverdue(key, todayKey: todayKey),
                "CadenceFocusSupport.isOverdue stopped forwarding for \(key)"
            )
            let urgencyIsOverdue =
                CadenceDueUrgency.evaluate(dueDateKey: key, isDone: false, todayKey: todayKey) == .overdue
            #expect(urgencyIsOverdue == AppTask.isDueDateOverdue(key, todayKey: todayKey))
        }
    }

    #if os(macOS)
    /// The kanban card is the surface every other macOS task row now shares its answer with —
    /// `MacTaskRow` carried a byte-identical re-implementation of all three of these.
    @Test func theKanbanCardPredicatesForwardToTheModel() {
        let overdue = task(due: DateFormatters.dateKey(from: Date(timeIntervalSinceNow: -86_400)))
        let done = task(due: DateFormatters.dateKey(from: Date(timeIntervalSinceNow: -86_400)), status: .done)

        #expect(KanbanCardComputedSupport.isOverdue(task: overdue))
        #expect(KanbanCardComputedSupport.isOverdue(task: done) == false)
        #expect(overdue.isOverdue(todayKey: DateFormatters.todayKey()))
    }
    #endif

    /// A completed task with a past due date is not overdue on the goal surfaces either. This one
    /// used to parse both sides to `Date` and compare `Date`s — the only overdue test in the app
    /// that could reach a different verdict than the string comparison every other surface uses.
    @Test func goalOverdueCountsUseTheSameTaskPredicate() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Shipping", context: context)
        let goal = Goal(title: "Ship it", context: context)
        let link = GoalListLink(goal: goal, area: area)

        let openTask = task(due: "2026-08-01")
        openTask.title = "Open and late"
        openTask.area = area
        openTask.context = context
        let finishedTask = task(due: "2026-08-01", status: .done)
        finishedTask.title = "Late but finished"
        finishedTask.area = area
        finishedTask.context = context

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(goal)
        modelContext.insert(link)
        modelContext.insert(openTask)
        modelContext.insert(finishedTask)
        try modelContext.save()

        let now = try #require(DateFormatters.date(from: todayKey))
        #expect(GoalContributionResolver.overdueTasks(for: goal, now: now).map(\.title) == ["Open and late"])
        #expect(
            GoalContributionResolver.overdueTasks(for: goal, now: now).allSatisfy { $0.isOverdue(todayKey: todayKey) }
        )
    }

    #if os(macOS)
    /// The count in a list-detail group header and the count in the same group on Today have to be
    /// the same number. `ListDetailComponents` used to carry its own bodies for both of these, and
    /// neither excluded completed tasks — so the same list reported two different overdue counts
    /// depending on which screen you opened it from.
    ///
    /// **And the second figure is the group's size, not the remainder.** `openCount` was
    /// `regularCount` and subtracted `overdueCount`, so this fixture — three tasks, one finished,
    /// one open and late, one open and on time — reported `1`. The user hit the degenerate case:
    /// a header reading `0 tasks` over three visible rows, because every open row under it was late.
    /// Two independent questions about the same rows, and each true on its own.
    @Test func groupHeaderCountsIgnoreCompletedTasks() {
        let openLate = task(due: "2026-08-01")
        let doneLate = task(due: "2026-08-01", status: .done)
        let openLater = task(due: "2026-09-01")
        let tasks = [openLate, doneLate, openLater]

        #expect(TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey) == 1)
        #expect(TasksPanelSupport.openCount(in: tasks) == 2)
        #expect(TasksPanelSupport.overdueCount(in: [doneLate], todayKey: todayKey) == nil)
    }
    #endif
}
