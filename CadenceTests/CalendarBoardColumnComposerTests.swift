import Foundation
import Testing
@testable import Cadence

// Cmd+N is documented as "open the inline composer in the hovered kanban column". Whether a given
// board column answers it is decided by one question — does this column's add affordance open the
// *inline composer* — and the Calendar Board's day columns got that wrong for a while: they never
// registered with `HoveredKanbanColumnManager` at all, so the shortcut silently did nothing over a
// day column while working over the other two boards.
//
// The registration itself is a SwiftUI `.onHover`, which no unit test can drive. What is pinned
// here is the decision it branches on, plus the identity it registers under.
#if os(macOS)
@Suite
@MainActor
struct CalendarBoardColumnComposerTests {

    // MARK: - Which columns Cmd+N may open

    @Test func composeBehaviorOpensTheInlineComposer() {
        let behavior = KanbanColumnAddBehavior.compose(.day(dateKey: "2026-06-18", startMin: -1))
        #expect(behavior.opensInlineComposer)
    }

    @Test func presentSheetBehaviorDoesNotOpenTheInlineComposer() {
        // The Unscheduled rail. A backlog has neither a day nor a list to seed, so it deliberately
        // opens the full create sheet — and Cmd+N must not resolve to a modal under the pointer.
        let behavior = KanbanColumnAddBehavior.presentSheet {}
        #expect(!behavior.opensInlineComposer)
    }

    @Test func absentBehaviorDoesNotOpenTheInlineComposer() {
        // The Overdue rail: no add affordance at all, because a task cannot be created *into* being
        // late.
        let behavior: KanbanColumnAddBehavior? = nil
        #expect(!behavior.opensInlineComposer)
    }

    // MARK: - The board's own targets, resolved the way the board resolves them

    @Test func dayColumnsComposeAndTheRailsDoNot() {
        #expect(composerOpens(for: .day("2026-06-18")))
        #expect(!composerOpens(for: .rail(.unscheduled)))
        #expect(!composerOpens(for: .rail(.overdue)))
    }

    /// Mirrors `CalendarPageBoardSupportViews.addBehavior(for:)`: the add action a target declares,
    /// turned into the column behavior the board hands to `KanbanColumnScroll`.
    private func composerOpens(for target: CalendarBoardDropTarget) -> Bool {
        let behavior: KanbanColumnAddBehavior?
        switch CalendarBoardPlannerSupport.addAction(for: target) {
        case .none:
            behavior = nil
        case .presentCreateSheet:
            behavior = .presentSheet {}
        case .insertInline(let dateKey):
            behavior = .compose(.day(dateKey: dateKey, startMin: -1))
        }
        return behavior.opensInlineComposer
    }

    // MARK: - What the hover registers under

    @Test func hoverIDIsKeyedByDayNotByColumnIndex() {
        // The board slides its render window, so column index 3 is a different day after a
        // recenter. Keying the hover by index would let Cmd+N compose into whichever day had
        // drifted into that slot.
        #expect(
            CalendarBoardDayColumn.hoverID(dateKey: "2026-06-18")
                != CalendarBoardDayColumn.hoverID(dateKey: "2026-06-19")
        )
        #expect(
            CalendarBoardDayColumn.hoverID(dateKey: "2026-06-18")
                == CalendarBoardDayColumn.hoverID(dateKey: "2026-06-18")
        )
    }

    @Test func hoverIDDoesNotCollideWithTheOtherBoardsColumnIDs() {
        // `HoveredKanbanColumnManager` is a single global keyed by `AnyHashable`; two surfaces
        // sharing a key would let one column's hover end another's registration.
        let dayID = CalendarBoardDayColumn.hoverID(dateKey: "2026-06-18")
        #expect(!dayID.hasPrefix("kanban-list-column-"))   // TaskListKanbanColumn
        #expect(!dayID.hasPrefix("kanban-column-"))        // ListSectionKanbanColumn
    }
}
#endif
