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
        // The picker call, through the clear handler that ends its argument list.
        let call = try #require(popover.range(of: "CadenceDatePicker("))
        let clearHandler = try #require(popover.range(of: "onClear: onClearDate", range: call.upperBound..<popover.endIndex))
        let tail = String(popover[call.lowerBound..<clearHandler.upperBound])

        // The shared label, not a re-spelling: `CadenceSharedBoardChromeTests` forbids the literal here.
        #expect(tail.contains("placeholder: editorHasDueDate ? nil : CadenceBoardColumnDueDatePlan.emptyLabel"))
        // Every pick commits through the setter; `.onChange` would miss a re-pick of the cleared day.
        #expect(tail.contains("editorHasDueDate = true"))
        #expect(tail.contains("onDueDateChanged()"))
        #expect(!popover.contains(".onChange(of: editorDueDate)"))
        #expect(!tail.contains("selection: $editorDueDate"))
        #endif
    }

    /// **[[T-9803]]: a dated column is cleared in one place, the picker's own panel.** The popover
    /// drew a second red "Clear date" under the picker's trigger, beside the one the picker's panel
    /// draws under its grid (`CadenceQuickDatePopover`, gated by `CadenceDateSelectionState.drawsClear`),
    /// so with the panel open the popover carried two. Every other Mac date field clears from the
    /// panel alone. The picker still gets the clear handler, so the column can still be undated.
    @Test func macColumnDueDateClearsOnlyFromThePickerPanel() throws {
        #if os(macOS)
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift")
        let popover = try #require(CadenceSourceScan.declarationBody("struct KanbanSectionEditorPopover", in: source))
        #expect(CadenceSourceScan.matchCount("onClearDate", in: popover) == 2, "the stored handler and the picker's onClear")
        #expect(CadenceSourceScan.matchCount("showsClear: editorHasDueDate,\\s*onClear: onClearDate\\s*\\)", in: popover) == 1)
        #expect(!popover.contains("Clear date"), "no second Clear control beside the picker's own")
        #expect(!popover.contains("Button(\"Clear"))

        // The panel's Clear is the one the user reaches: drawn over a date, never over none.
        #expect(CadenceDateSelectionState.drawsClear(showsClear: true, hasSelection: true))
        #expect(!CadenceDateSelectionState.drawsClear(showsClear: true, hasSelection: false))
        #endif
    }

    /// **[[T-9804]]: the iOS column row edits its due date the Mac popover's way.** It drew a "Due
    /// date" switch and, only when on, a picker with no placeholder and no clear -- two controls
    /// that could disagree about whether the column is dated. It now draws one `CadenceDatePicker`
    /// that reads the shared "No due date" while `draft.dueDate` is empty, commits every pick through
    /// the binding's setter, and clears through the picker's own `onClear`.
    @Test func iOSColumnDueDateIsOnePlaceholderPicker() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListEditorViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("private struct iOSSectionDraftRow", in: source))
        let call = try #require(row.range(of: "CadenceDatePicker("))
        let clear = try #require(row.range(of: "onClear: { draft.dueDate = \"\" }", range: call.upperBound..<row.endIndex))
        let tail = String(row[call.lowerBound..<clear.upperBound])

        #expect(tail.contains("placeholder: draft.dueDate.isEmpty ? CadenceBoardColumnDueDatePlan.emptyLabel : nil"))
        #expect(tail.contains("showsClear: !draft.dueDate.isEmpty"))
        #expect(tail.contains("draft.dueDate = DateFormatters.dateKey(from: newValue)"), "a pick commits through the setter")
        #expect(!tail.contains("selection: $dueDate"))
        #expect(CadenceSourceScan.matchCount("CadenceDatePicker\\(", in: row) == 1)
        #expect(!row.contains("Toggle(\"Due date\""), "the separate switch is back")
        #expect(!row.contains("hasDueDate"))
        #expect(!row.contains(".onChange(of: dueDate)"))
    }
}
