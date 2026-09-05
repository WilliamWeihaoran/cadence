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
            todayKey: todayKey
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

        let groups = CadenceTaskQuerySupport.todayListGroups(from: tasks, contexts: [])

        // One group, because every one of these tasks is unfiled. The past-due row used to be lifted
        // into an `Overdue` group ahead of Inbox; it is in Inbox with the rest of the day now, and
        // the rank still puts it first inside it.
        #expect(groups.map(\.title) == ["Inbox"])
        #expect(groups.map { $0.tasks.map(\.title) } == [
            ["Past due", "Past do", "Due today", "Do today"],
        ])
    }

    /// A due date outranks a do date in both implementations, so a task that is both past due and
    /// past do appears once. With Today grouped by list only, "once" is a claim about the *groups*
    /// rather than about which date bucket claimed it.
    @Test func aTaskThatIsBothPastDueAndPastDoIsGroupedOnce() {
        let both = makeTask("Both", due: "2026-08-09", scheduled: "2026-08-10")
        let tasks = CadenceTaskQuerySupport.activeTodayTasks(
            from: [both],
            todayKey: todayKey,
            sortMode: .listOrder
        )

        #expect(tasks.count == 1)

        let groups = CadenceTaskQuerySupport.todayListGroups(from: tasks, contexts: [])
        #expect(groups.map(\.listKey) == ["inbox"])
        #expect(groups.flatMap { $0.tasks.map(\.id) } == [both.id])
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

    // MARK: - The widget draws the same day (T-353)

    /// `seededTasks` plus the pairs that make the two definitions disagree in more than one way,
    /// so the id-set parity below is a real question rather than four easy cases.
    private func parityFixture() -> [AppTask] {
        seededTasks() + [
            makeTask("Past due and past do", due: "2026-08-09", scheduled: "2026-08-10"),
            makeTask("Due today and past do", due: todayKey, scheduled: "2026-08-10"),
            makeTask("Past do and due later", due: "2026-08-25", scheduled: "2026-08-10"),
            makeTask("Do today and due later", due: "2026-08-25", scheduled: todayKey),
            makeTask("Planned for later", scheduled: "2026-08-20")
        ]
    }

    /// **The exact defect.** A task planned for a past day with **no due date** is on the app's
    /// Today page; the widget kept a narrower copy of the scope with no past-do branch, so it was
    /// missing from the Today widget and from the Calendar widget's "Next up", which is `.first`
    /// of this same picker.
    @Test func pastDoWorkWithNoDueDateIsOnTodayInBothTheAppAndTheWidget() throws {
        let pastDo = makeTask("Past do, no due date", scheduled: "2026-08-10")
        let tasks = [pastDo, makeTask("Later", due: "2026-08-25"), makeTask("No dates")]

        let appToday = CadenceTaskQuerySupport
            .activeTodayTasks(from: tasks, todayKey: todayKey, sortMode: .listOrder)
        let widgetToday = CadenceTodayWidgetSupport.todayTasks(from: tasks, todayKey: todayKey)

        // Non-vacuity: the fixture really does put exactly this one task on the day, so neither
        // side can pass by returning nothing.
        #expect(appToday.map(\.id) == [pastDo.id])
        #expect(widgetToday.map(\.id) == [pastDo.id])
    }

    /// **The general form, driven from one fixture set.** Both scopes are asked the same
    /// question and must name the same ids, so an edit to either side cannot drift from the other
    /// without failing here.
    @Test func theWidgetTodayScopeIsExactlyTheAppTodayScope() {
        let tasks = parityFixture()

        let appIDs = Set(
            CadenceTaskQuerySupport
                .activeTodayTasks(from: tasks, todayKey: todayKey, sortMode: .listOrder)
                .map(\.id)
        )
        let widgetIDs = Set(CadenceTodayWidgetSupport.todayTasks(from: tasks, todayKey: todayKey).map(\.id))

        // Non-vacuity: 8 of the 13 fixture tasks are today's work, and 5 are not — a scope that
        // admitted everything or nothing would fail this line before it reached the comparison.
        #expect(appIDs.count == 8)
        #expect(appIDs.count < tasks.count)
        #expect(widgetIDs == appIDs)
    }

    /// The rank travelled with the scope: the widget orders the day past due → past do → due
    /// today → do today, the order `flatTodaySortOrderMatchesTheGroupOrder` pins for the app. Its
    /// own priority tie-break sits *below* that rank and is untouched — every task here has the
    /// same priority so the rank is what is being read.
    @Test func theWidgetOrdersTodayByTheSharedRank() {
        let ordered = CadenceTodayWidgetSupport.todayTasks(from: seededTasks(), todayKey: todayKey)

        #expect(ordered.map(\.title) == ["Past due", "Past do", "Due today", "Do today"])
        #expect(
            ordered.map { CadenceTaskQuerySupport.todayRank($0, todayKey: todayKey) } == [0, 1, 2, 3]
        )
    }

    /// The widget's *store query* has to hand over every row its scope admits, and it is the one
    /// place the rule cannot be a function call — a `#Predicate` compiles to a store query. Fixing
    /// the in-memory scope alone would have left the shipping widget still missing the task,
    /// because the row never arrived. Same fixtures, once through the query and once through every
    /// row in the store; the ids must match.
    @Test func theWidgetsStoreQueryKeepsEveryTaskItsTodayScopeAdmits() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        for task in parityFixture() {
            modelContext.insert(task)
        }
        try modelContext.save()

        let everyRow = try modelContext.fetch(FetchDescriptor<AppTask>())
        let queried = try modelContext.fetch(CadenceTodayWidgetSupport.todayCandidateFetchDescriptor())

        let fromEveryRow = Set(CadenceTodayWidgetSupport.todayTasks(from: everyRow, todayKey: todayKey).map(\.id))
        let fromQuery = Set(CadenceTodayWidgetSupport.todayTasks(from: queried, todayKey: todayKey).map(\.id))

        // Non-vacuity: the store really was seeded, and the day really has work on it.
        #expect(everyRow.count == 13)
        #expect(fromEveryRow.count == 8)
        #expect(fromQuery == fromEveryRow)
    }

    /// **The second wrong widget.** The Calendar widget's "Next up" is `.first` of the Today
    /// widget's picker, so the narrower scope cost two surfaces from one definition: the Calendar
    /// widget could report nothing urgent while the app's Today page had work on it. Driven
    /// through `CadenceCalendarWidgetSupport` rather than asserted about it, so the reuse is
    /// exercised and not just described.
    @Test func theCalendarWidgetNextUpAlsoNamesPastDoWork() throws {
        let today = try #require(DateFormatters.date(from: todayKey))
        let pastDo = makeTask("Past do, no due date", scheduled: "2026-08-10")
        let later = makeTask("Later", scheduled: "2026-08-20")

        let snapshot = CadenceCalendarWidgetSupport.snapshot(
            from: [pastDo, later],
            today: today,
            dayCount: 3
        )

        #expect(snapshot.upcomingTitle == "Past do, no due date")
        // No deadline — "Next up" names the task, and the widget must not invent a due date for it.
        #expect(snapshot.upcomingDueDate == "")
        // Non-vacuity: the fixture is live on this day, and `later` really is out of Today's scope,
        // so `.first` had a two-task list to be wrong about.
        #expect(snapshot.state == .ready)
        #expect(CadenceTodayWidgetSupport.todayTasks(from: [pastDo, later], todayKey: todayKey).count == 1)
    }

    /// The snapshot's three badges partition the rows it draws. A past-do task used to fall
    /// through all three tests, so a widget listing it could read "0 overdue, 0 due, 0 planned"
    /// beside the row it was showing.
    @Test func theWidgetSnapshotBadgesAccountForEveryTaskItCounts() {
        let snapshot = CadenceTodayWidgetSupport.snapshot(
            from: seededTasks(),
            todayKey: todayKey,
            limit: 10
        )

        #expect(snapshot.totalCount == 4)
        #expect(snapshot.overdueCount == 1)
        #expect(snapshot.dueTodayCount == 1)
        // Past do and do today: yesterday's plan is still planned work.
        #expect(snapshot.scheduledTodayCount == 2)
        #expect(snapshot.overdueCount + snapshot.dueTodayCount + snapshot.scheduledTodayCount == snapshot.totalCount)
        #expect(snapshot.tasks.map(\.title) == ["Past due", "Past do", "Due today", "Do today"])
    }
}
