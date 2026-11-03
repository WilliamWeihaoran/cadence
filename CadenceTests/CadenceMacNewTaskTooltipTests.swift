import Foundation
import Testing
@testable import Cadence

/// **[[T-10230]]: the Mac New Task panel's glyph buttons, and the floating "+" that opens it, show
/// a tooltip.**
///
/// Every other icon-only Mac control names itself through `cadenceControlLabel(_:)`, which sets the
/// accessible name and the hover tooltip from one string (T-472) -- the inspector's ✕ ("Close"),
/// the Focus page's ✕ ("Close focus session"), the sidebar toggle. These five set the name with a
/// bare `.accessibilityLabel` and so drew nothing under the pointer: the panel's ✕ and → (the only
/// way to read what the arrow does without pressing it), its flag, its subtask ✕, and the page's
/// floating "+".
///
/// A source read, because the defect is which modifier a view body carries and no unit test can
/// hover a button. Comments are stripped, so a label written in prose cannot answer for one.
struct CadenceMacNewTaskTooltipTests {
    private static func body(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    @Test(arguments: [
        ("struct CreateTaskSheet: View", "Cadence/macOS/Sheets/CreateTaskSheet.swift", "Cancel"),
        ("struct CreateTaskSheet: View", "Cadence/macOS/Sheets/CreateTaskSheet.swift", "Create Task"),
        ("struct CreateTaskSheet: View", "Cadence/macOS/Sheets/CreateTaskSheet.swift", "Remove"),
        ("struct TaskPriorityPicker: View", "Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift", "Priority"),
        ("struct FloatingNewTaskButton: View", "Cadence/macOS/Views/macOSRootSupportViews.swift", "New Task"),
    ])
    func eachGlyphButtonNamesItselfWithItsTooltip(declaration: String, path: String, name: String) throws {
        let compact = try Self.body(declaration, in: path)
        let quoted = "\"\(name.filter { !$0.isWhitespace })\""
        #expect(
            compact.contains(".cadenceControlLabel(\(quoted))"),
            "\(name) must set its name and tooltip through cadenceControlLabel"
        )
        #expect(
            !compact.contains(".accessibilityLabel(\(quoted))"),
            "\(name) must not be named a second, tooltip-less way"
        )
    }

    /// The panel's Do Date and Due Date chips are bare glyphs until set, and carried no name at
    /// all. Each is named, with its tooltip, by the `label` its call site passes; the set date is
    /// the value. Not parameterised, so `mutate.sh` can baseline it (T-3212).
    @Test func theDateChipNamesItselfByWhatItSets() throws {
        let compact = try Self.body("struct TaskDateChip: View", in: "Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift")
        #expect(compact.contains(".cadenceControlLabel(label)"), "an unset date chip must name itself and show a tooltip")
        #expect(compact.contains(".accessibilityValue(isOn?displayLabel:\"\")"), "a set chip's date is its value")
        #expect(!compact.contains(".accessibilityLabel("), "the chip must not be named a second, tooltip-less way")
    }

    /// The parameterised test above cannot be baselined by `mutate.sh` (T-3212); this sibling reads
    /// the same three files, so a run that executed it reached them.
    @Test func theThreeFilesAreReadable() throws {
        #expect(try Self.body("struct CreateTaskSheet: View", in: "Cadence/macOS/Sheets/CreateTaskSheet.swift").contains("cadenceControlLabel"))
        #expect(try Self.body("struct TaskPriorityPicker: View", in: "Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift").contains("cadenceControlLabel"))
        #expect(try Self.body("struct FloatingNewTaskButton: View", in: "Cadence/macOS/Views/macOSRootSupportViews.swift").contains("cadenceControlLabel"))
    }
}
