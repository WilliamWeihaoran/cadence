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
/// T-7292: `NoteActionDestinationRow` drew the note's current list (filled circle, blue title,
/// checkmark) and never told VoiceOver; it now carries `.isSelected` the way T-7267's list-sheet
/// cells do.
///
/// T-7293: iOS's `iOSNoteAIActionsMenu.label` named only the sparkles branch, so while an action ran
/// the header control was an unnamed spinner. The name now sits outside the branch, the way the
/// Mac pill's `cadenceControlLabel("Note actions")` covers both of its states.
///
/// Source reads in `CadenceListEditorSheetKeyboardTests`' style: no unit test can press a key in a
/// sheet, and the move rows are private views inside a popover. Read from declaration bodies so a
/// modifier elsewhere in the file cannot answer for these.
struct CadenceNoteActionSheetKeyboardTests {
    private static let sheetsPath = "Cadence/macOS/Views/NoteActionReviewSheets.swift"
    private static let menuPath = "Cadence/macOS/Views/AIActionsSupportViews.swift"
    private static let iosMenuPath = "Cadence/iOS/iOSAINoteActionsViews.swift"

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

        // [[T-8762]]: the rows name a list through the helper iOS's Move Note menu reads too, so
        // the fallback lives once, in `CadenceNoteMoveDestinations`.
        #expect(areas.contains("title:CadenceNoteMoveDestinations.title(for:area)"))
        #expect(projects.contains("title:CadenceNoteMoveDestinations.title(for:project)"))
        let shared = try Self.compactBody("enum CadenceNoteMoveDestinations", in: "Cadence/Shared/CadenceNoteMoveSupport.swift")
        #expect(shared.contains(
            "CadenceTitleNormalization.display(area.name,fallback:CadenceTitleNormalization.defaultAreaName)"
        ))
        #expect(shared.contains(
            "CadenceTitleNormalization.display(project.name,fallback:CadenceTitleNormalization.defaultProjectName)"
        ))
        #expect(!areas.contains("title:area.name,"))
        #expect(!projects.contains("title:project.name,"))
    }

    /// The fallback the rows now call is the one that turns a blank name into the Untitled noun —
    /// pinned on behaviour, so the source pin above cannot be satisfied by a helper that returns
    /// the raw string.
    @MainActor @Test func theFallbackTheRowsUseReadsUntitled() {
        #expect(CadenceTitleNormalization.display("", fallback: CadenceTitleNormalization.defaultAreaName) == "Untitled Area")
        #expect(CadenceTitleNormalization.display("   ", fallback: CadenceTitleNormalization.defaultProjectName) == "Untitled Project")
        #expect(CadenceTitleNormalization.display("Home", fallback: CadenceTitleNormalization.defaultAreaName) == "Home")
        // And the shared helper the rows now call ([[T-8762]]).
        #expect(CadenceNoteMoveDestinations.title(for: Area(name: "")) == "Untitled Area")
        #expect(CadenceNoteMoveDestinations.title(for: Project(name: "  ")) == "Untitled Project")
        #expect(CadenceNoteMoveDestinations.title(for: Area(name: "Home")) == "Home")
    }

    @Test func moveDestinationRowSaysWhichListIsSelected() throws {
        let row = try Self.compactBody("private struct NoteActionDestinationRow: View", in: Self.menuPath)

        #expect(
            row.contains("){action()}.accessibilityAddTraits(isSelected?.isSelected:[])"),
            "VoiceOver must hear which Move Note destination holds the note, on the row's own button"
        )
    }

    /// The name is applied to the whole `@ViewBuilder`, not to one branch of it, so the running
    /// spinner is named too — and exactly once, so a second per-branch label cannot drift from it.
    @Test func iOSAIButtonKeepsItsNameWhileAnActionRuns() throws {
        let label = try Self.compactBody("private var label: some View", in: Self.iosMenuPath)
        let content = try Self.compactBody("private var labelContent: some View", in: Self.iosMenuPath)
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iosMenuPath))
            .filter { !$0.isWhitespace }

        #expect(label.contains(#"labelContent.accessibilityLabel("AIactions")"#))
        #expect(content.contains("ifrunningAction!=nil{ProgressView()"), "the running branch must still be in the content")
        #expect(!content.contains(".accessibilityLabel("), "a per-branch label is the T-7293 shape")
        #expect(source.components(separatedBy: #".accessibilityLabel("AIactions")"#).count - 1 == 1)
    }
}
