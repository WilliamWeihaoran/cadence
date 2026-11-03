import Foundation
import Testing
@testable import Cadence

/// **[[T-8563]]: one spelling for each small word the list surfaces said two ways.** The owner's
/// decision of 2026-11-02: "Create" on a creation sheet, "Unarchive" for an archived list, the
/// plural due-date toggles, and an edit control named for its list. `Cadence/iOS/` is not compiled
/// by the macOS leg, so the phone's half is read off the source; the words themselves are values.
@MainActor
struct CadenceListVocabularyParityTests {
    private static func ios(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    @Test func theSharedListWordsAreTheDecidedSpellings() {
        #expect(CadenceListVocabularyCopy.createActionTitle == "Create")
        #expect(CadenceListVocabularyCopy.unarchiveActionTitle == "Unarchive")
        #expect(CadenceListVocabularyCopy.hideEmptyTaskDueDatesToggle == "Hide empty task due dates")
        #expect(CadenceListVocabularyCopy.hideEmptyColumnDueDatesToggle == "Hide empty column due dates")
    }

    /// (e): the edit control names the list it edits, and a blank name reads the header's own
    /// fallback title rather than a dangling "Edit ".
    @Test func theListHeaderEditControlIsNamedForItsList() {
        #expect(ListDetailHeaderAccessibility.editLabel(listName: "Roadmap") == "Edit Roadmap")
        #expect(
            ListDetailHeaderAccessibility.editLabel(listName: "  ")
                == "Edit \(TaskTitleSupport.defaultCompactDisplayTitle)"
        )
        #expect(!TaskTitleSupport.defaultCompactDisplayTitle.isEmpty, "non-vacuity: no fallback title")
    }

    @Test func bothListHeadersNameTheirEditControlThroughTheSharedLabel() throws {
        let phone = try Self.ios("Cadence/iOS/iOSListDetailView.swift")
        let header = try #require(CadenceSourceScan.declarationBody("private struct iOSListDetailHeader: View", in: phone))
        #expect(header.contains("accessibilityLabel: ListDetailHeaderAccessibility.editLabel(listName: title)"))
        #expect(!phone.contains("\"Edit list\""), "the iOS header names no list again")

        let mac = try Self.ios("Cadence/macOS/Views/ListDetailView.swift")
        #expect(mac.contains("accessibilityLabel: ListDetailHeaderAccessibility.editLabel(listName: name)"))
        #expect(!mac.contains("accessibilityLabel: \"Edit \\("), "the Mac header spells its own edit label")
    }

