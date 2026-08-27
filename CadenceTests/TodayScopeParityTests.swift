import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Today's task scope, measured against the two implementations that draw it.
///
/// `CadenceTaskQuerySupport.activeTodayTasks` is the whole of iPad Today; macOS Today is built
/// from `TasksPanelDerivedState`'s four buckets. The shared helper was missing the `scheduledDate
/// < todayKey` clause entirely, so a task planned for yesterday and never finished appeared in
/// macOS's "Past Do" section and *nowhere at all* on iPad — same account, same moment.
@MainActor
struct TodayScopeParityTests {
    private let todayKey = "2026-08-11"

    private func makeTask(
        _ title: String,
        due: String = "",
        scheduled: String = "",
        status: TaskStatus = .todo
    ) -> AppTask {
        let task = AppTask(title: title)
        task.dueDate = due
        task.scheduledDate = scheduled
        task.status = status
        return task
    }

    /// One task per bucket, plus the tasks that must stay out.
    private func seededTasks() -> [AppTask] {
        [
            makeTask("Do today", scheduled: todayKey),
            makeTask("Due today", due: todayKey),
            makeTask("Past do", scheduled: "2026-08-10"),
            makeTask("Past due", due: "2026-08-09"),
            makeTask("Later", due: "2026-08-25", scheduled: "2026-08-20"),
            makeTask("No dates"),
            makeTask("Finished past do", scheduled: "2026-08-10", status: .done),
            makeTask("Cancelled past do", scheduled: "2026-08-10", status: .cancelled)
        ]
    }

    @Test func sharedTodayScopeIncludesPastDoTasks() {
        let tasks = seededTasks()

        let titles = Set(
            CadenceTaskQuerySupport
                .activeTodayTasks(from: tasks, todayKey: todayKey, sortMode: .listOrder)
                .map(\.title)
        )

        #expect(titles == ["Do today", "Due today", "Past do", "Past due"])
    }

    #if os(macOS)
    /// The parity assertion proper: the shared helper and macOS's derived state must agree on the
    /// exact id set, not merely overlap.
    @Test func sharedTodayScopeMatchesMacTodayScope() {
        let tasks = seededTasks()

        let shared = Set(
            CadenceTaskQuerySupport
                .activeTodayTasks(from: tasks, todayKey: todayKey, sortMode: .listOrder)
                .map(\.id)
        )

        let derived = TasksPanelDerivedState(
            allTasks: tasks,
            areas: [],
            projects: [],
            mode: .todayOverview,
            todayKey: todayKey,
            sortField: .date,
            sortDirection: .ascending
        )

        #expect(shared == Set(derived.todayEligibleTasks.map(\.id)))
    }
    #endif

    /// Today's groups are Overdue and then the day's lists (T-305). These tasks have no list, so
    /// they all land in Inbox — and the date distinctions that used to be three separate headings
    /// survive as the *order* inside that one group: past do, then due today, then do today.
    @Test func theDaysNonOverdueWorkFallsIntoItsListsGroupInTodayRankOrder() {
        let tasks = CadenceTaskQuerySupport.activeTodayTasks(
            from: seededTasks(),
            todayKey: todayKey,
            sortMode: .listOrder
        )

        let groups = CadenceTaskQuerySupport.todayGroups(from: tasks, todayKey: todayKey, contexts: [])

        #expect(groups.map(\.title) == ["Overdue", "Inbox"])
        #expect(groups.map { $0.tasks.map(\.title) } == [
            ["Past due"],
            ["Past do", "Due today", "Do today"],
        ])
    }

    /// A due date outranks a do date in both implementations, so a task that is both past due and
    /// past do is counted once, under the due bucket.
    @Test func aTaskThatIsBothPastDueAndPastDoIsGroupedOnceUnderOverdue() {
        let both = makeTask("Both", due: "2026-08-09", scheduled: "2026-08-10")
        let tasks = CadenceTaskQuerySupport.activeTodayTasks(
            from: [both],
            todayKey: todayKey,
            sortMode: .listOrder
        )

        #expect(tasks.count == 1)

        let groups = CadenceTaskQuerySupport.todayGroups(from: tasks, todayKey: todayKey, contexts: [])
        #expect(groups.map(\.identity) == [.overdue])
    }

    /// The flat sort still ranks the day past due → past do → due today → do today. Since T-305 it
    /// is the *only* thing that says so — Today's headings are lists now, so this rank is what
    /// orders the rows inside each of them.
    @Test func flatTodaySortOrderMatchesTheGroupOrder() {
        let sorted = CadenceTaskQuerySupport.activeTodayTasks(
            from: seededTasks(),
            todayKey: todayKey,
            sortMode: .listOrder
        )

        #expect(sorted.map(\.title) == ["Past due", "Past do", "Due today", "Do today"])
    }
}
