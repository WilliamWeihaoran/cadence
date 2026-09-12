import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1055, measured: what a renumber over a visible slice does to the rows outside it.**
///
/// `CadenceOrderCommit.commit`'s own doc says `ordered` "must be the *whole* collection the `order`
/// sequence spans rather than the visible slice". Every production caller hands it a slice: Today
/// hands one `CadenceTaskQuerySupport.todayListGroups` group, All Tasks / Inbox hands one section,
/// a list's Tasks tab hands `CadenceTaskQuerySupport.openTasks(from: tasks)`, and both kanban card
/// drops hand one column. The ticket predicted "rows quietly interleaving between hidden ones" and
/// named the blocker as `order` being "allocated per container", so that a cross-list surface has
/// no whole sequence to renumber.
///
/// These tests measure that instead of arguing it, and the first one is why the rest read the way
/// they do.
@MainActor
struct CadenceRowReorderSliceSpanTests {

    private func container() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    private func task(
        _ title: String,
        order: Int,
        project: Project? = nil,
        scheduled: String = "",
        done: Bool = false,
        in modelContext: ModelContext
    ) -> AppTask {
        let task = AppTask(title: title)
        task.order = order
        task.project = project
        task.scheduledDate = scheduled
        task.status = done ? .done : .todo
        modelContext.insert(task)
        return task
    }

    private func customOrder(_ tasks: [AppTask]) -> [String] {
        tasks.taskSorted(by: .custom, direction: .ascending).map(\.title)
    }

    // MARK: - The baseline the ticket got wrong

    /// **MEASURED.** The app's primary creation path never allocates an `order` at all, so the
    /// ticket's stated blocker — "`order` is allocated per container (`nextTaskOrder(in:)` maxes
    /// over one list)" — is not what the shipped app does on the path that makes most tasks.
    ///
    /// `TaskCreationService.insertion(from:into:)` writes eight fields of the new `AppTask` and
    /// applies its container, and `order` is not among them, so every task the composer creates keeps `AppTask.order`'s
    /// declared default of `0`, in every container. `CadenceTaskQuerySupport.makeTask` — the *other*
    /// creation path, used by the quick-capture surfaces — allocates `nextTaskOrder(in: allTasks)`,
    /// which is the max over **every task in the app** and not over one list.
    ///
    /// So the app has three rules at once: no allocation (the composer), a global allocation
    /// (quick capture and `CadenceWidgetIntents.captureTask`), and a per-container allocation
    /// (`CadenceTaskMutationSupport.nextContainerOrder`, on the move and duplicate paths only).
    /// That is the fact any renumber-the-whole-sequence fix would have to be built on, and it is
    /// not the one the ticket recorded.
    @Test func thecomposerPathNeverAllocatesAnOrderWhileQuickCaptureAllocatesGlobally() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let project = Project(name: "Work")
        modelContext.insert(area)
        modelContext.insert(project)

        // An existing task carrying a high order, so a per-container or global allocation would be
        // visible as anything other than 0.
        _ = task("Existing", order: 40, project: project, in: modelContext)
        try modelContext.save()

