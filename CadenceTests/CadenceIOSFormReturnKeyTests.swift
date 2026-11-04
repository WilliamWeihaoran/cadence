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

    /// [[T-10303]]: the description joined name and hex. It was `axis: .vertical`, where a
    /// hardware Return resigned the field with neither a newline nor a save; the Mac's tag card
    /// description is single-line and saves on Return ([[T-10033]]).
    @Test func tagCardEditorSavesOnReturnInItsSingleLineFields() throws {
        let editor = try Self.compactBody("private var editContent: some View", in: Self.tagsPath)
        #expect(
            Self.count(".onSubmit(requestSave)", in: editor) == 3,
            "Return in the tag card's name, description or hex field must save"
        )
        #expect(Self.count("TextField(", in: editor) == 3, "every field in the card is accounted for")
        #expect(!editor.contains("axis:"), "no tag card field is multi-line, as on the Mac")
        #expect(editor.contains(
            "TextField(CadenceTagSettingsCopy.descriptionFieldPlaceholder,text:$draftDescription).tagSettingsTextInput().onSubmit(requestSave)"
        ))
        #expect(editor.contains("isDisabled:!canSave,action:requestSave"))
        let request = try Self.compactBody("private func requestSave()", in: Self.tagsPath)
        #expect(request.contains("guardcanSaveelse{return}"))
    }

    /// [[T-10302]]: both description fields autocapitalised and autocorrected (`alpha` stored as
    /// `Alpha`) while NAME and HEX beside them did not. Every field on the screen now goes through
    /// one modifier that turns both off, as the Mac's fields type as written.
    @Test func everyTagSettingsFieldTypesAsWritten() throws {
        let file = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.tagsPath))
            .filter { !$0.isWhitespace }
        let fields = Self.count("TextField(", in: file)
        #expect(fields == 5, "Create Tag name/description, tag card name/description/hex")
        #expect(Self.count(".tagSettingsTextInput()", in: file) == fields,
                "every tag settings field goes through the one modifier")
        let createDescription = "TextField(CadenceTagSettingsCopy.descriptionFieldPlaceholder,text:$newDescription).tagSettingsTextInput()"
        let cardDescription = "TextField(CadenceTagSettingsCopy.descriptionFieldPlaceholder,text:$draftDescription).tagSettingsTextInput()"
        #expect(file.contains(createDescription))
        #expect(file.contains(cardDescription))
        let modifier = try Self.compactBody("func tagSettingsTextInput() -> some View", in: Self.tagsPath)
        #expect(modifier.contains("textInputAutocapitalization(.never)"))
        #expect(modifier.contains(".autocorrectionDisabled()"))
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
