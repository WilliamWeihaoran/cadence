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
        #"icon:"exclamationmark.triangle.fill",text:CadenceTagSettingsCopy.duplicateNameNotice"#

    /// **[[T-13062]].** Every tag editor that can draw the duplicate-name notice, with how many
    /// times it draws it: the Mac Settings create and edit cards, the Mac tag picker's Edit Tag
    /// sheet, and the phone's create and edit cards. Named per file and counted, so a site that
    /// reverts to a literal reds even while its sibling in the same file still reads the constant.
    private static let duplicateNoticeSites: [(path: String, count: Int)] = [
        ("Cadence/macOS/Views/SettingsTagsSection.swift", 2),
        ("Cadence/macOS/Views/TagPickerPopoverViews.swift", 1),
        ("Cadence/iOS/iOSSettingsTagsSection.swift", 2),
    ]

    @Test func everyTagEditorReadsTheSharedDuplicateNameSentence() throws {
        #expect(CadenceTagSettingsCopy.duplicateNameNotice == "A tag with this name already exists.")
        var total = 0
        for site in Self.duplicateNoticeSites {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(site.path))
            let reads = CadenceSourceScan.matchCount(#"text: CadenceTagSettingsCopy\.duplicateNameNotice\b"#, in: source)
            total += reads
            #expect(reads == site.count,
                    "\(site.path) reads the shared duplicate-name sentence \(reads) times, expected \(site.count)")
            #expect(!source.contains("already exists."),
                    "\(site.path) spells a duplicate-name sentence instead of reading CadenceTagSettingsCopy")
        }
        #expect(total == 5, "non-vacuity: five tag editors draw the notice, found \(total)")
    }

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
        // Save's gate: a duplicate name still disables Save, through the shared rename rule
        // ([[T-15801]]), whose clash clause `TagRenameClashStableSlugTests` pins by behaviour.
        #expect(sheet.contains("TagSupport.canRename(tag,to:name,in:allTags)"))
    }

    /// The phone's card, the half the Mac now matches. Non-vacuity for the needle above.
    @Test func theIOSTagEditCardDrawsTheSameNoticeRow() throws {
        let edit = try Self.squeezedBody("private var editContent",
                                         in: "Cadence/iOS/iOSSettingsTagsSection.swift")
        #expect(edit.contains("iOSTagNoticeRow(" + Self.noticeRow),
                "the iOS tag card no longer draws the duplicate-name notice row")
    }
}
