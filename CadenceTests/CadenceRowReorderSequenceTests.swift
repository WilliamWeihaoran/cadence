import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-884: which sequence a row drag rewrites, decided and pinned.**
///
/// Four macOS surfaces renumber `AppTask.order` from a drop, and until this ticket they did not
/// agree on what they were renumbering. Two took the tasks **in `order`** — Today / All Tasks /
/// Inbox through `TasksPanelSupport.reorderTask`, and the section kanban board's card drop. Two
/// took the **displayed** sequence — a list's own Tasks tab through `ListTasksView.reorderTask`
/// (the tab's active sort *plus* its hover freeze), and the All Tasks kanban board's card drop (the
/// board's active sort). Under `.custom` the two rules coincide; under `.date` or `.priority` the
/// same gesture meant two different things depending on which screen it was made on.
///
/// ## The decision, and why it is not the shorter diff
///
/// **`order` is the custom arrangement, and it is the only sequence in this app a user authors.**
/// `TaskOrdering.precedes` sorts by it outright under `.custom` and uses it only as the final
/// tie-break under `.date` and `.priority`. A drag made while the screen is sorted by date is
/// therefore not a statement about the sequence on screen — that sequence is derived from dates,
/// and the drag does not change a date.
///
/// **Renumbering the display writes the derived sequence over the authored one.** One drag under a
/// date sort replaces the user's whole hand-made arrangement with the date order, silently, and
/// invisibly, because the screen is not showing `order` while it happens. They find out the next
/// time they choose Custom, and there is nothing to undo. `theRejectedRuleWouldOverwriteTheCustom
/// ArrangementWithTheDateOrder` measures exactly that, over the rejected rule, so the argument is
/// not left as prose.
///
/// **The cost of the rule that was chosen is real, and it is smaller.** Under a date sort the
/// dragged row lands somewhere the user cannot see, so the gesture looks like it did nothing. But
/// the row springs back on screen under *either* rule, because the list re-sorts by date the moment
/// the drop lands — the visible outcome is identical, and only the rejected rule also destroys
/// something. And the chosen one is exactly recoverable: drag again under Custom.
///
/// **The hover-freeze half was not a judgement call at all.** `TaskListKanbanColumn.moveTask`
/// already recorded that "the hover freeze is a display-only concern and must never be what gets
/// written back into `order`", and `ListTasksView.reorderTask` was writing precisely that back.
///
/// ## What this ticket deliberately did not decide
///
/// Whether a row drag should be **offered** under a non-custom sort at all ([[T-1054]]), and the
/// fact that every one of these sites renumbers a *slice* rather than the whole sequence its
/// numbering spans ([[T-1055]]). Both are named in `TasksPanelSupport.reorderTask`'s own doc.
@MainActor
struct CadenceRowReorderSequenceTests {

    private func container() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    /// Four tasks whose `order` is the user's hand-made arrangement and whose dates run the other
    /// way, so the two candidate sequences are as different as they can be.
    ///
    /// custom order: Alpha, Bravo, Charlie, Delta
    /// date order:   Delta, Charlie, Bravo, Alpha
    private func board(in modelContext: ModelContext) throws -> [AppTask] {
        let dates = ["2026-09-04", "2026-09-03", "2026-09-02", "2026-09-01"]
        let tasks = ["Alpha", "Bravo", "Charlie", "Delta"].enumerated().map { index, title -> AppTask in
            let task = AppTask(title: title)
            task.order = index
            task.scheduledDate = dates[index]
            modelContext.insert(task)
            return task
        }
        try modelContext.save()
        return tasks
    }

    private func customOrder(_ tasks: [AppTask]) -> [String] {
        tasks.taskSorted(by: .custom, direction: .ascending).map(\.title)
    }

