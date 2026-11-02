import Foundation
import Testing
@testable import Cadence

/// **[[T-10016]] and [[T-10017]]: two Mac in-pane forms that ignored the key their siblings answer.**
///
/// - The Links tab's add form (`AddLinkBar`) had a Cancel button and nothing listening for Escape,
///   while the inline task composer and the list-note rename both leave on Escape. It now cancels
///   through the same `onCancel`, focus-scoped, never as a window-wide `.cancelAction`.
/// - The Focus Log Session popover's hours and minutes fields ignored Return, while Return commits
///   the Kanban column name, an inspector subtask and a saved link's URL. Return now logs, through
///   the same `submitLog()` as the Log button; Discard takes no key.
///
/// Source reads in `CadenceSettingsSheetKeyboardTests`' style: no unit test can press a key in a
/// pane or a popover. Read from the declaration's own body, so a handler elsewhere in the file
/// cannot answer.
struct CadenceMacInlineFormKeyboardTests {
    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    private static func count(_ needle: String, in compact: String) -> Int {
        compact.components(separatedBy: needle).count - 1
    }

    @Test func addLinkFormCancelsOnEscapeThroughItsOwnCancel() throws {
        let bar = try Self.compactBody(
            "private struct AddLinkBar: View",
            in: "Cadence/macOS/Views/LinksView.swift"
        )
        #expect(
            bar.contains(".onExitCommand(perform:onCancel)"),
            "Escape from a focused add-link field must cancel through onCancel"
        )
        #expect(
            bar.contains(".onKeyPress(.escape){onCancel()return.handled}"),
            "Escape must also cancel along SwiftUI's focus route"
        )
        #expect(
            Self.count(".keyboardShortcut(", in: bar) + Self.count("shortcut:.", in: bar) == 0,
            "a key equivalent would answer Escape or Return anywhere in the window"
        )
    }

    @Test func logSessionFieldsLogOnReturnAndDiscardTakesNoKey() throws {
        let popover = try Self.compactBody(
            "struct LogSessionPopover: View",
            in: "Cadence/macOS/Views/FocusLogSessionPopovers.swift"
        )
        #expect(
            popover.contains(".onSubmit(submitLog)"),
            "Return in the hours or minutes field must log"
        )
        #expect(
            popover.contains("privatefuncsubmitLog(){onLog(logHours,logMinutes,markComplete)}"),
            "Return and the Log button must read the same typed figures"
        )
        #expect(
            popover.contains("size:.compact){submitLog()}"),
            "the Log button must go through submitLog()"
        )
        #expect(
            Self.count(".keyboardShortcut(", in: popover) + Self.count("shortcut:.", in: popover) == 0,
            "Discard throws the session away and must take no key"
        )
    }
}
