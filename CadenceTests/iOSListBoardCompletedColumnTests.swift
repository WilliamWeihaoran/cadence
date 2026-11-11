import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-9837]]: an iOS list Kanban column closes with the Mac's "Completed N" toggle instead of
/// dropping its finished cards.**
///
/// `iOSListDetailView` handed `iOSListKanbanPanel` its `activeTasks` only and `iOSListKanbanColumn`
/// drew no footer, so a column whose work was all done read "0" and empty on an iPad while macOS's
/// `ListSectionKanbanColumn` split the same column with `KanbanBoardSupport.columnHalves` and
/// closed it with `KanbanCompletedTasksToggle`. The candidate reason -- the iOS list page has its
/// own Completed tab -- is not a hardware or input reason ([[T-8201]]), and the Mac list page has
/// finished work in more than one place too.
///
/// The bucketing is pinned by VALUE and the drawing by source scan. Both kinds: a scan that said
/// "a footer is drawn" would pass over a footer counting the wrong half.
@MainActor
struct iOSListBoardCompletedColumnTests {
    private static let boardFile = "Cadence/iOS/iOSListSupportViews.swift"
    private static let pageFile = "Cadence/iOS/iOSListDetailView.swift"

    private func boardSource() throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.boardFile))
    }

    private func column(in code: String) throws -> String {
        try #require(
            CadenceSourceScan.declarationBody("private struct iOSListKanbanColumn: View", in: code),
            "the iOS list board column is gone from \(Self.boardFile)"
        )
    }

    private func task(_ title: String, section: String, status: TaskStatus) -> AppTask {
        let task = AppTask(title: title)
        task.sectionName = section
        task.status = status
        return task
    }

    /// **Finished cards reach the column they belong to, by the same rule the open ones do.**
    ///
    /// *Failing-first:* bucketing by anything other than `sectionGroups` — a raw
    /// `filter { $0.sectionName == name }`, say — fails the case-insensitive expectation, which is
    /// the one a hand-rolled match gets wrong.
    @Test func finishedCardsAreBucketedIntoTheColumnTheyBelongTo() {
        let finished = [
            task("shipped", section: "Doing", status: .done),
            task("dropped", section: "doing", status: .cancelled),
            task("filed", section: "Backlog", status: .done)
        ]
        let byColumn = ListDetailKanbanBoard.completedTasksByColumn(
            tasks: finished,
            sectionNames: ["Backlog", "Doing", "Done"]
        )
        #expect(byColumn["Doing"]?.count == 2, "the finished half does not match a section name case-insensitively")
        #expect(byColumn["Backlog"]?.count == 1)
        // A CONFIGURED column with no finished work is ABSENT rather than present-and-empty, so
        // it draws no footer and a board of open columns looks exactly as it did.
        #expect(byColumn["Done"] == nil, "an empty Completed half is carried as a key, so an empty footer can be drawn")
        #expect(byColumn.count == 2)
    }

    /// **A cancelled task is finished work**, which is the one classification mistake this split
    /// can make — `!$0.isDone` would file it among the work you still intend to do, the
    /// T-147 / T-203 / T-342 / T-381 shape.
    ///
    /// *Failing-first:* splitting on `isDone` instead of `isFinishedTask` leaves the cancelled
    /// card out of the map entirely and fails the count.
    @Test func aCancelledCardCountsAsFinishedAndNotAsOpenWork() {
        let cancelled = task("dropped", section: "Doing", status: .cancelled)
        #expect(cancelled.isDone == false, "the premise moved: a cancelled task now reports isDone")
        let byColumn = ListDetailKanbanBoard.completedTasksByColumn(
            tasks: CadenceTaskQuerySupport.completedTasks(from: [cancelled]),
            sectionNames: ["Doing"]
        )
        #expect(byColumn["Doing"]?.count == 1, "a cancelled card is not treated as finished work")
    }

    /// **The page hands the board its finished half**, which it never did — without this the
    /// column has a footer and nothing to put in it, so the defect would ship unchanged.
    ///
    /// *Failing-first:* dropping `completedTasks: kanbanCompletedTasks` from the page's call fails here.
    /// [[T-16301]]: the argument is the board-sorted finished half, no longer the Completed tab's list.
    @Test func theListPageHandsTheBoardItsFinishedHalf() throws {
        // Ordering rather than a fixed window: both comment strippers preserve the source's
        // LENGTH, so a `prefix(n)` after the call can be almost entirely blanked comment.
        let page = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.pageFile))
        let call = try #require(page.range(of: "iOSListKanbanPanel("), "the list page draws no board")
        let active = try #require(page.range(of: "tasks: kanbanTasks,", range: call.upperBound..<page.endIndex),
                                  "non-vacuity: the call read is not the board's")
        let finished = try #require(
            page.range(of: "completedTasks: kanbanCompletedTasks,", range: active.upperBound..<page.endIndex),
            "the board is still handed the open half only, which is the [[T-9837]] defect"
        )
        // The board's own argument. This read `sectionNames: sectionNames,`, which the board call
        // has not carried since its columns became `kanbanSectionNames` -- so it matched the Tasks
        // tab's call further down, until [[T-12121]] removed that one too.
        let sections = try #require(page.range(of: "sectionNames: kanbanSectionNames,", range: call.upperBound..<page.endIndex))
        #expect(finished.upperBound <= sections.lowerBound,
                "the finished half is passed somewhere other than inside the board's own call")

        let board = try boardSource()
        let panel = try #require(
            CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: board),
            "the iOS list board panel is gone"
        )
        #expect(panel.contains("var completedTasks: [AppTask] = []"), "the panel takes no finished half")
        #expect(panel.contains("ListDetailKanbanBoard.completedTasksByColumn(tasks: completedTasks, sectionNames: sectionNames, filing: liveFiling)"),
                "the panel buckets the finished half some way other than the shared rule")
        #expect(panel.contains("completedTasks: finished[column.title] ?? []"),
                "the panel hands its columns no finished cards")
        // One pass for the board, not one filter per column inside the `ForEach` (T-1501).
        #expect(CadenceSourceScan.matchCount(#"let finished = completedByColumn"#, in: panel) == 1,
                "the finished map is derived per column again")
    }

    /// **The footer itself: the shared label, collapsed on arrival, over the column's own cards.**
    ///
    /// *Failing-first:* starting expanded (`= false`) fails the collapsed expectation; drawing the
    /// count with a hand-rolled row instead of `CadenceBoardCompletedToggleLabel` fails the shared
    /// label one, which is the second copy [[T-9835]] took out of the tree.
    @Test func theColumnClosesWithTheSharedCompletedToggleCollapsed() throws {
        let code = try boardSource()
        let column = try column(in: code)
        #expect(column.count > 1_000, "non-vacuity: the column read as \(column.count) characters")
        #expect(column.contains("var completedTasks: [AppTask] = []"), "the column takes no finished cards")
        #expect(column.contains("@State private var isCompletedCollapsed = true"),
                "the Completed section is not collapsed on arrival")
        #expect(column.contains("CadenceBoardCompletedToggleLabel("),
                "the column draws its own Completed row instead of the one shared with the Mac")
        #expect(column.contains("count: completedTasks.count,"), "the toggle counts something other than the finished cards")
        #expect(column.contains("isExpanded: !isCompletedCollapsed,"))
        #expect(column.contains("minimumHeight: 44"), "the toggle lost iOS's touch-row floor")
        // [[T-9833]]: the disclosure says which way it is, as the Mac's has since [[T-7081]].
        #expect(column.contains(#".accessibilityValue(isCompletedCollapsed ? "Collapsed" : "Expanded")"#),
                "the Completed toggle states neither Expanded nor Collapsed")
        #expect(column.contains("if !isCompletedCollapsed {"), "the finished cards are drawn whether or not it is open")
    }

    /// **The header's count stays the OPEN work.** The toggle carries its own count, so adding the
    /// two would state one number twice — T-571's rule, and the Mac's.
    ///
    /// *Failing-first:* `count: tasks.count + completedTasks.count` fails here.
    @Test func theColumnHeaderStillCountsOnlyTheOpenCards() throws {
        let code = try boardSource()
        let column = try column(in: code)
        let header = try #require(column.range(of: "CadenceBoardColumnHeader("), "the column has no header")
        let head = String(column[header.lowerBound...].prefix(300))
        #expect(head.contains("count: tasks.count,"), "the column header counts something other than its open cards")
        #expect(!head.contains("completedTasks.count"),
                "the header folds the finished cards into the number the toggle below already states")
    }

    /// **The footer is inside the card scroller, after the open stack** — [[T-9611]]'s answer for
    /// the Calendar Board's column, and where macOS puts its toggle. Pinned off the far bottom it
    /// would be a second thing competing for the column's height.
    ///
    /// *Failing-first:* moving `completedFooter` out of the `ScrollView` fails the ordering.
    @Test func theFooterScrollsWithTheCardsAboveIt() throws {
        let code = try boardSource()
        let column = try column(in: code)
        let scroller = try #require(column.range(of: "ScrollView {"), "the column's cards no longer scroll")
        let cards = try #require(column.range(of: "ForEach(tasks) { task in", range: scroller.upperBound..<column.endIndex))
        let footer = try #require(
            column.range(of: "completedFooter", range: cards.upperBound..<column.endIndex),
            "the column draws no Completed footer after its open cards"
        )
        let scrollerEnd = try #require(column.range(of: ".scrollIndicators(.hidden)"))
        #expect(footer.upperBound < scrollerEnd.lowerBound,
                "the footer is pinned outside the scroller, competing with the cards for the column's height")
    }

    // MARK: - [[T-15620]]: a finished card set down on another column moves there

    /// **A finished card is a card the board's drop accepts.** [[T-9837]] made the finished cards
    /// behind the Completed toggle `.draggable`, but the board checked the payload against its OPEN
    /// cards only, so the card lifted, was carried over, and snapped back with nothing written --
    /// while the Mac's section column, which checks against the list's whole task set, moves it.
    ///
    /// *Failing-first:* `droppableCards` returning `open` alone answers `false` here and leaves the
    /// card in "Doing".
    @Test func aFinishedCardDroppedOnAnotherColumnMovesThere() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let open = task("still open", section: "Doing", status: .todo)
        let finished = task("shipped", section: "Doing", status: .done)
        modelContext.insert(open)
        modelContext.insert(finished)
        try modelContext.save()

        let board = ListDetailKanbanBoard.droppableCards(open: [open], finished: [finished])
        #expect(board.count == 2, "the drop's card set leaves out one half of the board")
        let landed = CadenceKanbanCardDrop.drop(
            [TaskDragPayload.string(for: finished.id)],
            intoColumn: "Backlog",
            columnTasks: [],
            among: board,
            spanning: [open, finished],
            ofList: CadenceTaskDropSupport.containerKey(for: .inbox),
            in: modelContext
        )
        #expect(landed, "a finished card set down on another column is refused")
        #expect(finished.sectionName == "Backlog", "the finished card snapped back to its old column")
        #expect(finished.status == .done, "moving a finished card reopened it")
    }

    /// **The iOS board hands its drop that set**, and the finished cards it is about are still
    /// draggable -- otherwise the behavioural test above proves a helper nothing calls.
    ///
    /// *Failing-first:* restoring `among: tasks,` in `iOSListKanbanPanel` fails here.
    @Test func theIOSBoardDropAcceptsItsFinishedCards() throws {
        let code = try boardSource()
        let panel = try #require(
            CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: code),
            "the iOS list board panel is gone"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"among: ListDetailKanbanBoard\.droppableCards\(\s*open: tasks,\s*finished: completedTasks\s*\)"#,
                in: panel
            ) == 1,
            "the board checks a dropped card against its open cards only, so a finished card snaps back"
        )
        let column = try column(in: code)
        let footer = try #require(column.range(of: "ForEach(completedTasks) { task in"), "the footer draws no finished cards")
        // Since [[T-15622]] the footer draws the column's one card builder, which carries the drag.
        #expect(column[footer.upperBound...].prefix(1_200).contains("boardCard(task)"),
                "non-vacuity: the finished cards no longer draw the column's draggable card")
        let card = try boardCard(in: column)
        #expect(card.contains(".draggable(TaskDragPayload.string(for: task.id))"),
                "non-vacuity: the finished cards are no longer draggable, so there is nothing to accept")
    }

    // MARK: - [[T-15622]]: a card dropped on a finished card lands in front of it

    private func boardCard(in column: String) throws -> String {
        try #require(
            CadenceSourceScan.declarationBody("private func boardCard(_ task: AppTask) -> some View", in: column),
            "the column's one card builder is gone"
        )
    }

    /// **A card set down on a finished card goes in front of it**, as on the Mac, whose
    /// `ListSectionKanbanColumn.moveTask` orders among the column's whole `tasks`, finished cards
    /// included. `drop` finds a `before:` target only in `columnTasks`; handed the open half alone it
    /// cannot find a finished target and files the card at the column's end.
    ///
    /// *Failing-first:* `dropColumnCards` returning `open` alone puts the moved card AFTER the
    /// finished one it was dropped on.
    @Test func aCardDroppedOnAFinishedCardLandsInFrontOfIt() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let open = task("still open", section: "Doing", status: .todo)
        let finished = task("shipped", section: "Doing", status: .done)
        let moving = task("carried over", section: "Backlog", status: .todo)
        for (index, item) in [open, finished, moving].enumerated() {
            item.order = index
            modelContext.insert(item)
        }
        try modelContext.save()

        let columnCards = ListDetailKanbanBoard.dropColumnCards(open: [open], finished: [finished])
        #expect(columnCards.count == 2, "the column's drop order leaves out one half of the column")
        let landed = CadenceKanbanCardDrop.drop(
            [TaskDragPayload.string(for: moving.id)],
            intoColumn: "Doing",
            before: finished,
            columnTasks: columnCards,
            among: ListDetailKanbanBoard.droppableCards(open: [open, moving], finished: [finished]),
            spanning: [open, finished, moving],
            ofList: CadenceTaskDropSupport.containerKey(for: .inbox),
            in: modelContext
        )
        #expect(landed, "a card set down on a finished card is refused")
        #expect(moving.sectionName == "Doing", "the card did not move to the finished card's column")
        #expect(moving.order < finished.order,
                "the card landed after the finished card it was dropped on, at the column's end")
        #expect(open.order < moving.order, "the card jumped in front of the open card above the drop")
        #expect(finished.status == .done, "a drop on a finished card reopened it")
    }

    /// **Both stacks draw the one card builder, it is a drop target with the insertion line, and
    /// the board orders a drop among the column's finished cards too.** Without the first half the
    /// test above proves a helper the finished cards never reach.
    ///
    /// *Failing-first:* restoring the footer's bare `iOSBoardTaskCard(...).draggable(...)` fails the
    /// call count; restoring `columnTasks: column.tasks,` fails the panel half.
    @Test func theFinishedCardsAreDropTargetsWithTheInsertionLine() throws {
        let code = try boardSource()
        let column = try column(in: code)
        #expect(CadenceSourceScan.matchCount(#"boardCard\(task\)"#, in: column) == 2,
                "the open stack and the Completed footer do not both draw the column's one card")
        let footer = try #require(column.range(of: "ForEach(completedTasks) { task in"))
        #expect(column[footer.upperBound...].prefix(1_200).contains("boardCard(task)"),
                "the Completed footer draws a card that takes no drop")
        let card = try boardCard(in: column)
        #expect(CadenceSourceScan.matchCount(#"onDropCard\(items, task\)"#, in: card) == 1,
                "the card is not a drop-before target")
        #expect(card.contains("if dropTargetTaskID == task.id {") && card.contains(".frame(height: 2)"),
                "the card draws no insertion line while a card is held over it")

        let panel = try #require(
            CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: code),
            "the iOS list board panel is gone"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"columnTasks: ListDetailKanbanBoard\.dropColumnCards\(\s*open: column\.tasks,\s*finished: finished\[column\.title\] \?\? \[\]\s*\)"#,
                in: panel
            ) == 1,
            "the board orders a drop among the column's open cards only, so a drop on a finished card goes to the end"
        )
    }

    /// **The Mac's finished cards draw the insertion line too.** They were drop targets already
    /// but passed no `showsDropIndicator`, so the line the open cards draw never showed on them;
    /// one app, so both platforms' finished cards say where a drop lands ([[T-8201]]).
    ///
    /// *Failing-first:* dropping `showsDropIndicator:` from `completedTaskCards` fails here.
    @Test func theMacFinishedCardsDrawTheInsertionLineToo() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift")
        )
        let cards = try #require(
            CadenceSourceScan.declarationBody("private func completedTaskCards(tasks: [AppTask]) -> some View", in: source),
            "the Mac section column's finished cards are gone"
        )
        #expect(cards.contains("KanbanDraggableCard("), "non-vacuity: the finished cards are not the draggable card")
        #expect(cards.contains("showsDropIndicator: dragOverTaskID == task.id,"),
                "the Mac's finished cards draw no insertion line")
        #expect(cards.contains("onDropBefore:"), "the Mac's finished cards take no drop")
    }
}
