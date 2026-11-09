#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-14192 — the Mac sidebar list row's due-date popover opens on the list's due date.**
///
/// Seen on screen: Beta Project due Tomorrow (Nov 9) opened its flag popover with Today lit and the
/// 8 filled, Tomorrow unlit. The popover read a `@State` copy that defaulted to `Date()` and was
/// seeded by the badge button's action; the popover was presented on the default. The row now
/// hands the popover its selection from the stored key itself, so there is no seed to miss.
@MainActor
struct CadenceSidebarDueDatePopoverSeedTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    private static let calendar = Calendar.current

    /// Sunday 2026-11-08, mid-afternoon -- the day of the sighting.
    private static var sightingToday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 15))!
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func aListDueTomorrowOpensOnTomorrowNotToday() {
        let selection = SidebarListRow.dueDatePickerSelection(forKey: "2026-11-09", today: Self.sightingToday)
        #expect(Self.calendar.isDate(selection, inSameDayAs: Self.day(2026, 11, 9)))
        // The pills the popover lights: Tomorrow, and not Today.
        #expect(CadenceDateSelectionState.isSelected(Self.day(2026, 11, 9), selection: selection, hasSelection: true))
        #expect(!CadenceDateSelectionState.isSelected(Self.day(2026, 11, 8), selection: selection, hasSelection: true))
    }

    @Test func aKeyThatDoesNotParseFallsBackToToday() {
        let selection = SidebarListRow.dueDatePickerSelection(forKey: "not a date", today: Self.sightingToday)
        #expect(selection == Self.sightingToday)
    }

    @Test func theGridOpensOnTheDueDatesMonth() {
        let month = SidebarListRow.dueDatePickerViewMonth(
            forKey: "2027-03-15",
            today: Self.sightingToday,
            calendar: Self.calendar
        )
        #expect(month == Self.day(2027, 3, 1))
    }

    @Test func thePopoverReadsTheStoredKeyNotASeededCopy() throws {
        let source = try Self.code("Cadence/macOS/Views/SidebarSupportViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("struct SidebarListRow: View", in: source))
        #expect(row.contains("get: { Self.dueDatePickerSelection(forKey: key) }"))
        #expect(!row.contains("dueDatePickerDate"))
    }
}
#endif
