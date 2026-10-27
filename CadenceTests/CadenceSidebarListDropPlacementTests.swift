#if os(macOS)
import Testing
@testable import Cadence

/// The Mac sidebar's list drag: the insertion line must sit on the edge the dropped row lands
/// against (T-7255). It was pinned to the target's top edge for every drag, so a downward drag
/// landed one row below the line.
struct CadenceSidebarListDropPlacementTests {
    private let rows = ["A", "B", "C", "D", "E"]

    /// Every move within one five-row section: a top line means the row lands directly above the
    /// target, a bottom line directly below it, and no line means nothing moves.
    @Test func theLineSitsOnTheEdgeTheDroppedRowLandsAgainst() {
        var bottomCount = 0
        var topCount = 0
        for from in rows.indices {
            for to in rows.indices {
                let result = SidebarListDropPlacement.reordered(rows, moving: from, onto: to)
                let dragged = rows[from]
                let target = rows[to]
                let draggedAt = result.firstIndex(of: dragged)!
                let targetAt = result.firstIndex(of: target)!
                switch SidebarListDropPlacement.indicatorEdge(draggedIndex: from, targetIndex: to) {
                case .top:
                    topCount += 1
                    #expect(draggedAt + 1 == targetAt, "\(dragged) onto \(target): line above, row landed at \(result)")
                case .bottom:
                    bottomCount += 1
                    #expect(draggedAt == targetAt + 1, "\(dragged) onto \(target): line below, row landed at \(result)")
                case nil:
                    #expect(result == rows, "\(dragged) onto \(target): no line, yet the order changed")
                }
            }
        }
        // 20 off-diagonal pairs, half each way.
        #expect(topCount == 10)
        #expect(bottomCount == 10)
    }

    /// The case the owner hits most: dragging a row onto the one just below it swaps them, so the
    /// line belongs under that row, not on the boundary the dragged row already sits on.
    @Test func dragOntoTheNextRowDownDrawsTheLineUnderIt() {
        #expect(SidebarListDropPlacement.reordered(rows, moving: 0, onto: 1) == ["B", "A", "C", "D", "E"])
        #expect(SidebarListDropPlacement.indicatorEdge(draggedIndex: 0, targetIndex: 1) == .bottom)
        #expect(SidebarListDropPlacement.indicatorEdge(draggedIndex: 3, targetIndex: 2) == .top)
    }

    /// A row from another section is not in this one's entries, and its drop changes nothing here,
    /// so no line is drawn either.
    @Test func aRowFromAnotherSectionDrawsNoLine() {
        #expect(SidebarListDropPlacement.indicatorEdge(draggedIndex: nil, targetIndex: 2) == nil)
        #expect(SidebarListDropPlacement.indicatorEdge(draggedIndex: 2, targetIndex: 2) == nil)
    }
}
#endif
