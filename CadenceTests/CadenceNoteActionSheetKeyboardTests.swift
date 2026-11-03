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
/// sheets. Summary: Escape closes, Return appends. Drafts: Escape cancels, and plain Return is left
/// off Create Selected on purpose; [[T-7290]]'s owner call (2026-11-02) gave it Cmd+Return instead.
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

    /// Both spellings: a bare `.keyboardShortcut(` modifier, or `CadenceActionButton`'s
    /// `shortcut:` argument, which the footers use since [[T-9451]].
    private static func shortcutCount(_ compact: String) -> Int {
        (compact.components(separatedBy: ".keyboardShortcut(").count - 1)
            + (compact.components(separatedBy: "shortcut:.").count - 1)
    }

    @Test func summarySheetCloseTakesEscapeAndAppendTakesReturn() throws {
        let sheet = try Self.compactBody("struct AISummaryReviewSheet: View", in: Self.sheetsPath)

        #expect(
            sheet.contains(#"CadenceActionButton(title:CadenceAIReviewCopy.summaryCloseTitle,role:.ghost,size:.compact,shortcut:.cancelAction){dismiss()}"#),
            "Escape must close the Mac AI summary sheet"
        )
        #expect(
            sheet.contains(#"CadenceActionButton(title:CadenceAIReviewCopy.summaryAppendTitle,role:.primary,size:.compact,shortcut:.defaultAction){append()}"#),
            "Return must append the summary, through the same append() as the click"
        )
        #expect(Self.shortcutCount(sheet) == 2)
    }

    /// **[[T-7290]].** Cmd+Return creates, through the same `createSelected()` as the click, and
    /// stays behind `review.canCreate`; plain Return reaches nothing, because every draft card is a
    /// column of single-line fields and a `.defaultAction` would fire from any of them.
    @Test func draftSheetCancelTakesEscapeAndCreateTakesCommandReturn() throws {
        let sheet = try Self.compactBody("struct AITaskDraftReviewSheet: View", in: Self.sheetsPath)

        #expect(
            sheet.contains(#"CadenceActionButton(title:CadenceAIReviewCopy.draftsCancelTitle,role:.ghost,size:.compact,shortcut:.cancelAction){dismiss()}"#),
            "Escape must cancel the Mac AI task draft sheet"
        )
        #expect(
            sheet.contains(#"CadenceActionButton(title:CadenceAIReviewCopy.draftsCreateTitle,role:.primary,size:.compact,isDisabled:!review.canCreate,shortcut:KeyboardShortcut(.return,modifiers:.command)){createSelected()}"#),
            "Cmd+Return must create the approved drafts, gated like the click"
        )
        #expect(!sheet.contains("defaultAction"), "plain Return must not create every approved draft")
        // The two keys above and no third: Escape's `shortcut:.` and Cmd+Return's `shortcut:K`.
        #expect(Self.shortcutCount(sheet) == 1)
        #expect(sheet.components(separatedBy: "shortcut:KeyboardShortcut(").count - 1 == 1)
    }

    /// **[[T-7291]].** One word set for both platforms' AI review sheets, the Mac's (owner call,
    /// 2026-11-03), read by both from `CadenceAIReviewCopy`.
    @Test func bothPlatformsReviewSheetsSayTheMacsWords() throws {
        #expect(CadenceAIReviewCopy.summaryTitle == "AI Summary")
        #expect(CadenceAIReviewCopy.summaryCloseTitle == "Close")
        #expect(CadenceAIReviewCopy.summaryAppendTitle == "Append to Note")
        #expect(CadenceAIReviewCopy.draftsTitle == "AI Task Drafts")
        #expect(CadenceAIReviewCopy.draftsCaption == "Review each draft before creating anything in Cadence.")
        #expect(CadenceAIReviewCopy.draftsCancelTitle == "Cancel")
        #expect(CadenceAIReviewCopy.draftsCreateTitle == "Create Selected")

        let summary = try Self.compactBody("struct iOSAISummaryReviewSheet: View", in: Self.iosMenuPath)
        #expect(summary.contains(".navigationTitle(CadenceAIReviewCopy.summaryTitle)"))
        #expect(summary.contains("Button(CadenceAIReviewCopy.summaryCloseTitle){dismiss()}"))
        #expect(summary.contains("Button(CadenceAIReviewCopy.summaryAppendTitle){append()}"))
        #expect(!summary.contains(#""Discard""#), "the iOS summary sheet says Discard again")
        #expect(!summary.contains(#"Button("Append")"#), "the iOS summary sheet says a bare Append again")

        let drafts = try Self.compactBody("struct iOSAITaskDraftReviewSheet: View", in: Self.iosMenuPath)
        #expect(drafts.contains(".navigationTitle(CadenceAIReviewCopy.draftsTitle)"))
        #expect(drafts.contains("Text(CadenceAIReviewCopy.draftsCaption)"), "the iOS draft sheet lost the Mac's caption")
        #expect(drafts.contains("Button(CadenceAIReviewCopy.draftsCancelTitle){dismiss()}"))
        #expect(drafts.contains("Button(CadenceAIReviewCopy.draftsCreateTitle){createApproved()}"))
        #expect(!drafts.contains(#""TaskDrafts""#), "the iOS draft sheet's own title came back")
        #expect(!drafts.contains(#""Create\("#), "the iOS draft sheet counts its own Create again")

        let mac = try CadenceSourceScan.sourceFile(Self.sheetsPath)
        #expect(mac.contains("Text(CadenceAIReviewCopy.summaryTitle)"))
        #expect(mac.contains("Text(CadenceAIReviewCopy.draftsTitle)"))
        #expect(mac.contains("Text(CadenceAIReviewCopy.draftsCaption)"))
        for word in ["\"AI Summary\"", "\"AI Task Drafts\"", "\"Append to Note\"", "\"Create Selected\""] {
            #expect(!mac.contains(word), "the Mac sheet spells \(word) itself again")
        }
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
