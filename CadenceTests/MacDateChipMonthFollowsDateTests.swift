#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-8105.** The New Task sheet's date chip and the inspector's date field anchored their month
/// grid in `onAppear` only, so after a pill, Cmd+T / Cmd+D or a nudge moved the date into another
/// month the grid reopened on the old month with no day highlighted.
struct MacDateChipMonthFollowsDateTests {

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func theGridOpensOnTheMonthOfTheChipsDate() {
        let month = TaskDateChipMonthSupport.viewMonth(
            isOn: true, date: Self.day(2026, 11, 1), now: Self.day(2026, 10, 31), calendar: Self.calendar
        )
        #expect(month == Self.day(2026, 11, 1))
    }

    @Test func anUnsetChipOpensOnTodaysMonth() {
        let month = TaskDateChipMonthSupport.viewMonth(
            isOn: false, date: Self.day(2027, 3, 14), now: Self.day(2026, 10, 31), calendar: Self.calendar
        )
        #expect(month == Self.day(2026, 10, 1))
    }

    /// The pure answer is only half the fix: both views must ask it again when the panel opens,
    /// not just when they appeared.
    @Test(arguments: [
        ("Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift", "struct TaskDateChip: View"),
        ("Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift", "struct TaskInspectorDateControl: View"),
    ])
    func bothDateControlsReanchorTheGridEveryTimeThePanelOpens(path: String, declaration: String) throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        let onOpen = try #require(body.range(of: ".onChange(of: showPicker)"))
        let after = body[onOpen.upperBound...].prefix(200)
        #expect(after.contains("if showPicker { viewMonth = TaskDateChipMonthSupport.viewMonth(isOn: isOn, date: date) }"))
    }
}
#endif
