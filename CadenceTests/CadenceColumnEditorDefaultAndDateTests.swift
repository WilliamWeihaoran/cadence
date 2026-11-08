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

    /// **[[T-11222]] (c): the Mac popover offers no Color for Default.** Both boards draw Default
    /// neutral whatever hex it stores (`CadenceBoardColumnTint.base` answers `.neutral`, [[T-11221]]),
    /// so a swatch picked there changed nothing on screen. The heading and every swatch sit inside
    /// the one `!section.isDefault` gate, and a non-Default column still reaches them.
    @Test func macDefaultColumnPopoverOffersNoColor() throws {
        #if os(macOS)
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/KanbanColumnSupportViews.swift")
        let popover = try #require(CadenceSourceScan.declarationBody("struct KanbanSectionEditorPopover", in: source))
        #expect(CadenceSourceScan.matchCount("Text\\(\"Color\"\\)", in: popover) == 1)
        #expect(CadenceSourceScan.matchCount("ForEach\\(editorColorOptions", in: popover) == 1)
        let gate = try #require(popover.range(of: "if !section.isDefault {"))
        let heading = try #require(popover.range(of: "Text(\"Color\")"))
        let swatches = try #require(popover.range(of: "ForEach(editorColorOptions"))
        let dueDate = try #require(popover.range(of: "Text(CadenceListVocabularyCopy.dueDateFieldLabel)"))
        #expect(gate.upperBound <= heading.lowerBound, "the Color heading is drawn above its Default gate")
        #expect(heading.lowerBound < swatches.lowerBound)
        // The gate closes before Due Date, which Default keeps. Between the gate's `{` and the Due
        // Date heading the braces balance only if the gate's `}` is there to pay for the Due Date
        // block's own opening `{`.
        let between = String(popover[gate.upperBound..<dueDate.lowerBound])
        #expect(between.filter { $0 == "{" }.count == between.filter { $0 == "}" }.count,
                "the Default gate does not close between the swatches and Due Date")
        #expect(CadenceBoardColumnTint.base(for: TaskSectionConfig(name: TaskSectionDefaults.defaultName, colorHex: "#ff0000")) == .neutral)
        #endif
    }

    /// **[[T-12070]]: the iOS column editor offers no Color for Default either**, the iOS twin of
    /// `macDefaultColumnPopoverOffersNoColor`. The picker is drawn once, inside the one
    /// `!draft.isDefaultColumn` gate, and that gate closes before the Due date row Default keeps.
    @Test func iOSDefaultColumnRowOffersNoColor() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSListEditorViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("private struct iOSSectionDraftRow", in: source))
        #expect(CadenceSourceScan.matchCount("iOSSectionColorPicker\\(", in: row) == 1)
        let gate = try #require(row.range(of: "if !draft.isDefaultColumn {"))
        let picker = try #require(row.range(of: "iOSSectionColorPicker(selectedHex: $draft.colorHex)"))
        let dueDate = try #require(row.range(of: "Text(CadenceListVocabularyCopy.dueDateFieldLabel)"))
        #expect(gate.upperBound <= picker.lowerBound, "the Color picker is drawn above its Default gate")
        #expect(picker.lowerBound < dueDate.lowerBound)
        let between = String(row[gate.upperBound..<dueDate.lowerBound])
        #expect(between.filter { $0 == "{" }.count == between.filter { $0 == "}" }.count,
                "the Default gate does not close between the picker and Due date")
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

    /// **[[T-9804]], step two: the iOS project due date is the column row's placeholder picker.**
    /// `iOSListEditorSheet` drew `Toggle("Due date")` and, only when on, a picker with no
    /// placeholder or clear. It now holds the stored key itself (`projectDueDateKey`, "" for none),
    /// so "is the project dated" is that value alone, and both save branches -- creating a project
    /// and editing one -- write it as it stands: "" once cleared, the picked day once set.
    @Test func iOSProjectDueDateIsOnePlaceholderPicker() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let source = try read("Cadence/iOS/iOSListEditorViews.swift")
        let sheet = try #require(CadenceSourceScan.declarationBody("struct iOSListEditorSheet: View", in: source))

        #expect(!sheet.contains("Toggle(\"Due date\""), "the separate switch is back")
        #expect(!sheet.contains("hasProjectDueDate"), "a second flag can disagree with the stored key")
        #expect(!sheet.contains("CadenceDatePicker(selection: $projectDueDate)"))
        #expect(sheet.contains("placeholder: projectDueDateKey.isEmpty ? CadenceBoardColumnDueDatePlan.emptyLabel : nil"))
        #expect(sheet.contains("showsClear: !projectDueDateKey.isEmpty"))
        #expect(sheet.contains("onClear: { projectDueDateKey = \"\" }"))
        #expect(sheet.contains("projectDueDateKey = DateFormatters.dateKey(from: newValue)"), "a pick commits through the setter")

        // Both save branches (new project, edited project) write the key as it stands.
        #expect(CadenceSourceScan.matchCount("project\\.dueDate = projectDueDateKey", in: sheet) == 2)
        #expect(sheet.contains("dueDateKey: projectDueDateKey,"), "the dismiss guard's snapshot reads the same key")
        // An existing dated project opens dated; an undated or unreadable one opens empty.
        let load = try #require(CadenceSourceScan.declarationBody("private func load()", in: source))
        #expect(load.contains("projectDueDateKey = DateFormatters.dateKey(from: date)"))
        #expect(CadenceSourceScan.matchCount("projectDueDateKey = \"\"", in: load) == 3)
    }

    /// **[[T-9804]], step two on the Mac.** Both list sheets drew the due date through
    /// `TaskInspectorDateControl` -- already one trigger, no switch -- but held a separate
    /// `hasDueDate` flag beside the date. They now hold the stored key and go through
    /// `ListEditorDueDateRow`, which derives the control's `isOn:` from that key, so the save writes
    /// the key as it stands. The control itself, shared with no other caller shape, is unchanged.
    @Test func macProjectDueDateIsDerivedFromTheStoredKey() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let support = try read("Cadence/macOS/Sheets/ListEditorSupportViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("struct ListEditorDueDateRow: View", in: support))
        #expect(row.contains("get: { !dueDateKey.isEmpty }"), "dated is the stored key alone")
        #expect(row.contains("dueDateKey = dated ? DateFormatters.dateKey(from: seed) : \"\""), "Clear empties the key")
        #expect(row.contains("dueDateKey = DateFormatters.dateKey(from: newValue)"), "a pick writes the key")

        for path in ["Cadence/macOS/Sheets/EditListSheet.swift", "Cadence/macOS/Sheets/CreateListSheet.swift"] {
            let sheet = try read(path)
            #expect(sheet.contains("ListEditorDueDateRow(dueDateKey: $dueDateKey, seed: $dueDate)"), "\(path)")
            #expect(sheet.contains("project.dueDate = dueDateKey"), "\(path) saves the key as it stands")
            #expect(!sheet.contains("hasDueDate"), "\(path) holds a second flag again")
            #expect(!sheet.contains("TaskInspectorDateControl("), "\(path) bypasses the derived row")
        }
    }

    /// **[[T-10982]]: an undated project reads "No due date" on the Mac too.** The control read
    /// "Set" while empty -- the task inspector's idiom -- where iOS and both platforms' column rows
    /// read `CadenceBoardColumnDueDatePlan.emptyLabel`. The control now takes an empty label whose
    /// default stays "Set", and the project row passes the shared one.
    @Test func macProjectDueRowReadsTheSharedEmptyLabel() throws {
        let support = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Sheets/ListEditorSupportViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("struct ListEditorDueDateRow: View", in: support))
        #expect(
            CadenceSourceScan.matchCount("emptyLabel: CadenceBoardColumnDueDatePlan\\.emptyLabel,", in: row) == 1,
            "the project Due row passes the shared empty label"
        )
        #expect(CadenceBoardColumnDueDatePlan.emptyLabel == "No due date")
        #if os(macOS)
        #expect(TaskInspectorDateControl.defaultEmptyLabel == "Set", "the task inspector keeps its own word")
        let empty = TaskInspectorDateControl.displayValue(
            isOn: false, date: Date(), emptyLabel: CadenceBoardColumnDueDatePlan.emptyLabel
        )
        #expect(empty == CadenceBoardColumnDueDatePlan.emptyLabel)
        let dated = TaskInspectorDateControl.displayValue(
            isOn: true, date: Date(), emptyLabel: CadenceBoardColumnDueDatePlan.emptyLabel
        )
        #expect(dated != CadenceBoardColumnDueDatePlan.emptyLabel, "a dated row shows its date")
        #endif
    }

    /// **[[T-13221]]: one name for the list editors' due-date field, on both platforms.** A project's
    /// due date read "Due" in the Mac's list sheets and "Due date" in the iOS editor; a column's
    /// read "Due Date" in the Mac popover and "Due date" in the iOS editor row. No hardware or input
    /// makes a field label differ ([[T-8201]]), so all four read `dueDateFieldLabel`, and none of
    /// the four declarations types a spelling of its own.
    @Test func everyListEditorDueDateRowReadsTheOneSharedLabel() throws {
        #expect(CadenceListVocabularyCopy.dueDateFieldLabel == "Due date")
        #expect(CadenceListVocabularyCopy.dueDateFieldLabel == CadenceTaskControlAccessibility.dueDate,
                "the visible name and the accessibility name of the field are one word")

        let read = CadenceSourceScan.strippedSourceReader()
        let constant = "CadenceListVocabularyCopy\\.dueDateFieldLabel"
        let typed = #"(Text|label:)\s*\(?\s*"Due( [Dd]ate)?""#

        let support = try read("Cadence/macOS/Sheets/ListEditorSupportViews.swift")
        let macProjectRow = try #require(CadenceSourceScan.declarationBody("struct ListEditorDueDateRow: View", in: support))
        let columns = try read("Cadence/macOS/Views/KanbanColumnSupportViews.swift")
        let macColumnPopover = try #require(CadenceSourceScan.declarationBody("struct KanbanSectionEditorPopover", in: columns))
        let editor = try read("Cadence/iOS/iOSListEditorViews.swift")
        let iOSSheet = try #require(CadenceSourceScan.declarationBody("struct iOSListEditorSheet: View", in: editor))
        let iOSColumnRow = try #require(CadenceSourceScan.declarationBody("private struct iOSSectionDraftRow", in: editor))

        let sites: [(String, String)] = [
            ("Mac project Due row", macProjectRow),
            ("Mac column popover", macColumnPopover),
            ("iOS project Due row", iOSSheet),
            ("iOS column row", iOSColumnRow),
        ]
        for (name, body) in sites {
            #expect(CadenceSourceScan.matchCount(constant, in: body) == 1, "\(name) reads the shared label once")
            #expect(CadenceSourceScan.matchCount(typed, in: body) == 0, "\(name) types its own spelling of the field")
        }
    }
}
