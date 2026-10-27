#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-7336: Escape closes the Mac event-note sheet, and only once the editor has no use for it.**
///
/// `EventNoteEditorSheet`'s one exit was a plain Done button, so Escape did nothing — the gap
/// T-7266, T-7268 and T-7289 closed in the other Mac sheets with a `.cancelAction` on the cancel
/// button. That spelling is wrong here: the sheet's body is the AppKit markdown editor, and a
/// `.cancelAction` is a key equivalent, offered every Escape before the text view sees it, so it
/// would close the sheet out from under an open picker, a table-cell edit, an inline task title or
/// the inline task panel. Instead the editor hands the host only an Escape all of those declined
/// (`MarkdownEditor.onUnhandledEscape`), and the pane closes an open task popover first.
///
/// The ordering and the wiring are source reads in `CadenceListEditorSheetKeyboardTests`' style —
/// no unit test can press a key in a sheet. The popover half is driven for real.
@MainActor
struct CadenceEventNoteSheetEscapeTests {
    private static let sheetPath = "Cadence/macOS/Views/EventNoteSupportViews.swift"
    private static let coordinatorPath = "Cadence/macOS/Editor/MarkdownEditorCoordinator.swift"
    private static let panePath = "Cadence/macOS/Views/NoteEditorPane.swift"

    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    @Test func sheetClosesOnEscapeThroughTheEditorAndOutsideIt() throws {
        let sheet = try Self.compactBody("struct EventNoteEditorSheet: View", in: Self.sheetPath)

        #expect(sheet.contains("onUnhandledEscape:{dismiss()}"), "an Escape the editor declined must close the sheet")
        #expect(sheet.contains(".onExitCommand{dismiss()}"), "Escape with focus outside the body must close the sheet")
        #expect(
            !sheet.contains(".keyboardShortcut("),
            "a .cancelAction is a key equivalent and would take Escape ahead of the editor's own uses"
        )
    }

    /// The host gets Escape LAST: after the three pickers and the inline task panel, and never
    /// during an IME composition. The table-cell and inline-title field editors answer to their own
    /// delegate and never reach this method.
    @Test func editorOffersEscapeToTheHostOnlyAfterItsOwnUses() throws {
        let method = try Self.compactBody(
            "func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool",
            in: Self.coordinatorPath
        )
        // The FIRST read of the host's closure, wherever and however it is spelled, so an
        // early-return added above the pickers cannot hide behind the later, correct one.
        let host = try #require(method.range(of: "parent.onUnhandledEscape"))
        #expect(method.components(separatedBy: "parent.onUnhandledEscape").count - 1 == 1)
        for earlier in [
            "handleTagPickerCommand(",
            "handleReferencePickerCommand(",
            "handleSlashCommandPickerCommand(",
            "cancelInlineTaskPanel()",
        ] {
            let found = try #require(method.range(of: earlier), "\(earlier) must still run")
            #expect(found.lowerBound < host.lowerBound, "\(earlier) must see Escape before the host does")
        }
        #expect(method.contains("!textView.hasMarkedText(),letonUnhandledEscape"))
    }

    @Test func paneClosesAnOpenPopoverBeforeHandingEscapeOn() throws {
        let pane = try Self.compactBody("struct NoteEditorPane: View", in: Self.panePath)
        #expect(pane.contains("if!embeds.closeOpenPopover(){hostEscape()}"))
    }

    @Test func closeOpenPopoverClosesEitherPopoverAndReportsIt() throws {
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "test-")
        #expect(handlers.closeOpenPopover() == false, "nothing open: Escape goes on to the host")

        handlers.linkedTaskForPopover = AppTask(title: "Linked")
        #expect(handlers.closeOpenPopover() == true)
        #expect(handlers.linkedTaskForPopover == nil)
        #expect(handlers.closeOpenPopover() == false, "the second Escape reaches the host")

        handlers.embeddedTaskEditRequest = TaskEmbedFieldEditRequest(taskID: UUID(), field: .priority)
        #expect(handlers.closeOpenPopover() == true)
        #expect(handlers.embeddedTaskEditRequest == nil)
    }
}
#endif