    /// **Behavioural.** A drag under a date sort moves one row inside the *custom* sequence and
    /// leaves the rest of that sequence exactly as the user arranged it.
    @Test func adragUnderADateSortMovesOneRowInsideTheCustomArrangement() throws {
        let modelContext = ModelContext(try container())
        let tasks = try board(in: modelContext)
        let displayed = tasks.taskSorted(by: .date, direction: .ascending)
        #expect(displayed.map(\.title) == ["Delta", "Charlie", "Bravo", "Alpha"], "non-vacuity: the two sequences agree")

        // The user drags Delta — last in the custom order, first on screen — onto Bravo.
        let dropped = try #require(tasks.first { $0.title == "Delta" })
        let target = try #require(tasks.first { $0.title == "Bravo" })
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: dropped.id,
                targetID: target.id,
                scopeTasks: displayed,
                modelContext: modelContext
            )
        )

        #expect(customOrder(tasks) == ["Alpha", "Delta", "Bravo", "Charlie"])
        #expect(!modelContext.hasChanges, "the drop is still pending after it answered yes")
    }

    /// **Behavioural, over the rejected rule.** The same gesture, renumbering the displayed
    /// sequence: every row the user ever arranged by hand is now in date order, and nothing on
    /// screen said so. This is the loss the decision above is about, and it is measured rather than
    /// asserted in prose.
    @Test func therejectedRuleWouldOverwriteTheCustomArrangementWithTheDateOrder() throws {
        let modelContext = ModelContext(try container())
        let tasks = try board(in: modelContext)
        #expect(customOrder(tasks) == ["Alpha", "Bravo", "Charlie", "Delta"])

        // Exactly what `ListTasksView.reorderTask` used to do: take the displayed sequence, move
        // the dragged row inside it, renumber that.
        var displayed = tasks.taskSorted(by: .date, direction: .ascending)
        let fromIndex = try #require(displayed.firstIndex { $0.title == "Delta" })
        let toIndex = try #require(displayed.firstIndex { $0.title == "Bravo" })
        let element = displayed.remove(at: fromIndex)
        displayed.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        #expect(
            CadenceOrderCommit.commit(
                displayed,
                readOrder: { $0.order },
                writeOrder: { $0.order = $1 },
                in: modelContext
            )
        )

        #expect(
            customOrder(tasks) == ["Charlie", "Delta", "Bravo", "Alpha"],
            "the rejected rule no longer destroys the custom arrangement, so this test argues nothing"
        )
        // Alpha, which the user never touched and which sat first in their arrangement, is last.
        #expect(customOrder(tasks).last == "Alpha")
    }

    /// **Behavioural.** Under `.custom` the two rules coincide, which is why the disagreement went
    /// unnoticed: the displayed sequence *is* the `order` sequence there.
    @Test func underTheCustomSortTheTwoRulesAgree() throws {
        let modelContext = ModelContext(try container())
        let tasks = try board(in: modelContext)
        let displayed = tasks.taskSorted(by: .custom, direction: .ascending)
        #expect(displayed.map(\.title) == ["Alpha", "Bravo", "Charlie", "Delta"])

        let dropped = try #require(tasks.first { $0.title == "Delta" })
        let target = try #require(tasks.first { $0.title == "Bravo" })
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: dropped.id,
                targetID: target.id,
                scopeTasks: displayed,
                modelContext: modelContext
            )
        )
        #expect(customOrder(tasks) == ["Alpha", "Delta", "Bravo", "Charlie"])
    }

    /// **Behavioural.** The kanban card drop is the same decision on the other pair of surfaces:
    /// `KanbanBoardSupport.reorder` is handed the column in `order`, so a card dragged while the
    /// board is sorted by date moves inside the custom arrangement rather than flattening it.
    @Test func thekanbanCardDropAlsoRenumbersTheCustomArrangement() throws {
        let modelContext = ModelContext(try container())
        let tasks = try board(in: modelContext)
        let dropped = try #require(tasks.first { $0.title == "Delta" })
        let target = try #require(tasks.first { $0.title == "Bravo" })

        // What both column views now pass: the column's tasks, unfrozen, in `order`.
        #expect(
            KanbanBoardSupport.reorder(
                tasks.taskSorted(by: .date, direction: .ascending).sorted { $0.order < $1.order },
                moving: dropped,
                before: target,
                in: modelContext
            )
        )
        #expect(customOrder(tasks) == ["Alpha", "Delta", "Bravo", "Charlie"])
    }

    // MARK: - The four sites

    /// **All four renumbering sites take their sequence in `order`.**
    ///
    /// Two of them are `private` members of SwiftUI views, so this is a source scan; the two that
    /// are not are driven behaviourally above. The list's Tasks tab is pinned by its *absence* of
    /// `activeTasks` — the one name in that file that carries both the active sort and the hover
    /// freeze — because that is the shape the defect had.
    @Test func everyRowRenumberTakesItsSequenceInOrder() throws {
        let panelSupport = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/TasksPanelSupport.swift")
        let shared = try CadenceCommitSurfaceScan.declarationBody(named: "reorderTask", in: panelSupport)
        #expect(shared.contains("scopeTasks.sorted { $0.order < $1.order }"), "the shared row renumber left the `order` sequence")

        let listTab = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/ListDetailComponents.swift")
        let tabDrop = try CadenceCommitSurfaceScan.declarationBody(named: "reorderTask", in: listTab)
        #expect(tabDrop.contains("TasksPanelSupport.reorderTask("), "the list's Tasks tab renumbers its own sequence again")
        #expect(!tabDrop.contains("activeTasks"), "the list's Tasks tab writes its sort and hover freeze back into `order`")

        let sectionColumn = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanSectionColumnView.swift")
        let sectionDrop = try CadenceCommitSurfaceScan.declarationBody(named: "moveTask", in: sectionColumn)
        #expect(sectionDrop.contains("tasks.sorted { $0.order < $1.order }"))

        let listColumn = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanListColumnView.swift")
        let listDrop = try CadenceCommitSurfaceScan.declarationBody(named: "moveTask", in: listColumn)
        #expect(
            listDrop.contains("unfrozenSortedTasks.sorted { $0.order < $1.order }"),
            "the list kanban column renumbers the board's active sort again"
        )
    }
    // MARK: - T-1054: is the drag actually invisible under a non-custom sort?

    /// **Behavioural, and it contradicts the premise of [[T-1054]].** A drag between two rows that
    /// **tie on the active sort key** lands exactly where it was dropped and stays there. Nothing
    /// springs back.
    ///
    /// `TaskOrdering.precedes` falls through to `fallbackPrecedes` on a tie under both `.date` and
    /// `.priority`, and `fallbackPrecedes`'s **first** key is `order`. So the displayed sequence
    /// inside a tie band *is* the `order` sequence, exactly as it is under `.custom`.
    @Test func adragBetweenTwoUndatedRowsIsFullyVisibleUnderADateSort() throws {
        let modelContext = ModelContext(try container())
        let tasks = ["Alpha", "Bravo", "Charlie"].enumerated().map { index, title -> AppTask in
            let task = AppTask(title: title)
            task.order = index
            modelContext.insert(task)   // no scheduledDate: all three tie on `noDateSortKey`
            return task
        }
        try modelContext.save()

        let displayed = tasks.taskSorted(by: .date, direction: .ascending)
        #expect(displayed.map(\.title) == ["Alpha", "Bravo", "Charlie"])

        let dropped = try #require(tasks.first { $0.title == "Charlie" })
        let target = try #require(tasks.first { $0.title == "Alpha" })
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: dropped.id,
                targetID: target.id,
                scopeTasks: displayed,
                modelContext: modelContext
            )
        )

        // The screen is still sorted by date, and the row is where it was dropped.
        #expect(
            tasks.taskSorted(by: .date, direction: .ascending).map(\.title) == ["Charlie", "Alpha", "Bravo"],
            "the drag under a date sort did nothing the user can see"
        )
    }

    /// **Behavioural.** The same under `.priority`, where ties are the common case rather than the
    /// edge one: there are four ranks, so every list longer than four rows has a band.
    @Test func adragInsideOnePriorityBandIsFullyVisibleUnderAPrioritySort() throws {
        let modelContext = ModelContext(try container())
        let tasks = ["Alpha", "Bravo", "Charlie"].enumerated().map { index, title -> AppTask in
            let task = AppTask(title: title)
            task.order = index
            task.priority = .high
            modelContext.insert(task)
            return task
        }
        try modelContext.save()

        let displayed = tasks.taskSorted(by: .priority, direction: .descending)
        #expect(displayed.map(\.title) == ["Alpha", "Bravo", "Charlie"])

        let dropped = try #require(tasks.first { $0.title == "Charlie" })
        let target = try #require(tasks.first { $0.title == "Bravo" })
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: dropped.id,
                targetID: target.id,
                scopeTasks: displayed,
                modelContext: modelContext
            )
        )

        #expect(
            tasks.taskSorted(by: .priority, direction: .descending).map(\.title) == ["Alpha", "Charlie", "Bravo"],
            "reordering inside one priority band is invisible"
        )
    }

    /// **Behavioural, the other half.** Across a sort-key boundary the row genuinely does spring
    /// back — this is the case [[T-1054]] describes, and it is a *subset* of the gesture rather
    /// than all of it.
    @Test func adragAcrossADateBoundaryIsTheOneThatSpringsBack() throws {
        let modelContext = ModelContext(try container())
        let tasks = try board(in: modelContext)
        let displayed = tasks.taskSorted(by: .date, direction: .ascending)
        #expect(displayed.map(\.title) == ["Delta", "Charlie", "Bravo", "Alpha"])

        let dropped = try #require(tasks.first { $0.title == "Alpha" })
        let target = try #require(tasks.first { $0.title == "Delta" })
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: dropped.id,
                targetID: target.id,
                scopeTasks: displayed,
                modelContext: modelContext
            )
        )

        #expect(
            tasks.taskSorted(by: .date, direction: .ascending).map(\.title) == ["Delta", "Charlie", "Bravo", "Alpha"],
            "the dragged row did not spring back, so the premise of T-1054 holds nowhere"
        )
        #expect(customOrder(tasks) != ["Alpha", "Bravo", "Charlie", "Delta"], "and `order` did change")
    }

}
