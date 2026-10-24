import Foundation
import Testing
@testable import Cadence

/// **T-5834 and T-5835: two column-editor defects, one per platform.**
///
/// - T-5834 (macOS): the Kanban column popover's Due Date field showed today's date for a column
///   with no due date — `openSectionEditor()` seeds `editorDueDate` with `?? Date()` — and after
///   "Clear date" it kept showing the date just cleared. The fix passes `CadenceDatePicker` its
///   `placeholder:` while there is no date, and commits every pick through the binding's setter, so
///   re-picking the cleared day (an unchanged value, which `.onChange` never saw) sets it again.
/// - T-5835 (iOS): the list editor drew Default's name as an editable field and let Default be
///   swiped away, which the Mac forbids. A rename moved Default's cards to the new name beside a
///   freshly synthesised empty "Default"; a delete came back on Save with its colour and due date
///   erased. Default's row now draws its name read-only, with the Mac's sentence, and refuses delete.
///
/// The rule is a value (`CadenceSectionDraft.isDefaultColumn`); the two views are private SwiftUI
/// bodies and are pinned as comment-stripped source text.
@MainActor
struct CadenceColumnEditorDefaultAndDateTests {

    // MARK: - T-5834, the macOS popover

    @Test func macColumnDueDateShowsAPlaceholderWithoutADate() throws {
        #if os(macOS)
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift")
        let popover = try #require(CadenceSourceScan.declarationBody("struct KanbanSectionEditorPopover", in: source))
        // The picker call, up to the "Clear date" button that follows it.
        let call = try #require(popover.range(of: "CadenceDatePicker("))
        let clearButton = try #require(popover.range(of: "if editorHasDueDate {", range: call.upperBound..<popover.endIndex))
        let tail = String(popover[call.lowerBound..<clearButton.lowerBound])

        #expect(tail.contains("placeholder: editorHasDueDate ? nil : \"No due date\""))
        // Every pick commits through the setter; `.onChange` would miss a re-pick of the cleared day.
        #expect(tail.contains("editorHasDueDate = true"))
        #expect(tail.contains("onDueDateChanged()"))
        #expect(!popover.contains(".onChange(of: editorDueDate)"))
        #expect(!tail.contains("selection: $editorDueDate"))
        #endif
    }
}
