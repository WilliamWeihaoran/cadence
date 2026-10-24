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

    // MARK: - T-5835, the rule as a value

    /// The draft of the existing Default column is Default whatever its field now holds; a column
    /// added during the edit is never Default, even one typed as "Default"; other columns are not.
    @Test func onlyTheExistingDefaultDraftIsTheDefaultColumn() {
        #expect(CadenceSectionDraft(config: TaskSectionConfig(name: TaskSectionDefaults.defaultName)).isDefaultColumn)
        #expect(CadenceSectionDraft(config: TaskSectionConfig(name: "default")).isDefaultColumn)

        var renamed = CadenceSectionDraft(config: TaskSectionConfig(name: TaskSectionDefaults.defaultName))
        renamed.name = "Backlog"
        #expect(renamed.isDefaultColumn, "keyed on the name the editor opened with, not the field")

        #expect(!CadenceSectionDraft(config: TaskSectionConfig(name: "Doing")).isDefaultColumn)
        #expect(!CadenceSectionDraft(config: TaskSectionConfig(name: "Defaults")).isDefaultColumn)
        #expect(!CadenceSectionDraft(name: TaskSectionDefaults.defaultName).isDefaultColumn)
    }

    // MARK: - T-5835, the iOS row

    @Test func iOSDefaultRowHasNoNameFieldAndCannotBeDeleted() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListEditorViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("private struct iOSSectionDraftRow", in: source))

        // The name field is drawn only on the non-Default branch.
        let gate = try #require(row.range(of: "if draft.isDefaultColumn {"))
        let field = try #require(row.range(of: "TextField(\"Column name\", text: $draft.name)"))
        let elseBranch = try #require(row.range(of: "} else {", range: gate.upperBound..<row.endIndex))
        #expect(elseBranch.upperBound <= field.lowerBound, "the name field must sit in the else branch")
        #expect(CadenceSourceScan.matchCount("TextField\\(\"Column name\"", in: row) == 1)
        #expect(row.contains("cannot be renamed, completed, archived, or deleted."))

        // The row in the editor's ForEach refuses the swipe-delete for Default.
        let code = CadenceSourceScan.strippingComments(source)
        #expect(CadenceSourceScan.matchCount(
            "iOSSectionDraftRow\\(draft: \\$draft, lifecycle: lifecycle\\(for: draft\\)\\)\\s*\\.deleteDisabled\\(draft\\.isDefaultColumn\\)",
            in: code
        ) == 1)
    }

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