        let service = TaskCreationService(areas: [area], projects: [project])
        let containers: [TaskContainerSelection] = [.inbox, .area(area.id), .project(project.id)]
        var created: [AppTask] = []
        for (index, selection) in containers.enumerated() {
            let draft = TaskCreationDraft(
                title: "Composed \(index)",
                notes: "",
                priority: .none,
                container: selection,
                sectionName: TaskSectionDefaults.defaultName,
                dueDateKey: "",
                scheduledDateKey: "",
                subtaskTitles: [],
                tags: []
            )
            created.append(try #require(try service.createTask(from: draft, into: modelContext)))
        }

        #expect(created.map(\.order) == [0, 0, 0], "the composer has started allocating an order")

        // The other creation path, over the same store, allocates the global maximum plus one.
        let captured = try #require(
            CadenceTaskQuerySupport.makeTask(
                title: "Captured",
                allTasks: try modelContext.fetch(FetchDescriptor<AppTask>())
            )
        )
        #expect(captured.order == 41, "quick capture no longer maxes over every task in the app")
    }

    // MARK: - Do orders collide?

    /// **MEASURED.** Yes, and inside one container. A drop on a list's Tasks tab renumbers
    /// `openTasks(from: tasks)` from 0, and the list's finished tasks are not in that array, so they
    /// keep the orders the renumber has just handed out again.
    @Test func adropOnAListsTasksTabHandsItsFinishedTasksOrdersTheOpenOnesNowAlsoHold() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Work")
        modelContext.insert(project)

        let done = [
            task("Done A", order: 0, project: project, done: true, in: modelContext),
            task("Done B", order: 1, project: project, done: true, in: modelContext)
        ]
        let open = [
            task("Open A", order: 10, project: project, in: modelContext),
            task("Open B", order: 11, project: project, in: modelContext),
            task("Open C", order: 12, project: project, in: modelContext)
        ]
        try modelContext.save()

        let all = done + open
        #expect(Set(all.map(\.order)).count == 5, "non-vacuity: nothing collides before the drop")

        // Exactly `ListTasksView.reorderTask`: the tab hands over its open tasks and nothing else.
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: try #require(open.last).id,
                targetID: try #require(open.first).id,
                scopeTasks: CadenceTaskQuerySupport.openTasks(from: all),
                modelContext: modelContext
            )
        )

        #expect(open.map(\.order) == [1, 2, 0], "the open slice was not renumbered from 0")
        #expect(done.map(\.order) == [0, 1], "a finished task was written by a drop that never named it")

        let collisions = Dictionary(grouping: all, by: \.order).filter { $0.value.count > 1 }
        #expect(collisions.keys.sorted() == [0, 1])
        #expect(collisions[0]?.count == 2)
        #expect(collisions[1]?.count == 2)
    }

    /// **MEASURED.** The renumber writes no row outside the slice — which is both why the collision
    /// happens and why it is bounded. A task in another list, and a task in the same list held back
    /// by the tab's filter, come out of the commit holding the order they went in with.
    @Test func therenumberWritesNoRowOutsideTheSliceItWasHanded() throws {
        let modelContext = ModelContext(try container())
        let work = Project(name: "Work")
        let home = Project(name: "Home")
        modelContext.insert(work)
        modelContext.insert(home)

        let outsiders = [
            task("Other list", order: 7, project: home, in: modelContext),
            task("Same list, finished", order: 8, project: work, done: true, in: modelContext)
        ]
        let slice = [
            task("Slice A", order: 3, project: work, in: modelContext),
            task("Slice B", order: 4, project: work, in: modelContext)
        ]
        try modelContext.save()

        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: try #require(slice.last).id,
                targetID: try #require(slice.first).id,
                scopeTasks: slice,
                modelContext: modelContext
            )
        )

        #expect(slice.map(\.order) == [1, 0])
        #expect(outsiders.map(\.order) == [7, 8], "a row outside the slice was renumbered")
    }

    // MARK: - Does a later renumber undo an earlier one?

    /// **MEASURED.** Yes, and it does not need the two screens to be *sorted* differently — only
    /// to *slice* differently.
    ///
    /// The user arranges four rows on the list's Tasks tab, dragging Delta to the top. Then, on
    /// Today, they drag Charlie above Bravo — the only two rows that list puts on the day, and a
    /// one-place move on the tab. Today's group is a two-row slice, so it renumbers to `0, 1` over
    /// the orders the tab arrangement had just given to Delta and Alpha.
    ///
    /// Two things the user did not ask for come out of that. **Delta, which they deliberately
    /// dragged to the top and then never touched, is no longer at the top.** And **Charlie, which
    /// they asked to move up one place, is now first** — it travelled three places, past two rows
    /// that were not in the slice and not on the screen.
    @Test func asecondDropOnASmallerSliceOverwritesTheArrangementTheFirstOneMade() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Work")
        modelContext.insert(project)
        let todayKey = DateFormatters.ymd.string(from: Date())

        // Created Alpha, Bravo, Charlie, Delta, so `createdAt` — the tie-break every collision
        // below falls through to — is the identity permutation and every reading of it is legible.
        let alpha = task("Alpha", order: 0, project: project, in: modelContext)
        let bravo = task("Bravo", order: 1, project: project, scheduled: todayKey, in: modelContext)
        let charlie = task("Charlie", order: 2, project: project, scheduled: todayKey, in: modelContext)
        let delta = task("Delta", order: 3, project: project, in: modelContext)
        let all = [alpha, bravo, charlie, delta]
        for (index, item) in all.enumerated() {
            item.createdAt = Date(timeIntervalSince1970: 1_000 + Double(index))
        }
        try modelContext.save()

        // Drop 1, on the list's own Tasks tab: the user drags Delta to the top.
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: delta.id,
                targetID: alpha.id,
                scopeTasks: CadenceTaskQuerySupport.openTasks(from: all),
                modelContext: modelContext
            )
        )
        #expect(all.map(\.order) == [1, 2, 3, 0])
        #expect(customOrder(all) == ["Delta", "Alpha", "Bravo", "Charlie"])
        #expect(Set(all.map(\.order)).count == 4, "non-vacuity: the first drop left a total order")

        // Drop 2, on Today. The slice is the real one — one `CadenceTaskQuerySupport
        // .todayListGroups` group, which holds only the two rows this list puts on the day.
        let todaySlice = try #require(
            CadenceTaskQuerySupport.todayListGroups(
                from: all.filter { $0.scheduledDate == todayKey },
                contexts: []
            ).first
        ).tasks
        #expect(Set(todaySlice.map(\.title)) == ["Bravo", "Charlie"], "the Today slice is not the two scheduled rows")

        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: charlie.id,
                targetID: bravo.id,
                scopeTasks: todaySlice,
                modelContext: modelContext
            )
        )

        // On Today the gesture did exactly what was asked.
        #expect(customOrder([bravo, charlie]) == ["Charlie", "Bravo"])

        // Charlie and Bravo took 0 and 1 — the orders Delta and Alpha were holding.
        #expect(charlie.order == 0)
        #expect(bravo.order == 1)
        #expect(delta.order == 0)
        #expect(alpha.order == 1)

        // And this is what the Tasks tab shows now. Every row has moved, from a drag made on a
        // different screen over two of them.
        #expect(customOrder(all) == ["Charlie", "Delta", "Alpha", "Bravo"])
        #expect(customOrder(all).first == "Charlie", "the one-place move on Today travelled one place")
        #expect(customOrder(all).first != "Delta", "the row the user dragged to the top is still at the top")
    }

    // MARK: - Can the user see it?

    /// **MEASURED.** Yes, on a screen the drag was not made on. Nothing is dragged on the list's
    /// Tasks tab at all here: the user's only gesture is on Today, and it moves a row on the tab
    /// that Today never displayed.
    ///
    /// This is the answer to the ticket's "confirmed by reading, not observed in use", and it is
    /// sharper than the "quiet interleaving" it predicted: the interleave is deterministic, but the
    /// *displacement* is not quiet — an untouched row changes places with another untouched row.
    @Test func atodayDropMovesARowOnTheListsTasksTabThatTodayNeverShowed() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Work")
        modelContext.insert(project)
        let todayKey = DateFormatters.ymd.string(from: Date())

        let rows = [
            task("Unscheduled first", order: 0, project: project, in: modelContext),
            task("Unscheduled second", order: 1, project: project, in: modelContext),
            task("Today early", order: 2, project: project, scheduled: todayKey, in: modelContext),
            task("Today late", order: 3, project: project, scheduled: todayKey, in: modelContext)
        ]
        for (index, item) in rows.enumerated() {
            item.createdAt = Date(timeIntervalSince1970: 2_000 + Double(index))
        }
        try modelContext.save()

        let before = customOrder(rows)
        #expect(before == ["Unscheduled first", "Unscheduled second", "Today early", "Today late"])

        // One gesture, on Today: drag "Today late" above "Today early" inside their list group.
        let todaySlice = try #require(
            CadenceTaskQuerySupport.todayListGroups(
                from: rows.filter { $0.scheduledDate == todayKey },
                contexts: []
            ).first
        ).tasks
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: try #require(rows.last).id,
                targetID: rows[2].id,
                scopeTasks: todaySlice,
                modelContext: modelContext
            )
        )

        // On Today the gesture did exactly what was asked.
        #expect(customOrder(Array(rows[2...])) == ["Today late", "Today early"])

        // On the list's Tasks tab, which the user was not looking at, the sequence is different.
        // "Today late" was renumbered to 0 and now ties with "Unscheduled first"; "Today early"
        // was renumbered to 1 and now ties with "Unscheduled second". Both ties are resolved by
        // `createdAt`, so "Unscheduled second" — a row the user never dragged and which Today
        // never displayed — has been pushed from second place to third.
        let after = customOrder(rows)
        #expect(after == ["Unscheduled first", "Today late", "Unscheduled second", "Today early"])
        #expect(after != before)
        #expect(before.firstIndex(of: "Unscheduled second") == 1)
        #expect(
            after.firstIndex(of: "Unscheduled second") == 2,
            "a row the user never dragged, and which Today never displayed, did not move"
        )
    }

    /// **MEASURED.** The kanban card drop has the same shape through a different commit. One
    /// column's cards are renumbered from 0 and a card in another column of the same board keeps
    /// the order it holds, so the board's two columns now number from the same base.
    @Test func akanbanCardDropRenumbersOneColumnAndCollidesWithTheNext() throws {
        let modelContext = ModelContext(try container())
        let work = Project(name: "Work")
        let home = Project(name: "Home")
        modelContext.insert(work)
        modelContext.insert(home)

        let other = [
            task("Home A", order: 0, project: home, in: modelContext),
            task("Home B", order: 1, project: home, in: modelContext)
        ]
        let column = [
            task("Work A", order: 5, project: work, in: modelContext),
            task("Work B", order: 6, project: work, in: modelContext)
        ]
        try modelContext.save()

        let movingCard = try #require(column.last)
        let landingCard = try #require(column.first)
        #expect(
            KanbanBoardSupport.reorder(
                column,
                moving: movingCard,
                before: landingCard,
                in: modelContext
            )
        )

        #expect(column.map(\.order) == [1, 0])
        #expect(other.map(\.order) == [0, 1])
        let board = other + column
        let collisions = Dictionary(grouping: board, by: \.order).filter { $0.value.count > 1 }
        #expect(collisions.keys.sorted() == [0, 1], "the two columns no longer number from the same base")
    }

    // MARK: - T-1119: a drag reorders within its own list only

    /// **The answer to the question this file's measurements raised**, asked of the repository
    /// owner and answered verbatim: *"Reorder within its own list only."*
    ///
    /// The same shape as `atodayDropMovesARowOnTheListsTasksTabThatTodayNeverShowed` above, one
    /// list further out: All Tasks with the grouping chip on **By Date**, so the Do Today section
    /// is drawn from two lists at once and a drag inside it names a row in each. Under the
    /// cross-list renumber this section was renumbered whole, so the other list's row took a new
    /// `order` from a drag nobody made in it — and on that list's own Tasks tab, a third row that
    /// was in neither list's section changed places.
    ///
    /// What is asserted is both halves of the decision: the dragged row moves among its **own**
    /// list's rows, and the other list comes out of the drop holding exactly what it went in with.
    @Test func acrossListDropRenumbersTheDraggedRowsOwnListOnly() throws {
        let modelContext = ModelContext(try container())
        let work = Project(name: "Work")
        let home = Project(name: "Home")
        modelContext.insert(work)
        modelContext.insert(home)
        let todayKey = DateFormatters.ymd.string(from: Date())

        let workFirst = task("Work first", order: 0, project: work, in: modelContext)
        let workSecond = task("Work second", order: 1, project: work, in: modelContext)
        let workToday = task("Work today", order: 2, project: work, scheduled: todayKey, in: modelContext)
        let homeEarly = task("Home early", order: 3, project: home, scheduled: todayKey, in: modelContext)
        let homeLate = task("Home late", order: 4, project: home, scheduled: todayKey, in: modelContext)

        // `createdAt` is the tie-break every collision falls through to, and it is set so that a
        // collision is *visible*: "Work today" is older than "Work second", so if a cross-list
        // renumber ever gives it "Work second"'s order again, it overtakes it on the Work tab.
        workFirst.createdAt = Date(timeIntervalSince1970: 3_000)
        workToday.createdAt = Date(timeIntervalSince1970: 3_001)
        workSecond.createdAt = Date(timeIntervalSince1970: 3_002)
        homeEarly.createdAt = Date(timeIntervalSince1970: 3_003)
        homeLate.createdAt = Date(timeIntervalSince1970: 3_004)
        let all = [workFirst, workSecond, workToday, homeEarly, homeLate]
        try modelContext.save()

        let workRows = [workFirst, workSecond, workToday]
        let workTabBefore = customOrder(workRows)
        #expect(workTabBefore == ["Work first", "Work second", "Work today"])

        // The real All Tasks slice: `TasksListView.sections(from:)` under `.byDate` is
        // `CadenceTaskQuerySupport.dateDisplayGroups`, and the Do Today group holds both lists'
        // rows for the day.
        let section = try #require(
            CadenceTaskQuerySupport.dateDisplayGroups(from: all, todayKey: todayKey)
                .first { $0.id == "do-today" }
        ).tasks
        #expect(Set(section.map(\.title)) == ["Work today", "Home early", "Home late"])
        #expect(
            Set(section.compactMap { $0.project?.name }) == ["Work", "Home"],
            "non-vacuity: the section this drag is made in does not cross lists"
        )

        // One drag, inside that section: Home late above Work today.
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: homeLate.id,
                targetID: workToday.id,
                scopeTasks: section,
                modelContext: modelContext
            )
        )

        // Its own list took the move: the two Home rows swapped, which is the whole of what a drag
        // over a row of another list can mean.
        #expect(homeLate.order == 0)
        #expect(homeEarly.order == 1)
        #expect(customOrder([homeEarly, homeLate]) == ["Home late", "Home early"])

        // And the other list was not written at all — not the row that was in the section, and not
        // the two that were not.
        #expect(workRows.map(\.order) == [0, 1, 2], "a row in another list was renumbered by this drop")
        #expect(
            customOrder(workRows) == workTabBefore,
            "a screen the drag was not made on changed because of it"
        )
        #expect(
            customOrder(workRows).firstIndex(of: "Work second") == 1,
            "a row the user never dragged, in a list the user was not arranging, moved"
        )
    }

    /// **The `nil` half of the rule.** A cross-list drop that passes none of the dragged row's own
    /// siblings has nothing to say in that row's list, so nothing is written anywhere.
    ///
    /// The alternative is worse than a no-op rather than merely different: the dragged row would be
    /// the only member of its filtered sequence, `CadenceOrderCommit.commit` would renumber it to
    /// `0`, and a drag aimed at a row of another list would silently send it to the top of its own
    /// list's arrangement. It still answers `true`, because nothing failed.
    @Test func acrossListDropThatPassesNoneOfItsOwnListsRowsWritesNothing() throws {
        let modelContext = ModelContext(try container())
        let work = Project(name: "Work")
        let home = Project(name: "Home")
        modelContext.insert(work)
        modelContext.insert(home)
        let todayKey = DateFormatters.ymd.string(from: Date())

        let rows = [
            task("Work A", order: 0, project: work, scheduled: todayKey, in: modelContext),
            task("Work B", order: 1, project: work, scheduled: todayKey, in: modelContext),
            task("Home only", order: 2, project: home, scheduled: todayKey, in: modelContext)
        ]
        try modelContext.save()

        let section = try #require(
            CadenceTaskQuerySupport.dateDisplayGroups(from: rows, todayKey: todayKey)
                .first { $0.id == "do-today" }
        ).tasks

        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: try #require(rows.last).id,
                targetID: try #require(rows.first).id,
                scopeTasks: section,
                modelContext: modelContext
            ),
            "a drop with nothing to write is not a refusal"
        )

        #expect(rows.map(\.order) == [0, 1, 2], "a drop that moved the row past none of its siblings wrote anyway")
    }

    /// The other four surfaces are one container each, so the rule above is the identity on them —
    /// which is what lets it live in one place. Measured here on the smallest such surface rather
    /// than asserted: the same two-row drop as `therenumberWritesNoRowOutsideTheSliceItWasHanded`,
    /// read through `CadenceRowReorderSpan` directly.
    @Test func thespanRuleIsTheIdentityOnASliceThatIsAlreadyOneList() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Work")
        modelContext.insert(project)

        let slice = [
            task("Slice A", order: 3, project: project, in: modelContext),
            task("Slice B", order: 4, project: project, in: modelContext)
        ]
        try modelContext.save()

        let dropped = try #require(slice.last)
        let target = try #require(slice.first)
        let siblings = try #require(
            CadenceRowReorderSpan.ownListSiblings(moving: dropped.id, before: target.id, in: slice)
        )
        #expect(siblings.map(\.title) == ["Slice B", "Slice A"], "the span rule dropped a row of the one list it was handed")
    }
}
