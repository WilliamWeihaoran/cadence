import Foundation
import Testing
@testable import Cadence

/// **T-8103 (a): Escape closes the Mac create-task sheet.**
///
/// The in-window New Task panel (Cmd+N, `TaskCreationLayerView`) had no Escape at all: the sheet's
/// ✕ carried no shortcut, the sheet no exit command, and the root key monitor passes every
/// non-Command key through, so Escape reached the main window's `cancelOperation` and did nothing.
/// The ✕ now takes `.cancelAction`, as the Mac list sheets' Cancel did in T-7266. The quick-capture
/// panel shows the same sheet and its `dismissAction` is the `closeDiscardingDraft` its
/// `cancelOperation` already ran, so Escape means the same thing there.
///
/// A source read, because the defect is a modifier missing from a view body and no unit test can
/// press a key in a sheet. Read from the declaration body with comments stripped, so a shortcut
/// written in prose cannot answer for the button.
struct CadenceCreateTaskSheetEscapeTests {
    private static func sheetBody() throws -> String {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/CreateTaskSheet.swift")
        )
        let body = try #require(CadenceSourceScan.declarationBody("struct CreateTaskSheet: View", in: source))
        return body.filter { !$0.isWhitespace }
    }

    @Test func theCancelButtonTakesEscape() throws {
        let compact = try Self.sheetBody()
        #expect(
            compact.contains(#".buttonStyle(.cadencePlain).keyboardShortcut(.cancelAction).accessibilityLabel("Cancel")"#),
            "Escape must close the create-task sheet, from the same ✕ a click uses"
        )
        #expect(
            compact.contains("Button(action:dismiss){Image(systemName:\"xmark\")"),
            "the ✕ must still close through dismiss(), which honours the host's dismissAction"
        )
    }

    /// Exactly one Escape in the sheet: a second `.cancelAction` would make the key ambiguous.
    @Test func theSheetDeclaresOneCancelAction() throws {
        let compact = try Self.sheetBody()
        #expect(compact.components(separatedBy: ".keyboardShortcut(.cancelAction)").count - 1 == 1)
    }
}
