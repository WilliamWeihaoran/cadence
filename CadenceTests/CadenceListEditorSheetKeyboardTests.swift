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

    @Test func iconStripCellCarriesTheSelectedTrait() throws {
        let cell = try Self.body("private struct ListEditorIconCell: View", in: Self.supportPath)
        #expect(cell.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
    }

    @Test func newListTypeButtonCarriesTheSelectedTrait() throws {
        let button = try Self.body("private struct TypeButton: View", in: Self.createListPath)
        #expect(button.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
    }
}
