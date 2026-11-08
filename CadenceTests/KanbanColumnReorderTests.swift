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
#endif
