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

/// **T-18637.** The Mac calendar picker's search field, under the [[T-14791]] rule above: the unlinked
/// row (id `""`) is always first, so a typed query used to leave the highlight on it when nothing was
/// linked, and a query that matched nothing left only that hidden row, which Return picked --
/// unlinking an area's or project's calendar on Save.
@MainActor
struct CadenceCalendarPickerKeyboardTests {
    private let none = CadenceCalendarPickerKeyboard.noneID
    private let work = "cal-work"
    private let home = "cal-home"

    @Test func aTypedQueryWithNothingLinkedHighlightsTheFirstCalendar() {
        let index = CadenceCalendarPickerKeyboard.highlightIndex(
            itemIDs: [none, work], selectedID: none, query: "Work", current: 0
        )
        #expect(index == 1)
        #expect(CadenceCalendarPickerKeyboard.submitTarget(itemIDs: [none, work], query: "Work", highlightIndex: index) == work)
    }

    @Test func aTypedQueryHighlightsTheFirstCalendarEvenWhenTheLinkedOneAlsoMatches() {
        #expect(CadenceCalendarPickerKeyboard.highlightIndex(
            itemIDs: [none, home, work], selectedID: work, query: "o", current: 0
        ) == 1)
    }

    @Test func returnOverACalendarQueryThatMatchedNothingUnlinksNothing() {
        #expect(CadenceCalendarPickerKeyboard.searchFoundNothing(itemIDs: [none], query: "zzz"))
        let index = CadenceCalendarPickerKeyboard.highlightIndex(itemIDs: [none], selectedID: work, query: "zzz", current: 2)
        #expect(index == 0)
        #expect(CadenceCalendarPickerKeyboard.submitTarget(itemIDs: [none], query: "zzz", highlightIndex: index) == nil)
        // allowNone off: nothing at all matched.
        #expect(CadenceCalendarPickerKeyboard.submitTarget(itemIDs: [], query: "zzz", highlightIndex: 0) == nil)
    }

    @Test func withNoQueryTheHighlightFollowsTheSelectionAndReturnCanUnlink() {
        #expect(CadenceCalendarPickerKeyboard.highlightIndex(itemIDs: [none, home, work], selectedID: work, query: "  ", current: 0) == 2)
        #expect(CadenceCalendarPickerKeyboard.highlightIndex(itemIDs: [none, home, work], selectedID: none, query: "", current: 2) == 0)
        #expect(!CadenceCalendarPickerKeyboard.searchFoundNothing(itemIDs: [none], query: ""))
        #expect(CadenceCalendarPickerKeyboard.submitTarget(itemIDs: [none, home, work], query: "", highlightIndex: 0) == none)
    }

    @Test func anOutOfRangeCalendarHighlightPicksNothing() {
        #expect(CadenceCalendarPickerKeyboard.submitTarget(itemIDs: [none, work], query: "", highlightIndex: 5) == nil)
        #expect(CadenceCalendarPickerKeyboard.highlightIndex(itemIDs: [], selectedID: none, query: "w", current: 3) == 0)
        #expect(CadenceCalendarPickerKeyboard.highlightIndex(itemIDs: [none, home], selectedID: "gone", query: "", current: 7) == 1)
    }

    /// The view reads the helper for both the highlight and Return, rather than its own rule.
    @Test func thePickerRoutesItsKeyboardThroughTheHelper() throws {
        let file = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/CadenceCalendarPicker.swift"))
        let list = try #require(CadenceSourceScan.declarationBody("struct CadenceCalendarPickerList: View", in: file))
        #expect(list.contains("CadenceCalendarPickerKeyboard.submitTarget("))
        #expect(list.contains("CadenceCalendarPickerKeyboard.highlightIndex("))
        #expect(list.contains("if searchFoundNothing || (groups.isEmpty && !allowNone) {"))
    }
}
#endif
