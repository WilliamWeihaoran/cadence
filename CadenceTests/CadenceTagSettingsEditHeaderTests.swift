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

    @Test func theMacEditFormOpensWithTheTagsTitleRow() throws {
        let file = "Cadence/macOS/Views/SettingsTagsSection.swift"
        let edit = try Self.body("private var editContent", in: file)
        let titleAt = try #require(edit.range(of: "tagTitle"), "the Mac edit form dropped the tag's title").lowerBound
        let nameAt = try #require(edit.range(of: "CadenceTagSettingsCopy.nameFieldPlaceholder")).lowerBound
        #expect(titleAt < nameAt, "the tag's title must sit above the form, not below it")
    }
}
