// macOS only: `KanbanBoardSupport` lives behind `#if os(macOS)` in `Cadence/macOS/Views/`.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-13931]]: a Mac Kanban column dropped on another column lands where it was let go.**
///
/// `KanbanBoardSupport.reorderedSectionConfigs` inserted the moving column *before* the target in
/// both directions. Dragged leftwards that is the target's slot; dragged rightwards it is one short
/// of it, so a column dropped on its right-hand neighbour did not move at all, and no column could
/// ever be put last -- the board has no drop target after its final column.
struct KanbanColumnReorderTests {
    private func columns(_ names: [String], archived: Set<String> = []) -> [TaskSectionConfig] {
        names.map { TaskSectionConfig(name: $0, isArchived: archived.contains($0)) }
    }

    private func reordered(_ names: [String], moving: String, onto target: String, archived: Set<String> = []) -> [String] {
        KanbanBoardSupport.reorderedSectionConfigs(
            columns(names, archived: archived),
            movingName: moving,
            targetName: target
        ).map(\.name)
    }

    private let board = [TaskSectionDefaults.defaultName, "Todo", "Doing", "Done"]

    /// Red before the fix: the answer was the board unchanged.
    @Test func aColumnDroppedOnItsRightNeighbourMovesPastIt() {
        #expect(
            reordered(board, moving: "Todo", onto: "Doing") == [TaskSectionDefaults.defaultName, "Doing", "Todo", "Done"]
        )
    }

    /// Red before the fix: the column stopped one short of the last slot.
    @Test func aColumnDroppedOnTheLastColumnBecomesTheLastColumn() {
        #expect(
            reordered(board, moving: "Todo", onto: "Done") == [TaskSectionDefaults.defaultName, "Doing", "Done", "Todo"]
        )
    }

    /// Unchanged by the fix: a leftward drop already took the target's slot.
    @Test func aColumnDroppedLeftwardsLandsBeforeTheTarget() {
        #expect(
            reordered(board, moving: "Done", onto: "Todo") == [TaskSectionDefaults.defaultName, "Done", "Todo", "Doing"]
        )
        #expect(
            reordered(board, moving: "Done", onto: "Doing") == [TaskSectionDefaults.defaultName, "Todo", "Done", "Doing"]
        )
    }

    /// Every rightward drop moves the column to the target's visible position -- the relation, over
    /// every pair, rather than one example.
    @Test func everyDropPutsTheColumnAtTheTargetsIndex() {
        let names = [TaskSectionDefaults.defaultName, "A", "B", "C", "D", "E"]
        var checked = 0
        for moving in names.dropFirst() {
            for target in names.dropFirst() where target != moving {
                let result = reordered(names, moving: moving, onto: target)
                #expect(result.firstIndex(of: moving) == names.firstIndex(of: target), "\(moving) onto \(target): \(result)")
                #expect(Set(result) == Set(names) && result.count == names.count)
                checked += 1
            }
        }
        #expect(checked == 20, "non-vacuity: every ordered pair of the five user columns")
    }

    /// A hidden archived column between the two does not swallow the move: the board hands in the
    /// whole blob, and the moved column must still pass the visible target.
    @Test func aHiddenArchivedColumnBetweenDoesNotSwallowTheMove() {
        let names = [TaskSectionDefaults.defaultName, "Todo", "Parked", "Doing"]
        let result = reordered(names, moving: "Todo", onto: "Doing", archived: ["Parked"])
        let visible = result.filter { $0 != "Parked" }
        #expect(visible == [TaskSectionDefaults.defaultName, "Doing", "Todo"])
    }

    /// The Default column stays first, and a drop on itself or on an unknown name changes nothing.
    @Test func defaultStaysFirstAndNoOpDropsChangeNothing() {
        #expect(reordered(board, moving: "Done", onto: TaskSectionDefaults.defaultName).first == TaskSectionDefaults.defaultName)
        #expect(reordered(board, moving: "Doing", onto: "doing") == board)
        #expect(reordered(board, moving: "Doing", onto: "Missing") == board)
    }
}
/// **[[T-16500]]: a Mac Kanban column let go over another column's CARDS reorders the board.**
///
/// A section column's cards are drop targets nested inside the column's, and the innermost one
/// under the pointer takes the drop. The card handler (`ListSectionKanbanColumn.handleTaskDrop`)
/// parsed only card payloads, so a column dragged by its header and released over a card -- most
/// of a filled column's height -- was refused: nothing moved, and the dragged column stayed faded,
/// because only `onReorderBefore` clears the board's drag state.
struct KanbanColumnDropOverCardTests {
    private let target = UUID()

