import Foundation
import Testing
@testable import Cadence

/// **[[T-10044]] and [[T-10045]]: four iOS editors that ignored Return on an iPad hardware
/// keyboard, where their Mac siblings commit.**
///
/// - Settings > Tags: the Create Tag name and description fields and a tag card's name and hex
///   fields. The Mac's same fields commit on Return since [[T-10033]].
/// - The Context editor sheet and the list editor sheet (Area / Project): Return confirms the
///   Mac's New Context and list sheets since [[T-7266]].
///
/// Every Return goes through the button's own function, and the two sheets' Return is refused on
/// the same blank name that disables Save. Source reads in `CadenceMacInlineFormKeyboardTests`'
/// style, comments stripped, from each declaration's own body: no unit test can press a key, and
/// these files are `#if os(iOS)`.
struct CadenceIOSFormReturnKeyTests {
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

    @Test func createTagFieldsCreateOnReturnThroughTheButtonsOwnFunction() throws {
        let section = try Self.compactBody("struct iOSTagsSettingsSection: View", in: Self.tagsPath)
        #expect(
            Self.count(".onSubmit(createTag)", in: section) == 2,
            "Return in the Create Tag name or description field must create"
        )
        #expect(section.contains("action:createTag"), "the Create Tag button calls the same function")
        let create = try Self.compactBody("private func createTag()", in: Self.tagsPath)
        #expect(
            create.contains("guardcaselet.creatable("),
            "createTag must refuse what the disabled button refuses before it inserts"
        )
    }

    @Test func tagCardEditorSavesOnReturnInItsSingleLineFields() throws {
        let editor = try Self.compactBody("private var editContent: some View", in: Self.tagsPath)
        #expect(
            Self.count(".onSubmit(requestSave)", in: editor) == 2,
            "Return in the tag card's name or hex field must save"
        )
        #expect(editor.contains("isDisabled:!canSave,action:requestSave"))
        let request = try Self.compactBody("private func requestSave()", in: Self.tagsPath)
        #expect(request.contains("guardcanSaveelse{return}"))
    }

    @Test func contextEditorSavesOnReturnUnlessTheNameIsBlank() throws {
        let sheet = try Self.compactBody("struct iOSContextEditorSheet: View", in: Self.contextPath)
        #expect(sheet.contains("TextField(\"Contextname\",text:$name).submitLabel(.done).onSubmit(submitName)"))
        #expect(Self.count(".onSubmit(", in: sheet) == 1)
        let submit = try Self.compactBody("private func submitName()", in: Self.contextPath)
        #expect(submit.contains("guard!trimmedName.isEmptyelse{return}save()"))
        #expect(sheet.contains(".disabled(trimmedName.isEmpty)"), "Save is gated on the same blank name")
    }

    @Test func listEditorSavesOnReturnUnlessTheNameIsBlank() throws {
        let sheet = try Self.compactBody("struct iOSListEditorSheet: View", in: Self.listEditorPath)
        #expect(sheet.contains(".submitLabel(.done).onSubmit(submitName)"))
        #expect(Self.count(".onSubmit(", in: sheet) == 1)
        let submit = try Self.compactBody("private func submitName()", in: Self.listEditorPath)
        #expect(submit.contains("guard!trimmedName.isEmptyelse{return}save()"))
        #expect(sheet.contains(".disabled(trimmedName.isEmpty)"), "Save is gated on the same blank name")
    }

    /// The list editor's column row is "the board's own column header in miniature"; it drew an
    /// 8pt dot beside the header's 7.
    @Test func listEditorColumnRowDrawsTheBoardHeadersDot() throws {
        let row = try Self.compactBody("private struct iOSSectionDraftRow: View", in: Self.listEditorPath)
        #expect(row.contains(
            ".frame(width:CadenceBoardColumnHeaderMetrics.dotSize,height:CadenceBoardColumnHeaderMetrics.dotSize)"
        ))
        #expect(!row.contains(".frame(width:8,height:8)"))
    }
}
