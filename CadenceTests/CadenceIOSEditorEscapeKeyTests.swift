import Foundation
import Testing
@testable import Cadence

/// **[[T-10046]]: three iOS editors that ignored Escape on an iPad hardware keyboard, where their
/// Mac siblings cancel.**
///
/// - The Context editor sheet and the list editor sheet (Area / Project): the Mac's New Context and
///   list sheets' Cancel carries `.cancelAction` since [[T-7266]], so the iOS toolbar Cancel does too.
/// - A Settings tag card's inline editor: the Mac's tag card cancels on Escape since [[T-10033]],
///   focus-scoped rather than a `.cancelAction`, because several cards can be open at once.
///
/// Each Escape goes through the Cancel control's own action. Source reads in
/// `CadenceIOSFormReturnKeyTests`' style, comments stripped, from each declaration's own body: no
/// unit test can press a key, and these files are `#if os(iOS)`.
struct CadenceIOSEditorEscapeKeyTests {
    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    private static func count(_ needle: String, in compact: String) -> Int {
        compact.components(separatedBy: needle).count - 1
    }

    private static let tagsPath = "Cadence/iOS/iOSSettingsTagsSection.swift"
    private static let contextPath = "Cadence/iOS/iOSSettingsContextSection.swift"
    private static let listEditorPath = "Cadence/iOS/iOSListEditorViews.swift"

    @Test func contextEditorCancelTakesEscape() throws {
        let sheet = try Self.compactBody("struct iOSContextEditorSheet: View", in: Self.contextPath)
        #expect(
            sheet.contains(#"Button("Cancel"){dismiss()}.keyboardShortcut(.cancelAction)"#),
            "Escape must cancel the iOS Context editor, from its own Cancel"
        )
        #expect(Self.count(".keyboardShortcut(", in: sheet) == 1, "only Cancel carries a key")
    }

    @Test func listEditorCancelTakesEscape() throws {
        let sheet = try Self.compactBody("struct iOSListEditorSheet: View", in: Self.listEditorPath)
        #expect(
            sheet.contains(#"Button("Cancel"){dismiss()}.keyboardShortcut(.cancelAction)"#),
            "Escape must cancel the iOS list editor, from its own Cancel"
        )
        #expect(Self.count(".keyboardShortcut(", in: sheet) == 1, "only Cancel carries a key")
    }

    @Test func tagCardEditorCancelsOnEscapeThroughTheCancelButtonsOwnFunction() throws {
        let row = try Self.compactBody("private struct iOSTagSettingsRow: View", in: Self.tagsPath)
        #expect(
            row.contains(#"iOSActionButton(title:"Cancel",role:.secondary,size:.compact,action:cancelEditing)"#),
            "the card's Cancel button calls cancelEditing"
        )
        #expect(
            row.contains(".onKeyPress(.escape){cancelEditing()return.handled}"),
            "Escape in the tag card editor must call the same cancelEditing"
        )
        #expect(
            !row.contains(".keyboardShortcut(.cancelAction)"),
            "focus-scoped, as on the Mac: several cards can be open at once"
        )
        let cancel = try Self.compactBody("private func cancelEditing()", in: Self.tagsPath)
        #expect(cancel.contains("saveFailureNotice=nil"))
        #expect(cancel.contains("isEditing=false"), "Cancel closes the editor, discarding the draft")
    }
}
