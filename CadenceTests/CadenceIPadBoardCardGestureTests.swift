#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-8182]] and [[T-8183]]: what a finger can do to an iOS board card.**
///
/// - [[T-8182]]: a long press on a board card opens the task action menu the task rows show. The
///   card had no context menu at all, so neither a long press nor a right-click opened anything.
/// - [[T-8183]]: a card on the list Kanban tab moves between columns by touch. The card offered no
///   drag and its column took no card.
/// - [[T-8271]]: and within one. A card dropped on a card lands in front of it, as on macOS; the
///   column was the only target, so a card could never move inside its own column.
///
/// The write is asked directly, because it lives in `Shared/` (`CadenceKanbanCardDrop`, the write macOS's
/// columns make too). The wiring is read from source,
/// because `Cadence/iOS/` is inside `#if os(iOS)` and this target builds for macOS. Neither half
/// is a sighting: what a press on glass actually does is for an attended simulator session.
@MainActor
struct CadenceIPadBoardCardGestureTests {

    // MARK: - What a card dropped on a column writes

    private final class CountingCommit {
        var refuses = false
        private(set) var commitCount = 0
        struct Refused: Error {}

        func commit(_ modelContext: ModelContext) throws {
            commitCount += 1
            if refuses { throw Refused() }
            try modelContext.save()
        }
    }

    private func boardTask(
        _ title: String,
        section: String,
        order: Int = 0,
        in modelContext: ModelContext
    ) throws -> AppTask {
        let task = AppTask(title: title)
        task.sectionName = section
        task.order = order
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    /// The board's call with one board's worth of arguments: every card on the board, the list as
    /// the span, and the inbox as the list (none of these tasks is filed anywhere else).
    private func drop(
        _ items: [String],
        into section: String,
        before target: AppTask? = nil,
        board: [AppTask],
        span: [AppTask]? = nil,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        CadenceKanbanCardDrop.drop(
            items,
            intoColumn: section,
            before: target,
            columnTasks: board.filter { $0.resolvedSectionName.caseInsensitiveCompare(section) == .orderedSame },
            among: board,
            spanning: span ?? board,
            ofList: CadenceTaskDropSupport.containerKey(for: .inbox),
            in: modelContext,
            commit: commit
        )
    }

    @Test func aCardDroppedOnAnotherColumnIsFiledThereInOneCommit() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try boardTask("Moved by touch", section: "Backlog", in: modelContext)
        let seam = CountingCommit()

        let landed = drop([TaskDragPayload.string(for: task.id)], into: "Doing", board: [task], in: modelContext, commit: seam.commit)

        #expect(landed)
        #expect(task.sectionName == "Doing", "the drop answered true and left the card in its old column")
        #expect(seam.commitCount == 1)
    }

    /// The macOS column body's write, not a section-only one: the card goes to the END of the
    /// column it lands in and the list comes out numbered `0…n`, finished rows included. A
    /// section-only write left the card at its old `order`, so it landed wherever that number fell
    /// among its new neighbours — and macOS put it at the end.
    @Test func aDroppedCardGoesToTheEndOfItsNewColumnAndTheListIsRenumbered() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let moved = try boardTask("Moved", section: "Backlog", order: 0, in: modelContext)
        let doingA = try boardTask("Doing A", section: "Doing", order: 1, in: modelContext)
        let finished = try boardTask("Finished", section: "Doing", order: 2, in: modelContext)
        finished.status = .done
        let doingB = try boardTask("Doing B", section: "Doing", order: 3, in: modelContext)
        try modelContext.save()
        let board = [moved, doingA, doingB]

        #expect(drop([TaskDragPayload.string(for: moved.id)], into: "Doing", board: board, span: board + [finished], in: modelContext))

