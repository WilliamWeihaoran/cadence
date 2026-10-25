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

/// T-5013(b). **iOS Search draws an idle line instead of leaving the scope picker over blank
/// space.**
///
/// `resultSection` draws nothing for an empty array and the "No results" panel is gated on
/// `isSearching`, so narrowing to Notes / Lists / Events with nothing to suggest left the picker
/// sitting on nothing. macOS's `GlobalSearchEmptyState` has had an idle state for exactly this.
///
/// This half was written on 2026-10-24, backed out because `iOSSearchView.swift` was fenced, and
/// re-applied once the fence was withdrawn at `741a9366` -- the job it was held for never started.
@Suite
struct CadenceSearchIdleLineTests {
    @Test func theIdleLineNamesTheNarrowedScope() {
        #expect(CadenceEmptyStateCopy.searchIdleTitle(scopeNoun: "notes") == "Start typing to search notes")
    }

    /// On **All** there is no one kind of thing to name, and "search all" says less than "search".
    @Test func theIdleLineNamesNoScopeOnAll() {
        #expect(CadenceEmptyStateCopy.searchIdleTitle(scopeNoun: nil) == "Start typing to search")
    }

    /// `Cadence/iOS/` sits inside `#if os(iOS)` and is invisible to this macOS-built target, so the
    /// phone's half is pinned by reading its source -- the same way `iOSCalendarMetricsTests` pins
    /// the chips it cannot construct.
    @Test func everyNarrowedScopeHasANounAndAllHasNone() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchSupportViews.swift")
        let body = try #require(CadenceSourceScan.declarationBody("var idleNoun: String?", in: source))

        #expect(body.contains("case .all: return nil"))
        for scope in ["tasks", "lists", "notes", "events", "progress"] {
            #expect(body.contains("case .\(scope): return \""), "\(scope)")
        }
    }

    /// **More** is a chip label, not a noun: "start typing to search more" is not a sentence, so
    /// `.progress` must not answer its own title.
    @Test func theMoreChipDoesNotNameItselfInTheSentence() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchSupportViews.swift")
        let body = try #require(CadenceSourceScan.declarationBody("var idleNoun: String?", in: source))

        #expect(body.contains("case .progress: return \"pages\""))
        #expect(!body.lowercased().contains("return \"more\""))
    }

    /// The idle branch must be gated on `!isSearching`, or it would draw under a query that simply
    /// matched nothing -- on top of the "No results" panel that already answers that. It must also
    /// honour the calendar-access card for [[T-6113]]'s reason.
    @Test func theIdleBranchIsGatedOnNotSearchingAndDefersToTheAccessCard() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")

        #expect(source.contains("if !isSearching && visibleResultsAreEmpty && !calendarAccessCardReplacesNoResults {"))
        #expect(source.contains("CadenceEmptyStateCopy.searchIdleTitle(scopeNoun: scope.idleNoun)"))
        // The one-line component at the touch tier, not the 220pt panel: nothing has been searched
        // yet, so the panel's "try a tag or section name" answers a question nobody asked.
        #expect(source.contains("surface: .touch"))
    }

    /// Both branches exist and are mutually exclusive: one `isSearching` panel, one `!isSearching`
    /// line. A tree with only one of them is the state this entry closed or the state before it.
    @Test func theSearchingAndIdleBranchesAreBothPresent() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")

        #expect(source.contains("if isSearching && visibleResultsAreEmpty && !calendarAccessCardReplacesNoResults {"))
        #expect(source.contains("if !isSearching && visibleResultsAreEmpty && !calendarAccessCardReplacesNoResults {"))
    }
}
