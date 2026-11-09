#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-14791.** The Mac context picker's search field: Return over a typed query picks the first
/// matching context, and Return over a query that matched nothing picks nothing. It used to pick the
/// "No context" row in both cases, so typing `Wor` + Return with no context set did nothing, and a
/// typo + Return cleared an area's or project's context on Save.
@MainActor
struct CadenceContextPickerKeyboardTests {
    private let workID = UUID()
    private let homeID = UUID()

    private var none: CadencePickerItem { CadencePickerItem(id: nil, title: "No context", icon: nil, colorHex: nil) }
    private var work: CadencePickerItem { CadencePickerItem(id: workID, title: "Work", icon: nil, colorHex: nil) }
    private var home: CadencePickerItem { CadencePickerItem(id: homeID, title: "Home", icon: nil, colorHex: nil) }

    @Test func aTypedQueryHighlightsTheFirstMatchNotTheNoContextRow() {
        let index = CadenceContextPickerKeyboard.highlightIndex(
            items: [none, work],
            selectedID: nil,
            query: "Wor",
            current: 0
        )
        #expect(index == 1)
        let target = CadenceContextPickerKeyboard.submitTarget(items: [none, work], query: "Wor", highlightIndex: index)
        #expect(target == .some(workID))
    }

    @Test func aTypedQueryHighlightsTheFirstMatchEvenWhenTheSelectionAlsoMatches() {
        let index = CadenceContextPickerKeyboard.highlightIndex(
            items: [none, home, work],
            selectedID: workID,
            query: "o",
            current: 2
        )
        #expect(index == 1)
    }

    @Test func returnOverAQueryThatMatchedNothingPicksNothing() {
        #expect(CadenceContextPickerKeyboard.searchFoundNothing(items: [none], query: "xyz"))
        let index = CadenceContextPickerKeyboard.highlightIndex(items: [none], selectedID: workID, query: "xyz", current: 1)
        #expect(index == 0)
        let target = CadenceContextPickerKeyboard.submitTarget(items: [none], query: "xyz", highlightIndex: index)
        #expect(target == nil)
    }

    @Test func withNoQueryTheHighlightFollowsTheSelectionAndReturnCanPickNoContext() {
        #expect(CadenceContextPickerKeyboard.highlightIndex(items: [none, home, work], selectedID: workID, query: "  ", current: 0) == 2)
        #expect(CadenceContextPickerKeyboard.highlightIndex(items: [none, home, work], selectedID: nil, query: "", current: 2) == 0)
        #expect(!CadenceContextPickerKeyboard.searchFoundNothing(items: [none], query: ""))
        let target = CadenceContextPickerKeyboard.submitTarget(items: [none, home, work], query: "", highlightIndex: 0)
        #expect(target == .some(nil))
    }

    @Test func anOutOfRangeHighlightPicksNothing() {
        #expect(CadenceContextPickerKeyboard.submitTarget(items: [none, work], query: "", highlightIndex: 5) == nil)
        #expect(CadenceContextPickerKeyboard.submitTarget(items: [], query: "", highlightIndex: 0) == nil)
        #expect(CadenceContextPickerKeyboard.highlightIndex(items: [], selectedID: nil, query: "w", current: 3) == 0)
    }
}
#endif