    /// Red before the fix: a column payload over a card was `.refuse`.
    @Test func aColumnDroppedOnACardReordersTheColumns() {
        #expect(
            KanbanBoardSupport.sectionCardDrop(["\(kanbanSectionDragPrefix)Doing"], onto: target)
                == .reorderColumn("Doing")
        )
    }

    /// The column payload is read the same way over a card and over the column body.
    @Test func theCardAndTheColumnBodyReadTheSameColumnName() {
        let payload = "\(kanbanSectionDragPrefix)In Review"
        #expect(KanbanBoardSupport.draggedColumnName(from: payload) == "In Review")
        #expect(KanbanBoardSupport.sectionCardDrop([payload], onto: target) == .reorderColumn("In Review"))
        #expect(KanbanBoardSupport.draggedColumnName(from: UUID().uuidString) == nil)
    }

    /// Unchanged: a card still lands in front of the card it was dropped on, and a card dropped on
    /// itself or an empty payload does nothing.
    @Test func cardDropsAreUnchanged() {
        let dropped = UUID()
        #expect(KanbanBoardSupport.sectionCardDrop([TaskDragPayload.string(for: dropped)], onto: target) == .moveCard(dropped))
        #expect(KanbanBoardSupport.sectionCardDrop([dropped.uuidString], onto: target) == .moveCard(dropped))
        #expect(KanbanBoardSupport.sectionCardDrop([target.uuidString], onto: target) == .refuse)
        #expect(KanbanBoardSupport.sectionCardDrop([], onto: target) == .refuse)
        #expect(KanbanBoardSupport.sectionCardDrop(["not a payload"], onto: target) == .refuse)
    }

    /// The wiring: every card of a section column -- open and finished -- drops through
    /// `handleTaskDrop`, and that hands a column payload to `onReorderBefore`.
    @Test func theSectionColumnsCardDropHandsAColumnToTheBoardReorder() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift")
        let body = try #require(CadenceSourceScan.declarationBody("private func handleTaskDrop(", in: source))
        #expect(body.contains("KanbanBoardSupport.sectionCardDrop(items, onto: target.id)"))
        #expect(body.contains("case .reorderColumn(let movingName):"))
        #expect(body.contains("return onReorderBefore(movingName)"))
        let cardDrops = source.components(separatedBy: "handleTaskDrop(items: items, before: task)").count - 1
        #expect(cardDrops == 2, "the open cards and the finished cards: \(cardDrops)")
    }
}

/// **[[T-16502]]: a column drag that ends on no column ends anyway.**
///
/// The board's drag state was set in `.onDrag` and cleared only by a column's drop, and SwiftUI
/// says nothing when a drag ends. Released over the add-column rail, outside the board, or
/// cancelled with Esc, the dragged column stayed faded and every other column drew the column-drop
/// bar under the next card drag. The board now ends it when the pointer comes up.
@MainActor
struct KanbanColumnDragEndTests {
    /// Red before the fix: nothing but a column's drop ever cleared the drag.
    @Test func aDragReleasedOverNoColumnLeavesNoColumnFaded() {
        var drag = KanbanColumnDrag()
        let generation = drag.begin("Doing")
        #expect(drag.isDragging("doing"))
        #expect(drag.isDraggingAnother(than: "Todo"))

        drag.pointerReleased(generation: generation)

        #expect(!drag.isDragging("Doing"), "the released column is still drawn faded")
        #expect(!drag.isDraggingAnother(than: "Todo"), "another column still draws the column-drop bar")
        #expect(drag.sectionName == nil)
    }

    /// A release watched for an older drag cannot end the one in flight.
    @Test func aStaleReleaseDoesNotEndANewerDrag() {
        var drag = KanbanColumnDrag()
        let first = drag.begin("Doing")
        let second = drag.begin("Todo")
        #expect(first != second)

        drag.pointerReleased(generation: first)

        #expect(drag.isDragging("Todo"), "an earlier drag's release ended the newer one")
        drag.pointerReleased(generation: second)
        #expect(drag.sectionName == nil)
    }

    /// A column's drop still ends the drag, and the dragged column is not a place it lands.
    @Test func aDropEndsTheDragAndTheDraggedColumnIsNotATarget() {
        var drag = KanbanColumnDrag()
        _ = drag.begin("Doing")
        #expect(!drag.isDraggingAnother(than: "DOING"))
        drag.end()
        #expect(drag.sectionName == nil)
        #expect(!drag.isDraggingAnother(than: "Todo"))
    }

    /// The wait returns once the button is up, having asked until then -- not before, not never.
    @Test func theWaitReturnsOnceThePointerIsUp() async {
        var answers = [true, true, true, false]
        var asked = 0
        await KanbanColumnDrag.waitForPointerRelease(every: .milliseconds(1)) {
            asked += 1
            return answers.isEmpty ? false : answers.removeFirst()
        }
        #expect(asked == 4, "the wait asked \(asked) times; the button came up on the fourth")
    }

    /// The wiring: the board's drag starts the release watch, both ends clear the drag, and the
    /// columns read the drag's own answers.
    @Test func theBoardEndsAColumnDragOnRelease() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        )
        #expect(CadenceSourceScan.matchCount(#"endColumnDragOnRelease\(columnDrag\.begin\(section\.name\)\)"#, in: source) == 1,
                "the column drag no longer watches for its release")
        #expect(CadenceSourceScan.matchCount(#"columnDrag\.pointerReleased\(generation: generation\)"#, in: source) == 1)
        #expect(CadenceSourceScan.matchCount(#"NSEvent\.pressedMouseButtons & 1 != 0"#, in: source) == 1)
        #expect(CadenceSourceScan.matchCount(#"columnDrag\.end\(\)"#, in: source) == 1, "a column's drop no longer ends the drag")
        #expect(CadenceSourceScan.matchCount(#"draggingSectionName"#, in: source) == 0, "a second drag state is back")
        #expect(CadenceSourceScan.matchCount(#"isBeingDragged: columnDrag\.isDragging\(section\.name\)"#, in: source) == 1)
        #expect(CadenceSourceScan.matchCount(#"isAnotherSectionBeingDragged: columnDrag\.isDraggingAnother\(than: section\.name\)"#, in: source) == 1)
    }
}
#endif
