import Foundation
import Testing
@testable import Cadence

/// **[[T-10004]]: Escape leaves the three Mac Settings sheets that ignored it.**
///
/// [[T-7266]] gave the list sheets Escape and Return, and [[T-7289]] the note AI review sheets,
/// but three sheets Settings presents carried no key at all, so the mouse was the only way out:
///
/// - `SidebarTabEditorSheet` (Settings > Sidebar, a tab's Edit): its lone Done now takes Escape.
///   The sheet's controls write through their bindings as they change, so closing it is "done".
/// - `SettingsDataResetConfirmationSheet` (Data Safety > Delete Account & Data): Cancel takes
///   Escape; Delete Everything takes no key -- destructive, and gated on the typed phrase.
/// - `SettingsArchiveImportPreviewSheet` (Data Safety > Import archive preview): Cancel takes
///   Escape; Import takes no Return, since its Overwrite mode replaces rows.
///
/// Source reads in `CadenceNoteActionSheetKeyboardTests`' style: no unit test can press a key in a
/// sheet. Read from the declaration's own body, so a shortcut elsewhere in the file cannot answer.
struct CadenceSettingsSheetKeyboardTests {
    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    /// Both spellings: a bare `.keyboardShortcut(` modifier, or `CadenceActionButton`'s
    /// `shortcut:` argument.
    private static func shortcutCount(_ compact: String) -> Int {
        (compact.components(separatedBy: ".keyboardShortcut(").count - 1)
            + (compact.components(separatedBy: "shortcut:.").count - 1)
    }

    @Test func sidebarTabEditorDoneTakesEscape() throws {
        let sheet = try Self.compactBody(
            "struct SidebarTabEditorSheet: View",
            in: "Cadence/macOS/Views/SettingsSupportViews.swift"
        )
        #expect(
            sheet.contains(#"CadenceActionButton(title:"Done",role:.primary,size:.compact,shortcut:.cancelAction){dismiss()}"#),
            "Escape must close the Mac sidebar tab editor through Done's own dismiss()"
        )
        #expect(Self.shortcutCount(sheet) == 1)
    }

    @Test func dataResetCancelTakesEscapeAndDeleteTakesNoKey() throws {
        let sheet = try Self.compactBody(
            "private struct SettingsDataResetConfirmationSheet: View",
            in: "Cadence/macOS/Views/SettingsDataSafetySection.swift"
        )
        #expect(
            sheet.contains(#"CadenceActionButton(title:"Cancel",role:.ghost,size:.compact,shortcut:.cancelAction){dismiss()}"#),
            "Escape must cancel the Mac Delete Account & Data sheet"
        )
        #expect(
            Self.shortcutCount(sheet) == 1,
            "Delete Everything is destructive and must take no key"
        )
    }

    @Test func archiveImportCancelTakesEscapeAndImportTakesNoKey() throws {
        let sheet = try Self.compactBody(
            "private struct SettingsArchiveImportPreviewSheet: View",
            in: "Cadence/macOS/Views/SettingsArchiveImportCard.swift"
        )
        #expect(
            sheet.contains("title:CadenceArchiveImportPresentation.cancelButtonTitle,role:.ghost,size:.compact,shortcut:.cancelAction,action:onCancel)"),
            "Escape must cancel the Mac archive import preview through the same onCancel"
        )
        #expect(
            Self.shortcutCount(sheet) == 1,
            "Import writes the store and must take no Return"
        )
    }

    /// **[[T-10005]].** The New Context sheet's name field said "e.g. Work, School, Personal" while
    /// its two siblings on the same `ListEditorSheetShell` say "Area name…" / "Project name…" and the
    /// iOS context editor says "Context name".
    @Test func newContextNameFieldNamesTheField() throws {
        let sheet = try Self.compactBody(
            "struct CreateContextSheet: View",
            in: "Cadence/macOS/Sheets/CreateContextSheet.swift"
        )
        #expect(sheet.contains(#"placeholder:"Contextname…""#))
        #expect(!sheet.contains("e.g."))
    }
}
