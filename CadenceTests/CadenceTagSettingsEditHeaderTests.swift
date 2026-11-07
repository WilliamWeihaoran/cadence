import Foundation
import Testing
@testable import Cadence

/// **[[T-12284]].** Tapping a tag's pencil in iOS Settings > Tags swapped the row's whole display
/// content — where the tag's title lives — for the edit form, so the form hung under the PREVIOUS
/// tag's title, counts and archive button, and nothing on screen named the tag being edited.
///
/// Decided (keeper, 2026-11-06): keep the edited tag's own title (its colour dot and current
/// title) visible above the form. The Mac's tag card had the same swap; its card border kept the
/// form off the previous row, but it named the tag only through the Name field's value, so it
/// takes the same title row ([[T-8201]]: one app, two platforms).
///
/// A view cannot be rendered here, so this reads the source: each platform's edit form must draw
/// the very title view the display row draws, and that view must read the tag's current name,
/// not the draft being typed.
struct CadenceTagSettingsEditHeaderTests {

    private static func body(_ declaration: String, in file: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
        return try #require(CadenceSourceScan.declarationBody(declaration, in: source),
                            "\(file) no longer declares \(declaration)")
    }

    @Test(arguments: [
        "Cadence/iOS/iOSSettingsTagsSection.swift",
        "Cadence/macOS/Views/SettingsTagsSection.swift",
    ])
    func theEditFormDrawsTheTagsOwnCurrentTitle(file: String) throws {
        let title = try Self.body("private var tagTitle", in: file)
        #expect(title.contains("tag.name"), "\(file): the title row no longer reads the tag's name")
        #expect(!title.contains("draftName"), "\(file): the title row must name the tag, not echo the draft")

        let display = try Self.body("private var displayContent", in: file)
        #expect(display.contains("tagTitle"), "\(file): non-vacuity -- the display row draws the same title view")

        let edit = try Self.body("private var editContent", in: file)
        let header = edit.contains("editingHeader")
            ? try Self.body("private var editingHeader", in: file)
            : edit
        #expect(header.contains("tagTitle"), "\(file): the edit form no longer names the tag it edits")
    }

    /// The parameterised test above cannot be baselined by `mutate.sh` (T-3212); this sibling
    /// pins the iOS half alone, the platform the defect was seen on.
    @Test func theIOSEditFormOpensWithTheTagsTitleRow() throws {
        let file = "Cadence/iOS/iOSSettingsTagsSection.swift"
        let edit = try Self.body("private var editContent", in: file)
        let header = try Self.body("private var editingHeader", in: file)
        #expect(edit.contains("editingHeader"), "the iOS edit form dropped the tag's title row")
        #expect(header.contains("tagDot") && header.contains("tagTitle"),
                "the iOS edit header must carry the tag's colour dot and its title")
        // It comes first, above the Name field, so it reads as the form's header.
        let headerAt = try #require(edit.range(of: "editingHeader")).lowerBound
        let nameAt = try #require(edit.range(of: "iOSSettingsField(title: \"Name\")")).lowerBound
        #expect(headerAt < nameAt, "the tag's title row must sit above the form, not below it")
    }

    /// **[[T-12512]].** The iOS header dot filled the SAVED colour, so picking a swatch or typing a
    /// hex moved the strip below it but not the dot beside the tag's name; the Mac's edit dot
    /// previews the draft. The dot now reads the normalized draft, falling back to the saved colour
    /// while the Hex field holds something that is not yet a colour. The title stays the saved name.
    @Test func theIOSEditHeaderDotPreviewsTheDraftColour() throws {
        #expect(iOSTagSettingsEdit.headerDotHex(draft: "#3B82F6", saved: "#ef4444") == "#3b82f6")
        #expect(iOSTagSettingsEdit.headerDotHex(draft: " 3b82f6 ", saved: "#ef4444") == "#3b82f6")
        #expect(iOSTagSettingsEdit.headerDotHex(draft: "#3b8", saved: "#ef4444") == "#ef4444",
                "a half-typed hex previews the saved colour, as the swatch strip does")
        #expect(iOSTagSettingsEdit.headerDotHex(draft: "", saved: "#ef4444") == "#ef4444")

        func squeezed(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        let file = "Cadence/iOS/iOSSettingsTagsSection.swift"
        let header = squeezed(try Self.body("private var editingHeader", in: file))
        #expect(header.contains("tagDot(hex:iOSTagSettingsEdit.headerDotHex(draft:draftColorHex,saved:tag.colorHex))"),
                "the iOS edit header's dot must preview the draft colour")
        #expect(header.contains("tagTitle"), "the title beside it keeps the saved name")
        let display = squeezed(try Self.body("private var displayContent", in: file))
        #expect(display.contains("tagDot(hex:tag.colorHex)"), "the display row still draws the saved colour")

        // The Mac's edit dot, which this mirrors ([[T-8201]]).
        let macEdit = squeezed(try Self.body("private var editContent", in: "Cadence/macOS/Views/SettingsTagsSection.swift"))
        #expect(macEdit.contains("TagSupport.normalizedColorHex(draftColorHex,fallback:tag.colorHex)"))
    }

    @Test func theMacEditFormOpensWithTheTagsTitleRow() throws {
        let file = "Cadence/macOS/Views/SettingsTagsSection.swift"
        let edit = try Self.body("private var editContent", in: file)
        let titleAt = try #require(edit.range(of: "tagTitle"), "the Mac edit form dropped the tag's title").lowerBound
        let nameAt = try #require(edit.range(of: "CadenceTagSettingsCopy.nameFieldPlaceholder")).lowerBound
        #expect(titleAt < nameAt, "the tag's title must sit above the form, not below it")
    }
}
