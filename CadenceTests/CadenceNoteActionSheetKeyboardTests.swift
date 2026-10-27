import Foundation
import Testing
@testable import Cadence

/// **T-7288 and T-7289: the Mac note Actions popover's Move page names blank lists, and its two AI
/// review sheets answer the keyboard.**
///
/// T-7288: the Move Note page printed `area.name` / `project.name` raw, so a blank-named list was a
/// row with nothing but its "Area" / "Project" subtitle. The sidebar and Cmd+K read such a list as
/// "Untitled Area" / "Untitled Project" since T-7202; this page now reads it the same way.
///
/// T-7289: `AISummaryReviewSheet` and `AITaskDraftReviewSheet` carried no keyboard shortcut, so
/// Escape closed neither sheet and Return did nothing — the same gap T-7266 closed in the list
/// sheets. Summary: Escape closes, Return appends. Drafts: Escape cancels, and Return is left off
/// Create Selected on purpose (T-7290 is the owner call).
///
/// Source reads in `CadenceListEditorSheetKeyboardTests`' style: no unit test can press a key in a
/// sheet, and the move rows are private views inside a popover. Read from declaration bodies so a
/// modifier elsewhere in the file cannot answer for these.
struct CadenceNoteActionSheetKeyboardTests {
    private static let sheetsPath = "Cadence/macOS/Views/NoteActionReviewSheets.swift"
    private static let menuPath = "Cadence/macOS/Views/AIActionsSupportViews.swift"

    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = try CadenceSourceScan.sourceFile(path)
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    private static func shortcutCount(_ compact: String) -> Int {
        compact.components(separatedBy: ".keyboardShortcut(").count - 1
    }

    @Test func summarySheetCloseTakesEscapeAndAppendTakesReturn() throws {
        let sheet = try Self.compactBody("struct AISummaryReviewSheet: View", in: Self.sheetsPath)

        #expect(
            sheet.contains(#"Button("Close"){dismiss()}.buttonStyle(.cadencePlain).keyboardShortcut(.cancelAction)"#),
            "Escape must close the Mac AI summary sheet"
        )
        #expect(
            sheet.contains(#"Button("AppendtoNote"){append()}.buttonStyle(.cadencePlain).keyboardShortcut(.defaultAction)"#),
            "Return must append the summary, through the same append() as the click"
        )
        #expect(Self.shortcutCount(sheet) == 2)
    }

    @Test func draftSheetCancelTakesEscapeAndCreateTakesNoKey() throws {
        let sheet = try Self.compactBody("struct AITaskDraftReviewSheet: View", in: Self.sheetsPath)

        #expect(
            sheet.contains(#"Button("Cancel"){dismiss()}.buttonStyle(.cadencePlain).keyboardShortcut(.cancelAction)"#),
            "Escape must cancel the Mac AI task draft sheet"
        )
        #expect(
            Self.shortcutCount(sheet) == 1,
            "Create Selected takes no key until the owner answers T-7290"
        )
    }

    @Test func moveDestinationRowsNameBlankListsUntitled() throws {
        let areas = try Self.compactBody("private var areaDestinations: some View", in: Self.menuPath)
        let projects = try Self.compactBody("private var projectDestinations: some View", in: Self.menuPath)

        #expect(areas.contains(
            "title:CadenceTitleNormalization.display(area.name,fallback:CadenceTitleNormalization.defaultAreaName)"
        ))
        #expect(projects.contains(
            "title:CadenceTitleNormalization.display(project.name,fallback:CadenceTitleNormalization.defaultProjectName)"
        ))
        #expect(!areas.contains("title:area.name,"))
        #expect(!projects.contains("title:project.name,"))
    }

    /// The fallback the rows now call is the one that turns a blank name into the Untitled noun —
    /// pinned on behaviour, so the source pin above cannot be satisfied by a helper that returns
    /// the raw string.
    @Test func theFallbackTheRowsUseReadsUntitled() {
        #expect(CadenceTitleNormalization.display("", fallback: CadenceTitleNormalization.defaultAreaName) == "Untitled Area")
        #expect(CadenceTitleNormalization.display("   ", fallback: CadenceTitleNormalization.defaultProjectName) == "Untitled Project")
        #expect(CadenceTitleNormalization.display("Home", fallback: CadenceTitleNormalization.defaultAreaName) == "Home")
    }
}
