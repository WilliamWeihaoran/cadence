import Testing
@testable import Cadence

/// **[[T-12743]].** The Mac tag card's "A tag with this name already exists." was bare red text,
/// while the same screen's Create Tag card and both of the phone's tag cards draw it as a
/// warning-icon notice row. No hardware constraint separates them ([[T-8201]]); the Mac edit card
/// now draws its `TagNoticeRow` too.
///
/// A view cannot be rendered here, so each platform's edit card is read from source.
@MainActor
struct CadenceTagSettingsDuplicateNoticeTests {

    private static func squeezedBody(_ declaration: String, in file: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source),
                                "\(file) no longer declares \(declaration)")
        return String(body.filter { !$0.isWhitespace })
    }

    private static let noticeRow =
        #"icon:"exclamationmark.triangle.fill",text:"Atagwiththisnamealreadyexists.""#

    @Test func theMacTagEditCardDrawsTheDuplicateNameAsANoticeRow() throws {
        let edit = try Self.squeezedBody("private var editContent",
                                         in: "Cadence/macOS/Views/SettingsTagsSection.swift")
        #expect(edit.contains("TagNoticeRow(" + Self.noticeRow),
                "the Mac tag card no longer draws the duplicate-name notice row")
        #expect(!edit.contains("Theme.red"),
                "the Mac tag card draws the duplicate name as bare red text again")
    }

    /// **[[T-12761]].** The tag picker's Edit Tag sheet was the last tag duplicate notice drawn as
    /// bare 11pt red text. It now draws Settings' own `TagNoticeRow` -- the shared row, not a copy.
    @Test func theTagPickerEditSheetDrawsTheDuplicateNameAsTheSharedNoticeRow() throws {
        let sheet = try Self.squeezedBody("private struct TagEditSheet: View",
                                          in: "Cadence/macOS/Views/TagPickerPopoverViews.swift")
        #expect(sheet.contains("ifhasDuplicateSlug{TagNoticeRow(" + Self.noticeRow),
                "the picker's Edit Tag sheet no longer draws the duplicate-name notice row")
        #expect(!sheet.contains("Theme.red"),
                "the picker's Edit Tag sheet draws the duplicate name as bare red text again")
        let picker = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TagPickerPopoverViews.swift"))
        #expect(!picker.contains("struct TagNoticeRow"),
                "the picker hand-rolls its own notice row instead of sharing Settings'")
        // Save's gate is unchanged: a duplicate name still disables Save.
        #expect(sheet.contains("!TagSupport.displayName(for:name).isEmpty&&!hasDuplicateSlug"))
    }

    /// The phone's card, the half the Mac now matches. Non-vacuity for the needle above.
    @Test func theIOSTagEditCardDrawsTheSameNoticeRow() throws {
        let edit = try Self.squeezedBody("private var editContent",
                                         in: "Cadence/iOS/iOSSettingsTagsSection.swift")
        #expect(edit.contains("iOSTagNoticeRow(" + Self.noticeRow),
                "the iOS tag card no longer draws the duplicate-name notice row")
    }
}