    /// (a): the phone's New List and New Context sheets confirm with "Create"; their edit modes
    /// keep "Save".
    @Test func thePhoneCreationSheetsConfirmWithCreate() throws {
        for (path, sheet) in [
            ("Cadence/iOS/iOSListEditorViews.swift", "struct iOSListEditorSheet: View"),
            ("Cadence/iOS/iOSSettingsContextSection.swift", "struct iOSContextEditorSheet: View")
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(sheet, in: try Self.ios(path)), "no \(sheet)")
            #expect(
                CadenceSourceScan.matchCount(
                    #"Button\(isEditing \? "Save" : CadenceListVocabularyCopy\.createActionTitle\)"#,
                    in: body
                ) == 1,
                "\(sheet) does not confirm a creation with Create"
            )
            #expect(!body.contains("Button(\"Save\")"), "\(sheet) confirms a creation with Save again")
        }
    }

    /// (b): an archived list comes back through "Unarchive" on the phone's Lists page, as it does
    /// in Settings on both platforms, and the archive confirmation says the same verb.
    @Test func anArchivedListIsUnarchivedOnEverySurface() throws {
        let support = try Self.ios("Cadence/iOS/iOSListSupportViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("struct iOSArchivedListRow: View", in: support))
        #expect(row.contains("title: CadenceListVocabularyCopy.unarchiveActionTitle,"))
        #expect(!row.contains("\"Restore\""), "the archived list row says Restore again")

        let windDown = try Self.ios("Cadence/iOS/iOSListWindDownSupport.swift")
        #expect(windDown.contains("moves to Archived and can be unarchived from there"))
        #expect(windDown.range(of: "restor", options: .caseInsensitive) == nil, "the archive confirmation says restore")

        for path in ["Cadence/iOS/iOSSettingsTemplateAndListSections.swift", "Cadence/macOS/Views/SettingsListManagementSections.swift"] {
            let code = try Self.ios(path)
            #expect(
                CadenceSourceScan.matchCount(#"CadenceListVocabularyCopy\.unarchiveActionTitle"#, in: code) == 2,
                "\(path) does not unarchive an area and a project through the shared word"
            )
            #expect(!code.contains("\"Unarchive\""), "\(path) spells its own Unarchive")
        }
    }

    /// (a), Mac half: the Mac's New List and New Context sheets confirm through the same word.
    @Test func theMacCreationSheetsConfirmThroughTheSharedWord() throws {
        for path in ["Cadence/macOS/Sheets/CreateListSheet.swift", "Cadence/macOS/Sheets/CreateContextSheet.swift"] {
            let code = try Self.ios(path)
            #expect(code.contains("confirmTitle: CadenceListVocabularyCopy.createActionTitle,"), "\(path)")
            #expect(!code.contains("confirmTitle: \"Create\""), "\(path) spells its own Create")
        }
    }

    /// (c): every list editor on both platforms reads the plural toggles through the shared words.
    @Test func everyListEditorReadsThePluralDueDateToggles() throws {
        let editor = try Self.ios("Cadence/iOS/iOSListEditorViews.swift")
        #expect(editor.contains("Toggle(CadenceListVocabularyCopy.hideEmptyTaskDueDatesToggle,"))
        #expect(editor.contains("Toggle(CadenceListVocabularyCopy.hideEmptyColumnDueDatesToggle,"))
        #expect(!editor.contains("Toggle(\"Hide empty"), "the iOS editor spells its own toggle")

        // CreateListSheet draws one pair; EditListSheet draws one per editor (area, project).
        for (path, pairs) in [("Cadence/macOS/Sheets/CreateListSheet.swift", 1), ("Cadence/macOS/Sheets/EditListSheet.swift", 2)] {
            let code = try Self.ios(path)
            #expect(CadenceSourceScan.matchCount(#"label: CadenceListVocabularyCopy\.hideEmptyTaskDueDatesToggle,"#, in: code) == pairs, "\(path)")
            #expect(CadenceSourceScan.matchCount(#"label: CadenceListVocabularyCopy\.hideEmptyColumnDueDatesToggle,"#, in: code) == pairs, "\(path)")
            #expect(!code.contains("\"Hide empty"), "\(path) spells its own due-date toggle")
        }
    }

    /// (d): the name placeholders carry no ellipsis and come from one place on both platforms.
    @Test func everyListEditorNamesItsFieldThroughTheSharedPlaceholders() throws {
        #expect(CadenceListVocabularyCopy.areaNamePlaceholder == "Area name")
        #expect(CadenceListVocabularyCopy.projectNamePlaceholder == "Project name")
        for path in [
            "Cadence/iOS/iOSListEditorViews.swift",
            "Cadence/macOS/Sheets/CreateListSheet.swift",
            "Cadence/macOS/Sheets/EditListSheet.swift"
        ] {
            let code = try Self.ios(path)
            #expect(code.contains("CadenceListVocabularyCopy.areaNamePlaceholder"), "\(path)")
            #expect(code.contains("CadenceListVocabularyCopy.projectNamePlaceholder"), "\(path)")
            #expect(!code.contains("\"Area name"), "\(path) spells its own area placeholder")
            #expect(!code.contains("\"Project name"), "\(path) spells its own project placeholder")
        }
    }
}
