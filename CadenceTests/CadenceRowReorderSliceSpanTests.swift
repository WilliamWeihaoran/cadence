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

    /// **MEASURED, and fixed by [[T-1175]].** They did, and inside one container: a drop on a
    /// list's Tasks tab renumbered `openTasks(from: tasks)` from 0, and the list's finished tasks
    /// were not in that array, so they kept the orders the renumber had just handed out again.
    ///
    /// The tab is the smallest surface where the **visible slice is a strict subset of the
    /// sequence the numbering spans**, which is the whole of what T-1175 is about and the thing a
    /// test over a slice equal to its span cannot see. The renumber now spans the list, so the two
    /// finished rows are numbered with the open ones and nothing collides.
    @Test func adropOnAListsTasksTabNumbersItsFinishedRowsIntoTheSameSequence() throws {
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
                spanTasks: all,
                modelContext: modelContext
            )
        )

        // The two finished rows keep the places they held — a drag among the open rows cannot
        // move a row past one the screen was not showing — and they are numbered rather than left
        // holding orders the open rows have just been given again.
        #expect(done.map(\.order) == [0, 1], "the finished rows were moved by a drag that never named them")
        #expect(open.map(\.order) == [3, 4, 2], "the renumber stopped at the edge of the visible slice")
        #expect(customOrder(all) == ["Done A", "Done B", "Open C", "Open A", "Open B"])

        let collisions = Dictionary(grouping: all, by: \.order).filter { $0.value.count > 1 }
        #expect(collisions.isEmpty, "the renumber left rows of one list holding the same order")
        #expect(Set(all.map(\.order)) == [0, 1, 2, 3, 4], "the list is not one 0…n sequence")
    }

    /// **Where the renumber stops, after [[T-1175]]: at the edge of the *list*, not the edge of
    /// the slice.** The two outsiders in this fixture were indistinguishable before — both came out
    /// of the commit holding the order they went in with — and they are the two halves of the
    /// decision. The row in another list is still untouched, because `order` is a per-list
    /// arrangement and [[T-1119]] settled that a drop may not write another list's. The row in the
    /// *same* list that the tab's filter held back is now written, because it is inside the
    /// sequence the drop is renumbering and leaving it out is what made the orders collide.
    @Test func therenumberSpansTheWholeListAndStopsAtItsEdge() throws {
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
                spanTasks: outsiders + slice,
                modelContext: modelContext
            )
        )

        #expect(slice.map(\.order) == [1, 0])
        #expect(outsiders[0].order == 7, "a row in another list was renumbered by this drop")
        #expect(outsiders[1].order == 2, "a row of the dragged row's own list was left out of its sequence")
        #expect(
            customOrder(outsiders + slice) == ["Slice B", "Slice A", "Same list, finished", "Other list"],
            "the list did not come out of the drop as one 0…n sequence"
        )
    }

    // MARK: - Does a later renumber undo an earlier one?

    /// **MEASURED, and fixed by [[T-1175]].** It did, and it did not need the two screens to be
    /// *sorted* differently — only to *slice* differently.
    ///
    /// The user arranges four rows on the list's Tasks tab, dragging Delta to the top. Then, on
    /// Today, they drag Charlie above Bravo — the only two rows that list puts on the day, and a
    /// one-place move on the tab. Today's group is a two-row slice, so it renumbers to `0, 1` over
    /// the orders the tab arrangement had just given to Delta and Alpha.
    ///
    /// Two things the user did not ask for used to come out of that. **Delta, which they
    /// deliberately dragged to the top and then never touched, was no longer at the top.** And
    /// **Charlie, which they asked to move up one place, was first** — it travelled three places,
    /// past two rows that were not in the slice and not on the screen.
    ///
    /// The second drop's slice is a **strict subset** of the sequence it renumbers, which is the
    /// shape this whole ticket is about: the renumber now spans the list, the two rows outside the
    /// Today group keep the places the first drag gave them, and the one-place move is one place.
    @Test func asecondDropOnASmallerSliceKeepsTheArrangementTheFirstOneMade() throws {
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
                spanTasks: all,
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
                spanTasks: all,
                modelContext: modelContext
            )
        )

        // On Today the gesture did exactly what was asked.
        #expect(customOrder([bravo, charlie]) == ["Charlie", "Bravo"])

        // And the two rows the Today group never held keep the places the first drag gave them.
        #expect(delta.order == 0)
        #expect(alpha.order == 1)
        #expect(charlie.order == 2)
        #expect(bravo.order == 3)
        #expect(Set(all.map(\.order)).count == 4, "the second drop left two rows holding one order")

        // And this is what the Tasks tab shows now: the first drag's arrangement, with the one
        // swap the second drag asked for.
        #expect(customOrder(all) == ["Delta", "Alpha", "Charlie", "Bravo"])
        #expect(customOrder(all).first == "Delta", "the row the user dragged to the top left it")
    }

    // MARK: - Can the user see it?

    /// **MEASURED, and fixed by [[T-1175]].** It did, on a screen the drag was not made on.
    /// Nothing is dragged on the list's Tasks tab at all here: the user's only gesture is on Today,
    /// and it used to move a row on the tab that Today never displayed.
    ///
    /// This was the answer to the ticket's "confirmed by reading, not observed in use", and it is
    /// sharper than the "quiet interleaving" it predicted: the interleave was deterministic, but the
    /// *displacement* was not quiet — an untouched row changed places with another untouched row.
    /// Today's group is a **strict subset** of the list it is drawn from, so the drop now renumbers
    /// the list and the two rows the group never held stay where they were.
    @Test func atodayDropLeavesTheRowsItsOwnGroupNeverHeld() throws {
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
                spanTasks: rows,
                modelContext: modelContext
            )
        )

        // On Today the gesture did exactly what was asked.
        #expect(customOrder(Array(rows[2...])) == ["Today late", "Today early"])

        // On the list's Tasks tab, which the user was not looking at, the only change is the one
        // the user made. "Today late" and "Today early" swapped; the two unscheduled rows, which
        // Today never displayed, hold the places and the orders they held before.
        let after = customOrder(rows)
        #expect(after == ["Unscheduled first", "Unscheduled second", "Today late", "Today early"])
        #expect(after != before, "non-vacuity: the drop the user did make changed nothing either")
        #expect(before.firstIndex(of: "Unscheduled second") == 1)
        #expect(
            after.firstIndex(of: "Unscheduled second") == 1,
            "a row the user never dragged, and which Today never displayed, moved"
        )
        #expect(Set(rows.map(\.order)) == [0, 1, 2, 3], "the list is not one 0…n sequence")
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
                spanning: other + column,
                ofList: CadenceTaskDropSupport.containerKey(for: .project(work.id)),
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
                spanTasks: all,
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
                spanTasks: rows,
                modelContext: modelContext
            ),
            "a drop with nothing to write is not a refusal"
        )

        #expect(rows.map(\.order) == [0, 1, 2], "a drop that moved the row past none of its siblings wrote anyway")
    }

    // MARK: - T-1175: the span is the list, not the slice

    /// **The rule the widening is built on: a drag among visible rows never moves one of them past
    /// a row the screen was not showing.** `wholeSequence` is read directly here because the
    /// property is about *positions* and is invisible in a `customOrder` reading, where a hidden
    /// row that moved one place and a hidden row that did not both come out somewhere plausible.
    ///
    /// The list is `Hidden A, Visible A, Hidden B, Visible B, Hidden C`. The slice — the two
    /// visible rows — comes back reversed, and the three hidden rows are still first, third and
    /// fifth. The alternative rules both fail it: appending the hidden rows would put them last,
    /// and resequencing the whole list from the drop would let a visible row overtake `Hidden B`.
    @Test func thewholeSequenceLeavesEveryRowTheSliceDoesNotHoldWhereItWas() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Work")
        modelContext.insert(project)

        let hiddenA = task("Hidden A", order: 0, project: project, in: modelContext)
        let visibleA = task("Visible A", order: 1, project: project, in: modelContext)
        let hiddenB = task("Hidden B", order: 2, project: project, in: modelContext)
        let visibleB = task("Visible B", order: 3, project: project, in: modelContext)
        let hiddenC = task("Hidden C", order: 4, project: project, in: modelContext)
        let list = [hiddenA, visibleA, hiddenB, visibleB, hiddenC]
        try modelContext.save()

        let sequence = CadenceRowReorderSpan.wholeSequence(
            resequencing: [visibleB, visibleA],
            within: list,
            ofList: CadenceTaskQuerySupport.listGroupKey(for: visibleA)
        )
        #expect(
            sequence.map(\.title) == ["Hidden A", "Visible B", "Hidden B", "Visible A", "Hidden C"],
            "a hidden row changed places with a row the drag never named"
        )
        #expect(sequence.count == list.count, "the widening dropped or duplicated a row of the list")
    }

    /// **The span is one list, and a row of another is not in it** — the [[T-1119]] half, asked of
    /// the widening rather than of the narrowing. A universe of two lists comes back as the one the
    /// key names, so widening the *write* cannot undo the decision that a drop writes one list.
    @Test func thewholeSequenceTakesOnlyTheListItsKeyNames() throws {
        let modelContext = ModelContext(try container())
        let work = Project(name: "Work")
        let home = Project(name: "Home")
        modelContext.insert(work)
        modelContext.insert(home)

        let workRows = [
            task("Work A", order: 0, project: work, in: modelContext),
            task("Work B", order: 1, project: work, done: true, in: modelContext)
        ]
        let homeRows = [
            task("Home A", order: 0, project: home, in: modelContext),
            task("Home B", order: 1, project: home, in: modelContext)
        ]
        try modelContext.save()

        let sequence = CadenceRowReorderSpan.wholeSequence(
            resequencing: [workRows[0]],
            within: workRows + homeRows,
            ofList: CadenceTaskQuerySupport.listGroupKey(for: workRows[0])
        )
        #expect(sequence.map(\.title) == ["Work A", "Work B"], "the widening reached a list the drop was not in")
        #expect(
            !sequence.contains(where: { homeRows.map(\.id).contains($0.id) }),
            "a row of another list is inside the sequence this drop renumbers"
        )
    }

    /// **A card arriving from another column is kept**, which is the one way a slice can hold a row
    /// the span does not. `KanbanBoardSupport.reorder` files the card into the destination column
    /// inside the same commit, so at the moment this is asked the card's own list is still the one
    /// it is leaving — and a widening that took only the rows it recognised would drop the dragged
    /// card out of the sequence and leave it holding its old `order`.
    @Test func thewholeSequenceKeepsACardTheDestinationListDoesNotHoldYet() throws {
        let modelContext = ModelContext(try container())
        let work = Project(name: "Work")
        let home = Project(name: "Home")
        modelContext.insert(work)
        modelContext.insert(home)

        let destination = [
            task("Work A", order: 0, project: work, in: modelContext),
            task("Work B", order: 1, project: work, done: true, in: modelContext)
        ]
        let arriving = task("Home A", order: 9, project: home, in: modelContext)
        try modelContext.save()

        let sequence = CadenceRowReorderSpan.wholeSequence(
            resequencing: [arriving, destination[0]],
            within: destination,
            ofList: CadenceTaskDropSupport.containerKey(for: .project(work.id))
        )
        #expect(sequence.map(\.title) == ["Home A", "Work A", "Work B"], "the arriving card fell out of the sequence")
    }

    /// **A refused card drop puts back every row the renumber would have written**, which since
    /// this ticket is the **list** rather than the column. The undo snapshot had to widen with the
    /// write: left at the column, a refused drop would leave the rows outside it — this list's
    /// finished card — holding orders from a drop the store never took.
    @Test func arefusedCardDropPutsBackEveryRowTheWidenedRenumberTouches() throws {
        let modelContext = ModelContext(try container())
        let work = Project(name: "Work")
        modelContext.insert(work)

        let column = [
            task("Card A", order: 0, project: work, in: modelContext),
            task("Card B", order: 1, project: work, in: modelContext)
        ]
        let outsideTheColumn = task("Finished", order: 7, project: work, done: true, in: modelContext)
        try modelContext.save()

        struct Refused: Error {}
        #expect(
            !KanbanBoardSupport.reorder(
                column,
                // Indexed rather than `#require`d: the column is the literal two rows above, so
                // both `#require`s were redundant and the compiler said so. The warning baseline
                // is zero.
                moving: column[1],
                before: column[0],
                spanning: column + [outsideTheColumn],
                ofList: CadenceTaskDropSupport.containerKey(for: .project(work.id)),
                in: modelContext,
                commit: { _ in throw Refused() }
            ),
            "a refused commit was reported as a drop that happened"
        )
        #expect(column.map(\.order) == [0, 1], "the refused drop left the new order on the column")
        #expect(
            outsideTheColumn.order == 7,
            "the refused drop left a row outside the column holding an order it was never committed"
        )
    }

    /// **Every row-drop surface hands in a span, and none of them hands in its own slice.** The
    /// parameter is not defaulted, so a surface cannot *forget* it — what it can still do is pass
    /// the array it already had, which compiles, passes every test written over a slice equal to
    /// its span, and reinstates the whole defect one surface at a time. This reads the five sites
    /// and names the value each one passes.
    ///
    /// Whole-file reads rather than declaration bodies, because one of the five is a closure
    /// (`TasksPanel`'s `reorderTask:` argument) and a body reader anchored on a prefix that has
    /// already opened the brace reads the wrong span. Each file holds exactly one such call, which
    /// the non-vacuity line below asserts rather than assumes.
    @Test func everyRowDropSurfaceHandsInASpanWiderThanItsSlice() throws {
        let sites: [(path: String, call: String, span: String)] = [
            ("Cadence/macOS/Views/TasksPanel.swift", "TasksPanelSupport.reorderTask(", "spanTasks: allTasks"),
            ("Cadence/macOS/Views/TasksListView.swift", "TasksPanelSupport.reorderTask(", "spanTasks: allTasks"),
            ("Cadence/macOS/Views/ListDetailComponents.swift", "TasksPanelSupport.reorderTask(", "spanTasks: tasks"),
            ("Cadence/macOS/Views/KanbanListColumnView.swift", "KanbanBoardSupport.reorder(", "spanning: spanTasks"),
            ("Cadence/macOS/Views/KanbanSectionColumnView.swift", "KanbanBoardSupport.reorder(", "spanning: spanTasks")
        ]
        var checked = 0
        for site in sites {
            let source = try CadenceCommitSurfaceScan.scanned(site.path)
            #expect(
                source.components(separatedBy: site.call).count == 2,
                "\(site.path) no longer holds exactly one \(site.call), so this read is about the wrong call"
            )
            #expect(source.contains(site.span), "\(site.path) renumbers a slice rather than the sequence it spans")
            #expect(
                !source.contains("spanTasks: scopeTasks"),
                "\(site.path) hands its own slice in as the span, which is the defect T-1175 is about"
            )
            checked += 1
        }
        #expect(checked == 5, "expected five row-drop surfaces, checked \(checked)")
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
