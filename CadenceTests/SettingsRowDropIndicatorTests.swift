#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-18634]] — the Settings Contexts and Sidebar rows draw a line on the edge the drop lands
/// on, read off the order the pane will draw once that drop is written.**
///
/// [[T-18630]] made both drags put the dragged row in the target's slot (a downward drop after it,
/// an upward one before it) but left the whole-row wash, which says neither. The edge is computed
/// from the post-drop order rather than from the two indices, so it cannot disagree with the
/// drop -- the Focus row, which takes a drop but draws last, is the case where the two differ.
@MainActor
struct SettingsRowDropIndicatorTests {
    private struct Row: Identifiable, Equatable {
        let id: String
    }

    private let rows = ["A", "B", "C", "D"].map(Row.init)

    /// The edge for dragging `dragged` onto `target` in the contexts' wiring: the drop is
    /// `CadenceOrderReassignment.moved(_:_:onto:)`.
    private func contextEdge(_ dragged: String?, onto target: String) -> SidebarListDropPlacement.Edge? {
        SettingsRowDropIndicator.edge(
            dragged: dragged,
            target: target,
            drawn: rows.map(\.id),
            afterDrop: dragged.flatMap { CadenceOrderReassignment.moved(rows, $0, onto: target)?.map(\.id) }
        )
    }

    @Test func aDownwardDragDrawsTheTargetsBottomEdge() {
        #expect(contextEdge("A", onto: "B") == .bottom)
        #expect(contextEdge("A", onto: "D") == .bottom)
        #expect(contextEdge("B", onto: "C") == .bottom)
    }

    @Test func anUpwardDragDrawsTheTargetsTopEdge() {
        #expect(contextEdge("D", onto: "C") == .top)
        #expect(contextEdge("D", onto: "A") == .top)
        #expect(contextEdge("C", onto: "B") == .top)
    }

    @Test func aDropThatMovesNothingDrawsNoLine() {
        #expect(contextEdge("B", onto: "B") == nil, "the row onto itself")
        #expect(contextEdge(nil, onto: "B") == nil, "no drag in flight")
        #expect(contextEdge("Z", onto: "B") == nil, "a payload this pane does not draw")
    }

    /// The line agrees with where the drop puts the row, for every pair: the dragged row sits
    /// directly below the target after a bottom-edge line, directly above it after a top-edge one.
    @Test func everyLineNamesTheSideTheDroppedRowSitsOn() throws {
        var checked = 0
        for dragged in rows.map(\.id) {
            for target in rows.map(\.id) where target != dragged {
                let after = try #require(CadenceOrderReassignment.moved(rows, dragged, onto: target)).map(\.id)
                let draggedIndex = try #require(after.firstIndex(of: dragged))
                let targetIndex = try #require(after.firstIndex(of: target))
                let edge = try #require(contextEdge(dragged, onto: target))
                #expect(draggedIndex == targetIndex + (edge == .bottom ? 1 : -1), "\(dragged) onto \(target)")
                checked += 1
            }
        }
        #expect(checked == 12)
    }

    // MARK: - Sidebar pane

    private func sidebarEdge(
        _ dragged: SidebarStaticDestination,
        onto target: SidebarStaticDestination
    ) -> SidebarListDropPlacement.Edge? {
        let layout = CadenceSidebarLayoutPreferenceStore.Layout()
        let drawn = CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(for: layout)
            .compactMap(\.sidebarStaticDestination)
        return SettingsRowDropIndicator.edge(
            dragged: dragged,
            target: target,
            drawn: drawn,
            afterDrop: SettingsRowDropIndicator.sidebarTabs(afterDropping: dragged, onto: target, in: layout)
        )
    }

    @Test func theSidebarPaneDrawsTheEdgeByDirection() throws {
        let drawn = CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(for: .init())
            .compactMap(\.sidebarStaticDestination)
            .filter { CadenceSidebarLayout.isOrderable($0.feature) }
        #expect(drawn.count >= 3, "non-vacuity: at least three orderable rows")
        let first = drawn[0], second = drawn[1], last = drawn[drawn.count - 1]
        #expect(sidebarEdge(first, onto: second) == .bottom)
        #expect(sidebarEdge(first, onto: last) == .bottom)
        #expect(sidebarEdge(last, onto: first) == .top)
        #expect(sidebarEdge(second, onto: first) == .top)
    }

    /// Focus takes a drop but sorts last as a footer glyph, so a nav row dropped on it is drawn
    /// directly ABOVE it -- the top edge, though the drag runs downward -- and the last nav row,
    /// already there, draws no line at all.
    @Test func aDropOnFocusDrawsItsTopEdgeOrNothing() throws {
        let drawn = CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(for: .init())
            .compactMap(\.sidebarStaticDestination)
        let focus = try #require(drawn.last)
        #expect(!CadenceSidebarLayout.isOrderable(focus.feature), "non-vacuity: Focus still sorts last, unorderable")
        let orderable = drawn.dropLast()
        #expect(orderable.count >= 2)
        #expect(sidebarEdge(orderable[orderable.startIndex], onto: focus) == .top)
        #expect(sidebarEdge(orderable[orderable.endIndex - 1], onto: focus) == nil)
    }

    // MARK: - Wiring

    /// Both rows draw the line from the edge and the whole-row wash is gone.
    @Test func bothSettingsRowsDrawTheEdgeLineInsteadOfTheWash() throws {
        let support = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsSupportViews.swift")
        )
        for declaration in ["struct ContextSettingsRow: View", "struct SidebarTabSettingsRow: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: support), "\(declaration) is gone")
            #expect(body.contains("SettingsRowDropLine(edge: dropLineEdge)"), "\(declaration) draws no edge line")
            #expect(body.contains("SettingsRowDragContext.shared.begin("), "\(declaration) does not record its drag")
            #expect(body.contains("SettingsRowDragContext.shared.end()"), "\(declaration) leaves its drag in flight on a drop")
            #expect(!body.contains("Theme.blue.opacity(0.10)"), "\(declaration) washes the whole row again")
        }
    }
}
#endif
