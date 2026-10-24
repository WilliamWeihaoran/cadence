import Foundation
import Testing
@testable import Cadence

/// T-5013(a). **The Calendar Board's Overdue rail says it is empty instead of drawing 200pt of
/// nothing under "Overdue 0".**
///
/// That is the board's resting state for anyone who keeps up, which is why the owner declined
/// collapsing the rail: a rail that came and went would shift the whole board each time the count
/// crossed zero. The Unscheduled rail has an add row standing in the empty space and does not need
/// one; the Overdue rail has `nil` for `add` because a task cannot be created into being late, so
/// it is the one column that was genuinely blank.
#if os(macOS)
@Suite
struct CadenceOverdueRailEmptyLineTests {
    @Test func anEmptyOverdueRailDrawsTheInlineLine() {
        #expect(
            CalendarBoardRailEmptySupport.line(for: .overdue, taskCount: 0, add: nil)
                == CadenceEmptyStateCopy.nothingOverdueTitle
        )
    }

    @Test func anOverdueRailWithCardsDrawsNothing() {
        #expect(CalendarBoardRailEmptySupport.line(for: .overdue, taskCount: 1, add: nil) == nil)
        #expect(CalendarBoardRailEmptySupport.line(for: .overdue, taskCount: 9, add: nil) == nil)
    }

    /// A column with an add row is never actually blank — the ghost row stands in the space and
    /// says what the column is for. Drawing a sentence there as well would be two empty states
    /// stacked on one column.
    @Test func aRailWithAnAddRowDrawsNothingEvenWhenEmpty() {
        #expect(
            CalendarBoardRailEmptySupport.line(
                for: .unscheduled,
                taskCount: 0,
                add: .presentSheet({})
            ) == nil
        )
    }

    /// The rule is "no cards and no add row", not "this rail is Overdue": a second rail that ever
    /// lost its add row would want the line for the same reason.
    @Test func theRuleIsDerivedFromWhatTheColumnDrawsNotFromTheRailCase() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarBoardRailSupportViews.swift")
        let body = try #require(CadenceSourceScan.functionBody(named: "line", in: source))

        #expect(body.contains("taskCount == 0, add == nil"))
        #expect(CalendarBoardRailEmptySupport.line(for: .unscheduled, taskCount: 0, add: nil) != nil)
    }

    /// The sentence is the one on the shared copy enum and reads as a state, not an instruction:
    /// there is no control on this rail to point the user at.
    @Test func theSentenceIsTheSharedOne() {
        #expect(CadenceEmptyStateCopy.nothingOverdueTitle == "Nothing overdue")
    }
}
#endif
