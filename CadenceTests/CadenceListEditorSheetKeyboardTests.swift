import Foundation
import Testing
@testable import Cadence

/// **T-7266 and T-7267: the Mac list sheets answer the keyboard and say what is chosen.**
///
/// `ListEditorSheetShell` is the footer of all three Mac list sheets — New List, Edit Area / Edit
/// Project, New Context. Its Cancel and Create/Save buttons carried no keyboard shortcut and the
/// name field has no submit handler, so Return and Escape did nothing in any of them (T-7266).
///
/// The icon strip's cells and New List's Area/Project buttons draw which one is chosen and never
/// told VoiceOver; the colour strip beside them and the full `IconGrid` already did (T-7267).
///
/// A source read, because the defect is a modifier missing from a view body and no unit test can
/// press a key in a sheet. Read from the declaration bodies, not the whole file, so a shortcut on
/// some other button in the file cannot answer for these.
struct CadenceListEditorSheetKeyboardTests {
    private static let supportPath = "Cadence/macOS/Sheets/ListEditorSupportViews.swift"
    private static let createListPath = "Cadence/macOS/Sheets/CreateListSheet.swift"

    private static func body(_ declaration: String, in path: String) throws -> String {
        let source = try CadenceSourceScan.sourceFile(path)
        return try #require(CadenceSourceScan.declarationBody(declaration, in: source))
    }

    @Test func shellCancelTakesEscapeAndConfirmTakesReturn() throws {
        let shell = try Self.body("struct ListEditorSheetShell<", in: Self.supportPath)
        let compact = shell.filter { !$0.isWhitespace }

        #expect(
            compact.contains(#"CadenceActionButton(title:"Cancel",role:.ghost,size:.compact,shortcut:.cancelAction)"#),
            "Escape must close every Mac list sheet"
        )
        #expect(
            compact.contains("isDisabled:isConfirmDisabled,shortcut:.defaultAction)"),
            "Return must confirm every Mac list sheet, gated by the same isDisabled as the click"
        )
    }

    /// T-7268: the Notes folder sheet and the tag picker's edit sheet had the same gap.
    @Test func noteFolderSheetCancelTakesEscapeAndConfirmTakesReturn() throws {
        let sheet = try Self.body(
            "struct NoteFolderSheet: View",
            in: "Cadence/macOS/Views/ListNotesListSupportViews.swift"
        )
        let compact = sheet.filter { !$0.isWhitespace }

        // [[T-9532]]: both footer buttons are the shared `CadenceActionButton`, so the keys
        // ride on its `shortcut:` argument rather than a bare `.keyboardShortcut(` modifier.
        #expect(
            compact.contains(#"CadenceActionButton(title:"Cancel",role:.ghost,size:.compact,shortcut:.cancelAction){dismiss()}"#),
            "Escape must close the Mac note folder sheet, from its Cancel button"
        )
        #expect(
            compact.contains("isDisabled:normalizedFolderPath.isEmpty,shortcut:.defaultAction)"),
            "Return must confirm the Mac note folder sheet, gated by the same isDisabled as the click"
        )
        #expect(
            (compact.components(separatedBy: ".keyboardShortcut(").count - 1)
                + (compact.components(separatedBy: "shortcut:.").count - 1) == 2
        )
    }

    @Test func tagEditSheetCancelTakesEscapeSaveTakesReturnArchiveTakesNeither() throws {
        let sheet = try Self.body(
            "private struct TagEditSheet: View",
            in: "Cadence/macOS/Views/TagPickerPopoverViews.swift"
        )
        let compact = sheet.filter { !$0.isWhitespace }

        // [[T-9801]]: the footer is the shared `CadenceActionButton`, as `NoteFolderSheet`'s is, so
        // the keys ride on its `shortcut:` argument.
        #expect(
            compact.contains(#"CadenceActionButton(title:"Cancel",role:.ghost,size:.compact,shortcut:.cancelAction,action:onCancel)"#),
            "Escape must close the Mac tag edit sheet"
        )
        #expect(
            compact.contains("isDisabled:!canSave,shortcut:.defaultAction,action:onSave)"),
            "Return must save the Mac tag edit sheet, gated by the same isDisabled as the click"
        )
        #expect(
            compact.contains(#"CadenceActionButton(title:"Archive",role:.destructive,size:.compact,action:onArchive)Spacer()"#),
            "Archive is destructive and must take neither Return nor Escape"
        )
        #expect(
            (compact.components(separatedBy: ".keyboardShortcut(").count - 1)
                + (compact.components(separatedBy: "shortcut:.").count - 1) == 2
        )
    }

    /// **[[T-9801]]: the tag picker's Edit Tag sheet wears the Mac's own sheet chrome.** It was the
    /// one surface in the app on AppKit's stock bezel fields and push buttons, on the elevated
    /// surface no other Mac sheet uses, with the colour as a third full-width text field. Its fields
    /// are now the Settings tag editor's (`SettingsTagRow.editField`), so the same tag edits in the
    /// same wells from either place, and the footer is `NoteFolderSheet`'s.
    @Test func tagEditSheetWearsTheMacSheetChrome() throws {
        let path = "Cadence/macOS/Views/TagPickerPopoverViews.swift"
        let sheet = try Self.body("private struct TagEditSheet: View", in: path)
        let compact = sheet.filter { !$0.isWhitespace }

        #expect(!compact.contains(".roundedBorder"), "No stock AppKit bezel field in a Cadence sheet")
        #expect(!compact.contains("Button(\""), "No stock push button: the footer is CadenceActionButton")
        #expect(compact.contains(#"Text("EditTag")"#), "Title Case, as every other Mac sheet title")
        #expect(compact.components(separatedBy: "editField(").count - 1 == 4, "three calls and the helper")
        #expect(compact.contains(##"TagColorSwatches(selectedHex:$colorHex)editField("#hex",text:$colorHex).frame(width:96)"##))
        #expect(compact.contains(".padding(18).frame(width:320).background(Theme.surface)"))

        // The well is the Settings tag editor's, not a third spelling of it.
        let field = try #require(CadenceSourceScan.declarationBody(
            "private func editField(_ placeholder: String, text: Binding<String>) -> some View",
            in: sheet
        )).filter { !$0.isWhitespace }
        #expect(field.contains(".textFieldStyle(.plain).font(.system(size:13)).foregroundStyle(Theme.text).cadenceSettingsWell()"))
    }

    @Test func iconStripCellCarriesTheSelectedTrait() throws {
        let cell = try Self.body("private struct ListEditorIconCell: View", in: Self.supportPath)
        #expect(cell.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
    }

    @Test func newListTypeButtonCarriesTheSelectedTrait() throws {
        let button = try Self.body("private struct TypeButton: View", in: Self.createListPath)
        #expect(button.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
    }
}