        #expect(moved.sectionName == "Doing")
        #expect(doingA.order < doingB.order && doingB.order < moved.order, "the card did not land after the column's cards")
        let orders = [moved, doingA, finished, doingB].map(\.order).sorted()
        #expect(orders == Array(0..<4), "the list was not renumbered 0…n: \(orders)")
    }

    /// A refused save puts the card back, so the board cannot draw a move the store never took.
    @Test func aRefusedDropAnswersFalseAndLeavesTheCardInItsColumn() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try boardTask("Refused", section: "Backlog", order: 4, in: modelContext)
        let seam = CountingCommit()
        seam.refuses = true

        let landed = drop([TaskDragPayload.string(for: task.id)], into: "Doing", board: [task], in: modelContext, commit: seam.commit)

        #expect(!landed)
        #expect(task.sectionName == "Backlog", "a refused drop left the new column on the task")
        #expect(task.order == 4, "a refused drop left the renumber on the task")
    }

    /// The column the card is already in: no write and no commit, and `false` so the card springs
    /// back rather than jumping to the bottom of the column it never left.
    @Test func aCardDroppedOnItsOwnColumnWritesNothing() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try boardTask("Stays put", section: "Doing", order: 0, in: modelContext)
        let below = try boardTask("Below", section: "Doing", order: 1, in: modelContext)
        let seam = CountingCommit()

        #expect(!drop([TaskDragPayload.string(for: task.id)], into: "doing", board: [task, below], in: modelContext, commit: seam.commit))
        #expect(seam.commitCount == 0, "a drop on the card's own column committed")
        #expect(task.sectionName == "Doing")
        #expect(task.order == 0, "a drop on the card's own column moved it to the end")
    }

    // MARK: - What a card dropped on the column's end slot writes ([[T-16503]])

    private func dropAtEnd(_ task: AppTask, into section: String, board: [AppTask], in modelContext: ModelContext,
                           commit: (ModelContext) throws -> Void = { try $0.save() }) -> Bool {
        CadenceKanbanCardDrop.drop(
            [TaskDragPayload.string(for: task.id)],
            intoColumn: section,
            at: .columnEnd,
            columnTasks: board.filter { $0.resolvedSectionName.caseInsensitiveCompare(section) == .orderedSame },
            among: board,
            spanning: board,
            ofList: CadenceTaskDropSupport.containerKey(for: .inbox),
            in: modelContext,
            commit: commit
        )
    }

    /// Red before the fix: nothing put a card below the last one of its own column. On the last
    /// card it went second-last, and the column body refused its own column.
    @Test func aCardDroppedOnItsOwnColumnsEndSlotBecomesTheLastCard() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let first = try boardTask("First", section: "Doing", order: 0, in: modelContext)
        let second = try boardTask("Second", section: "Doing", order: 1, in: modelContext)
        let third = try boardTask("Third", section: "Doing", order: 2, in: modelContext)
        let seam = CountingCommit()
        let board = [first, second, third]

        #expect(dropAtEnd(first, into: "Doing", board: board, in: modelContext, commit: seam.commit))

        #expect(seam.commitCount == 1)
        #expect(first.sectionName == "Doing")
        let column = board.sorted { $0.order < $1.order }.map(\.title)
        #expect(column == ["Second", "Third", "First"], "the card did not land below the column's last card: \(column)")
    }

    /// The end slot of another column files it there at the end, as the column body does.
    @Test func aCardDroppedOnAnotherColumnsEndSlotIsFiledAtItsEnd() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let moved = try boardTask("Moved", section: "Backlog", order: 0, in: modelContext)
        let doingA = try boardTask("Doing A", section: "Doing", order: 1, in: modelContext)
        let doingB = try boardTask("Doing B", section: "Doing", order: 2, in: modelContext)

        #expect(dropAtEnd(moved, into: "Doing", board: [moved, doingA, doingB], in: modelContext))

        #expect(moved.sectionName == "Doing")
        #expect(doingA.order < doingB.order && doingB.order < moved.order)
    }

    /// The body keeps its refusal: the end slot is the new target, not a looser body.
    @Test func theColumnBodyStillRefusesTheCardsOwnColumn() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = try boardTask("Stays put", section: "Doing", order: 0, in: modelContext)
        let below = try boardTask("Below", section: "Doing", order: 1, in: modelContext)
        let seam = CountingCommit()

        let landed = CadenceKanbanCardDrop.drop(
            [TaskDragPayload.string(for: task.id)], intoColumn: "Doing", at: .columnBody,
            columnTasks: [task, below], among: [task, below], spanning: [task, below],
            ofList: CadenceTaskDropSupport.containerKey(for: .inbox), in: modelContext, commit: seam.commit
        )
        #expect(!landed)
        #expect(seam.commitCount == 0)
        #expect(task.order == 0)
    }

    // MARK: - What a card dropped on a card writes ([[T-8271]])

    /// The ticket's case: a card dropped on a card ABOVE it in its own column lands in front of
    /// that card, in one commit. The column-only drop refused this outright.
    @Test func aCardDroppedOnACardInItsOwnColumnLandsInFrontOfIt() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let first = try boardTask("First", section: "Doing", order: 0, in: modelContext)
        let second = try boardTask("Second", section: "Doing", order: 1, in: modelContext)
        let third = try boardTask("Third", section: "Doing", order: 2, in: modelContext)
        let seam = CountingCommit()
        let board = [first, second, third]

        #expect(drop([TaskDragPayload.string(for: third.id)], into: "Doing", before: first, board: board, in: modelContext, commit: seam.commit))

        #expect(seam.commitCount == 1)
        #expect(third.sectionName == "Doing")
        let column = board.sorted { $0.order < $1.order }.map(\.title)
        #expect(column == ["Third", "First", "Second"], "the card did not land in front of the one it was dropped on: \(column)")
    }

    /// From another column, onto a card in the middle: refiled AND placed, not sent to the end.
    @Test func aCardDroppedOnACardInAnotherColumnIsFiledInFrontOfIt() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let moved = try boardTask("Moved", section: "Backlog", order: 0, in: modelContext)
        let doingA = try boardTask("Doing A", section: "Doing", order: 1, in: modelContext)
        let doingB = try boardTask("Doing B", section: "Doing", order: 2, in: modelContext)
        let board = [moved, doingA, doingB]

        #expect(drop([TaskDragPayload.string(for: moved.id)], into: "Doing", before: doingB, board: board, in: modelContext))

        #expect(moved.sectionName == "Doing")
        #expect(doingA.order < moved.order && moved.order < doingB.order, "the card did not land between the two it was dropped among")
        #expect(board.map(\.order).sorted() == Array(0..<3))
    }

    /// **[[T-17111]]: a card moved to another column leaves the rest of the list where it was.**
    /// The arriving card's old place is in the column it left, and the destination column's first
    /// card used to fill it -- so moving the top Backlog card to the end of Doing put "Doing A"
    /// above both remaining Backlog cards in the list's own order, the order the list's Tasks tab
    /// and All Tasks draw. Red before the fix: `["Doing A", "Backlog B", "Backlog C", "Moved"]`.
    @Test func aCardMovedToAnotherColumnLeavesTheOtherCardsInTheirListOrder() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let moved = try boardTask("Moved", section: "Backlog", order: 0, in: modelContext)
        let backlogB = try boardTask("Backlog B", section: "Backlog", order: 1, in: modelContext)
        let backlogC = try boardTask("Backlog C", section: "Backlog", order: 2, in: modelContext)
        let doingA = try boardTask("Doing A", section: "Doing", order: 3, in: modelContext)
        let board = [moved, backlogB, backlogC, doingA]

        #expect(drop([TaskDragPayload.string(for: moved.id)], into: "Doing", board: board, in: modelContext))

        #expect(moved.sectionName == "Doing")
        let list = board.sorted { $0.order < $1.order }.map(\.title)
        #expect(list == ["Backlog B", "Backlog C", "Doing A", "Moved"], "a card the drop never named changed places in the list: \(list)")
        #expect(board.map(\.order).sorted() == Array(0..<4))
    }

    /// The same rule with a target card: dropped in front of the column's second card, the moved
    /// card lands between the two and the column's first card keeps its place behind Backlog's.
    @Test func aCardDroppedInFrontOfACardInAnotherColumnMovesNoOtherCardInTheList() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let moved = try boardTask("Moved", section: "Backlog", order: 0, in: modelContext)
        let backlogB = try boardTask("Backlog B", section: "Backlog", order: 1, in: modelContext)
        let doingA = try boardTask("Doing A", section: "Doing", order: 2, in: modelContext)
        let doingB = try boardTask("Doing B", section: "Doing", order: 3, in: modelContext)
        let board = [moved, backlogB, doingA, doingB]

        #expect(drop([TaskDragPayload.string(for: moved.id)], into: "Doing", before: doingB, board: board, in: modelContext))

        let list = board.sorted { $0.order < $1.order }.map(\.title)
        #expect(list == ["Backlog B", "Doing A", "Moved", "Doing B"], "a card the drop never named changed places in the list: \(list)")
    }

    /// A card set down on itself writes nothing — macOS's `droppedID != target.id`.
    @Test func aCardDroppedOnItselfWritesNothing() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let above = try boardTask("Above", section: "Doing", order: 0, in: modelContext)
        let task = try boardTask("Self", section: "Doing", order: 1, in: modelContext)
        let seam = CountingCommit()

        #expect(!drop([TaskDragPayload.string(for: task.id)], into: "Doing", before: task, board: [above, task], in: modelContext, commit: seam.commit))
        #expect(seam.commitCount == 0, "a card dropped on itself committed")
        #expect(task.order == 1)
    }

    /// Only a card of this board. A task from another list is refused rather than half-moved, and
    /// the task that IS named is the one written.
    @Test func aPayloadNamingNoCardOfThisBoardIsRefused() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let ours = try boardTask("On this board", section: "Backlog", in: modelContext)
        let foreign = try boardTask("On another list", section: "Backlog", in: modelContext)

        for items in [
            [TaskDragPayload.string(for: foreign.id)],
            [TaskDragPayload.string(for: UUID())],
            [TaskDragPayload.bundleString(for: ours.id)],
            ["not a payload"],
            [],
        ] {
            #expect(!drop(items, into: "Doing", board: [ours], in: modelContext), "\(items) was accepted")
        }
        #expect(ours.sectionName == "Backlog")
        #expect(foreign.sectionName == "Backlog", "the drop wrote a task that is not on this board")

        #expect(drop([TaskDragPayload.string(for: ours.id)], into: "Doing", board: [foreign, ours], in: modelContext))
        #expect(ours.sectionName == "Doing")
        #expect(foreign.sectionName == "Backlog", "the drop wrote a task the payload did not name")
    }

    /// One write on two platforms ([[T-8201]]): macOS's card drop is the shared one, wrapped only in
    /// its animation — not a second copy of the renumber the iOS board would drift from.
    @Test func macOSsCardDropIsTheSharedWrite() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanBoardSupport.swift"))
        let reorder = try #require(CadenceSourceScan.declarationBody("static func reorder(", in: source))
        #expect(CadenceSourceScan.matchCount(#"CadenceKanbanCardDrop\.reorder\("#, in: reorder) == 1)
        #expect(CadenceSourceScan.matchCount(#"wholeSequence|\.order\s*="#, in: reorder) == 0,
                "KanbanBoardSupport.reorder renumbers by itself again")
    }

    // MARK: - The wiring, read from source

    private let cardFile = "Cadence/iOS/iOSBoardCards.swift"
    private let listBoardFile = "Cadence/iOS/iOSListSupportViews.swift"
    private let calendarBoardFile = "Cadence/iOS/iOSCalendarBoardView.swift"
    private let dragPayload = #"\.draggable\(TaskDragPayload\.string\(for: task\.id\)\)"#

    private func cardBody() throws -> String {
        let source = try CadenceSourceScan.sourceFile(cardFile)
        let card = try #require(CadenceSourceScan.declarationBody("struct iOSBoardTaskCard: View", in: source))
        #expect(card.count > 1_000, "non-vacuity: iOSBoardTaskCard read as \(card.count) characters")
        return card
    }

    /// [[T-8182]]: the card hosts the task row's own menu — one menu, not a board copy of it.
    @Test func theBoardCardHostsTheTaskRowsOwnContextMenu() throws {
        let card = try cardBody()
        #expect(
            CadenceSourceScan.matchCount(#"\.contextMenu\s*\{\s*iOSTaskRowContextMenu\("#, in: card) == 1,
            "the board card no longer opens the task action menu on a long press"
        )
    }

    /// [[T-9614]]: the lifted preview is outlined by the card's own rounded shape, not by the
    /// whole-card tap rectangle. Both halves are pinned: the preview shape at the card's radius and
    /// style, applied before the menu it outlines, and the tap rectangle still there.
    @Test func theLongPressPreviewIsOutlinedByTheCardsOwnRoundedShape() throws {
        let card = try cardBody()
        let preview = #"\.contentShape\(\s*\.contextMenuPreview,\s*RoundedRectangle\(cornerRadius: CadenceLedgerCardMetrics\.cornerRadius, style: \.continuous\)\s*\)"#
        #expect(CadenceSourceScan.matchCount(preview, in: card) == 1,
                "the board card's context-menu preview no longer takes the card's rounded outline")
        #expect(CadenceSourceScan.matchCount(#"\.contentShape\(Rectangle\(\)\)"#, in: card) == 1,
                "the board card lost the rectangle that lets the whole card take the tap")
        let previewAt = try #require(card.range(of: ".contextMenuPreview"))
        let menuAt = try #require(card.range(of: ".contextMenu {"))
        #expect(previewAt.lowerBound < menuAt.lowerBound,
                "the preview shape is applied after the context menu, outside the view it outlines")
        // The radius named is the one the card clips to, so the two cannot drift apart.
        let ledger = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceBoardLedgerCard.swift")
        #expect(CadenceSourceScan.matchCount(
            #"RoundedRectangle\(cornerRadius: CadenceLedgerCardMetrics\.cornerRadius, style: \.continuous\)"#,
            in: ledger) >= 1, "CadenceLedgerCard no longer clips to CadenceLedgerCardMetrics.cornerRadius")
    }

    /// Each question the menu asks has somewhere to be shown. Without these the menu's Delete,
    /// repeat-scope and refusal paths would set a flag that nothing on the board reads.
    @Test func everyStateTheMenuAsksForIsPresentedByTheCard() throws {
        let card = try cardBody()
        for modifier in [
            #"\.iOSTaskRowRecurrenceScopeDialog\("#,
            #"\.iOSTaskDeleteConfirmation\("#,
            #"\.iOSTaskDeleteFailureAlert\(isPresented: \$deleteFailed\)"#,
            #"\.iOSTaskMoveFailureAlert\(isPresented: \$moveFailed\)"#,
            #"\.iOSTaskRowRecurrenceFailureAlert\(isPresented: \$recurrenceFailed\)"#,
        ] {
            #expect(CadenceSourceScan.matchCount(modifier, in: card) == 1, "the card does not apply \(modifier)")
        }
    }

    /// The drag stays outside the card, at each call site, after the card's own context menu — the
    /// order `iOSTaskRow` uses. The card carrying it itself would put the drag *inside* the menu's
    /// modifier, and every board would have its card dragging whether it wanted that or not.
    @Test func everyBoardThatDrawsTheCardStillOffersItsDrag() throws {
        let card = try cardBody()
        #expect(CadenceSourceScan.matchCount(dragPayload, in: card) == 0)

        // The list board drew TWO from [[T-9837]] -- the column's open stack and the Completed
        // footer under it -- and draws ONE since [[T-15622]]: both stacks call the column's
        // `boardCard(_:)`, so the finished cards take a drop and draw the insertion line exactly
        // as the open ones do (`iOSListBoardCompletedColumnTests` pins that both stacks call it).
        // The Calendar Board draws two, its open stack and its footer.
        for (file, cards) in [(listBoardFile, 1), (calendarBoardFile, 2)] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(file))
            let drawn = CadenceSourceScan.matchCount(#"iOSBoardTaskCard\("#, in: source)
            let dragged = CadenceSourceScan.matchCount(
                #"iOSBoardTaskCard\([^)]*\)\s*\.draggable\(TaskDragPayload\.string\(for: task\.id\)\)"#,
                in: source
            )
            #expect(drawn == cards, "\(file) draws \(drawn) board cards, expected \(cards)")
            #expect(dragged == drawn, "\(file): \(drawn - dragged) board card(s) offer no drag")
        }
    }

    /// [[T-8183]]: the list board's column takes a card, and hands it to the shared write.
    @Test func theListBoardColumnTakesACardThroughTheSharedWrite() throws {
        let source = try CadenceSourceScan.sourceFile(listBoardFile)
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSListKanbanColumn: View", in: source)
        )
        #expect(column.count > 1_000, "non-vacuity: the column read as \(column.count) characters")
        #expect(CadenceSourceScan.matchCount(#"\.dropDestination\(for: String\.self\)"#, in: column) == 3,
                "the column, each card ([[T-8271]]) and the end slot ([[T-16503]]) are the three drop targets")
        #expect(CadenceSourceScan.matchCount(#"onDropCard\(items, nil\)"#, in: column) == 1, "the column body drops to the end")
        #expect(CadenceSourceScan.matchCount(#"onDropCard\(items, task\)"#, in: column) == 1, "a card is not a drop target")
        #expect(CadenceSourceScan.matchCount(#"onDropAtColumnEnd\(items\)"#, in: column) == 1, "the end slot is not a drop target")
        #expect(CadenceSourceScan.matchCount(#"if !tasks\.isEmpty \{\s*columnEndDropSlot\s*\}"#, in: column) == 1,
                "the column no longer draws its end slot under the last open card")

        let panel = try #require(
            CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: source)
        )
        #expect(
            CadenceSourceScan.matchCount(#"\{\s*items, slot in\s*CadenceKanbanCardDrop\.drop\("#, in: panel) == 1,
            "the board builds its columns without wiring their drop to the shared write"
        )
        #expect(
            CadenceSourceScan.matchCount(#"intoColumn: column\.title,\s*at: slot,"#, in: panel) == 1,
            "the board drops every card at the column's end whatever card it was set down on"
        )
        #expect(CadenceSourceScan.matchCount(#"onDropCard:\s*\{\s*items, target in\s*dropCard\(items, \.before\(target\)\)"#, in: panel) == 1,
                "a card or body drop no longer names the card it was set down on")
        #expect(CadenceSourceScan.matchCount(#"onDropAtColumnEnd:\s*\{\s*items in\s*dropCard\(items, \.columnEnd\)"#, in: panel) == 1,
                "the end slot's drop is not the column-end write")
    }
}
#endif
