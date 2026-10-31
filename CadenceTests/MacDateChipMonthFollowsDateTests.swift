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

    /// **T-9212.** Both controls carried a private copy of the quick-date popover — pills,
    /// grid, Clear — that drifted from the shared one (Clear as a glyph row in one, unpadded text
    /// in the other; 5pt pills; "This Weekend" derived twice). Each now hosts
    /// `CadenceQuickDatePopover`, keeps its own semantics through the arguments (picking turns
    /// the field on, Clear turns it off, an unset field shows no pick and no Clear), and tints the
    /// picked pill with its own accent, which the shared pill now reads instead of a literal blue.
    /// Not parameterised, so `mutate.sh` can baseline it (T-3212).
    @Test func bothDateControlsHostTheSharedQuickDatePopoverRatherThanACopy() throws {
        let sites = [
            ("Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift", "struct TaskDateChip: View"),
            ("Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift", "struct TaskInspectorDateControl: View"),
        ]
        var checked = 0
        for (path, declaration) in sites {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
            let popover = try #require(body.range(of: "CadenceQuickDatePopover("), "\(declaration) no longer hosts the shared popover")
            let call = String(body[popover.lowerBound...].prefix(700))
            #expect(body.components(separatedBy: "CadenceQuickDatePopover(").count - 1 == 1, "\(declaration)")
            #expect(call.contains("isOn = true"), "\(declaration): picking no longer turns the field on")
            #expect(call.contains("showsClear: isOn"), "\(declaration)")
            #expect(call.contains("onClear: { isOn = false }"), "\(declaration)")
            #expect(call.contains("hasSelection: isOn"), "\(declaration)")
            #expect(call.contains("tint: activeColor"), "\(declaration): the picked pill lost the field's accent")
            for copy in ["MonthCalendarPanel(", "quickPill", "Clear date", "daysUntilSaturday"] {
                #expect(!body.contains(copy), "\(declaration) still draws its own `\(copy)`")
            }
            checked += 1
        }
        #expect(checked == 2)

        let picker = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceDatePicker.swift")
        )
        let shared = try #require(CadenceSourceScan.declarationBody("struct CadenceQuickDatePopover: View", in: picker))
        #expect(shared.contains("var tint: Color = Theme.blue"))
        let pill = try #require(CadenceSourceScan.functionBody(named: "quickPill", in: shared))
        #expect(pill.contains(".background(isSelected ? tint : Theme.surface)"))
        #expect(pill.contains("Theme.onColor(for: tint)"))
        #expect(!pill.contains("Theme.blue"), "the shared pill ignores its tint")
    }
}
#endif
