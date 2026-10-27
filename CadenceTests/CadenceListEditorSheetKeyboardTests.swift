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

        #expect(
            compact.contains(".buttonStyle(.cadencePlain).keyboardShortcut(.cancelAction)Button(request.actionTitle){"),
            "Escape must close the Mac note folder sheet, from its Cancel button"
        )
        #expect(
            compact.contains(".keyboardShortcut(.defaultAction).disabled(normalizedFolderPath.isEmpty)"),
            "Return must confirm the Mac note folder sheet, gated by the same disabled as the click"
        )
        #expect(compact.components(separatedBy: ".keyboardShortcut(").count - 1 == 2)
    }

    @Test func tagEditSheetCancelTakesEscapeSaveTakesReturnArchiveTakesNeither() throws {
        let sheet = try Self.body(
            "private struct TagEditSheet: View",
            in: "Cadence/macOS/Views/TagPickerPopoverViews.swift"
        )
        let compact = sheet.filter { !$0.isWhitespace }

        #expect(
            compact.contains(#"Button("Cancel",action:onCancel).keyboardShortcut(.cancelAction)"#),
            "Escape must close the Mac tag edit sheet"
        )
        #expect(
            compact.contains(#"Button("Save",action:onSave).keyboardShortcut(.defaultAction).disabled(!canSave)"#),
            "Return must save the Mac tag edit sheet, gated by the same disabled as the click"
        )
        #expect(
            compact.contains(#"Button("Archive",role:.destructive,action:onArchive)Spacer()"#),
            "Archive is destructive and must take neither Return nor Escape"
        )
        #expect(compact.components(separatedBy: ".keyboardShortcut(").count - 1 == 2)
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
