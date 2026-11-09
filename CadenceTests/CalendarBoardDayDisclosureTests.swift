import Foundation
import Testing
@testable import Cadence

/// **[[T-14601]]: a day column's Completed fold, and the Mac's inline composer, belong to the day,
/// not to the column slot.**
///
/// Both Calendar Boards lay their day columns out as `ForEach(0..<renderDays)` over a render window
/// whose start moves -- a date jump re-anchors it, midnight re-floors it, a long scroll recenters it
/// -- so the column view at an index is a slot whose date changes. The fold and composer were
/// `@State` on that slot, and an open one moved onto whichever day slid into it. They are now held
/// by the board in `CalendarBoardDayDisclosures`, keyed by date key.
@Suite
struct CalendarBoardDayDisclosureTests {
    /// `.current`, because `DateFormatters.dateKey(from:)` spells a key in the current calendar.
    private let calendar = Calendar.current

    private func day(_ key: String) throws -> Date {
        try #require(DateFormatters.date(from: key, in: calendar))
    }

    /// The precondition of the leak: the iOS board re-anchors its window at
    /// `anchor - plannerLeadingDayCount` on every jump, so two different anchors land on the SAME
    /// index -- the same column view -- with different dates.
    @Test func aReanchorPutsTwoDifferentDaysOnTheSameColumnSlot() throws {
        let renderDays = CalendarBoardPlannerSupport.plannerRenderDayCount
        let lead = CalendarBoardPlannerSupport.plannerLeadingDayCount
        let first = try day("2026-11-09")
        let second = try day("2026-11-10")
        let firstStart = try #require(calendar.date(byAdding: .day, value: -lead, to: first))
        let secondStart = try #require(calendar.date(byAdding: .day, value: -lead, to: second))
        let firstIndex = CalendarBoardPlannerSupport.dayIndex(for: first, bufferStart: firstStart, calendar: calendar, renderDays: renderDays)
        let secondIndex = CalendarBoardPlannerSupport.dayIndex(for: second, bufferStart: secondStart, calendar: calendar, renderDays: renderDays)
        #expect(firstIndex == lead)
        #expect(firstIndex == secondIndex, "two anchors no longer share a slot; this suite's premise changed")
    }

    /// A fold opened on one day stays with that day across a window move, and the day that slid
    /// into its old slot is collapsed.
    @Test func anExpandedFoldTravelsWithItsDayAcrossAWindowMove() throws {
        let lead = CalendarBoardPlannerSupport.plannerLeadingDayCount
        let today = try day("2026-11-09")
        let tomorrow = try day("2026-11-10")
        let beforeStart = try #require(calendar.date(byAdding: .day, value: -lead, to: today))
        let afterStart = try #require(calendar.date(byAdding: .day, value: -lead, to: tomorrow))

        var disclosures = CalendarBoardDayDisclosures()
        let openedKey = DateFormatters.dateKey(from: CalendarBoardPlannerSupport.date(at: lead, bufferStart: beforeStart, calendar: calendar))
        #expect(openedKey == "2026-11-09", "non-vacuity: the slot is not today before the move")
        disclosures.setCompletedExpanded(true, for: openedKey)

        // After the jump the same slot is tomorrow, and today is one slot earlier.
        let slotKey = DateFormatters.dateKey(from: CalendarBoardPlannerSupport.date(at: lead, bufferStart: afterStart, calendar: calendar))
        let todaysNewKey = DateFormatters.dateKey(from: CalendarBoardPlannerSupport.date(at: lead - 1, bufferStart: afterStart, calendar: calendar))
        #expect(slotKey == "2026-11-10")
        #expect(todaysNewKey == "2026-11-09")
        #expect(!disclosures.isCompletedExpanded(slotKey), "the day that slid into the slot inherited the open fold")
        #expect(disclosures.isCompletedExpanded(todaysNewKey), "the day the fold was opened on lost it")

        disclosures.setCompletedExpanded(false, for: todaysNewKey)
        #expect(!disclosures.isCompletedExpanded(todaysNewKey))
        #expect(disclosures.expandedCompletedDateKeys.isEmpty)
    }

    /// The composer answers per day, independently of the fold, and closing one day's leaves
    /// another's open.
    @Test func aComposerIsOpenOnlyOnTheDayItWasOpenedOn() {
        var disclosures = CalendarBoardDayDisclosures()
        disclosures.setComposing(true, for: "2026-11-09")
        disclosures.setComposing(true, for: "2026-11-12")
        #expect(disclosures.isComposing("2026-11-09"))
        #expect(!disclosures.isComposing("2026-11-10"), "the composer opened on a day it was not opened on")
        #expect(!disclosures.isCompletedExpanded("2026-11-09"), "opening a composer opened the fold")

        disclosures.setComposing(false, for: "2026-11-09")
        #expect(!disclosures.isComposing("2026-11-09"))
        #expect(disclosures.isComposing("2026-11-12"), "closing one day's composer closed another's")
    }

    #if os(macOS)
    /// The Mac column holds neither as `@State`; the board hands each a binding keyed by the
    /// column's `dateKey`, never its `dayIndex`.
    @Test func theMacDayColumnHoldsNoSlotKeyedDisclosureState() throws {
        let column = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift")
        )
        let decl = try #require(CadenceSourceScan.declarationBody("struct CalendarBoardDayColumn: View", in: column))
        #expect(decl.contains("@Binding var isCompletedExpanded: Bool"))
        #expect(decl.contains("@Binding var isComposing: Bool"))
        #expect(CadenceSourceScan.matchCount(#"@State[^\n]*\b(isCompleted\w*|isComposing)\b"#, in: decl) == 0,
                "the Mac day column holds its fold or composer as slot-keyed @State again (T-14601)")

        let board = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageBoardSupportViews.swift")
        )
        #expect(board.contains("@State private var dayDisclosures = CalendarBoardDayDisclosures()"))
        for spelling in [
            "get: { dayDisclosures.isCompletedExpanded(dateKey) }",
            "set: { dayDisclosures.setCompletedExpanded($0, for: dateKey) }",
            "get: { dayDisclosures.isComposing(dateKey) }",
            "set: { dayDisclosures.setComposing($0, for: dateKey) }",
        ] {
            #expect(board.contains(spelling), "the board no longer keys a day column's disclosure by its date: \(spelling)")
        }
    }

    /// The iOS column is the same: its fold is a binding the board keys by `dateKey`, because
    /// `alignWindow(to:)` re-anchors the window on every jump and so lands each anchor on one slot.
    @Test func theIOSDayColumnHoldsNoSlotKeyedFold() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBoardView.swift")
        )
        let column = try #require(CadenceSourceScan.declarationBody("private struct iOSCalendarBoardDayColumn: View", in: source))
        #expect(column.contains("@Binding var isCompletedExpanded: Bool"))
        #expect(column.contains("isCompletedExpanded.toggle()"), "non-vacuity: the fold no longer toggles the binding")
        #expect(CadenceSourceScan.matchCount(#"@State[^\n]*\bisCompleted\w*\b"#, in: column) == 0,
                "the iOS day column holds its fold as slot-keyed @State again (T-14601)")

        #expect(source.contains("@State private var dayDisclosures = CalendarBoardDayDisclosures()"))
        #expect(source.contains("get: { dayDisclosures.isCompletedExpanded(dateKey) }"))
        #expect(source.contains("set: { dayDisclosures.setCompletedExpanded($0, for: dateKey) }"),
                "the iOS board no longer keys a day column's fold by its date")
    }
    #endif
}
