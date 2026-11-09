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
        // [[T-14582]]: named for the one thing it controls, the Mac board card's empty Due token.
        #expect(CadenceListVocabularyCopy.hideEmptyTaskDueDatesToggle == "Hide empty due dates on board cards")
        #expect(CadenceListVocabularyCopy.hideEmptyTaskDueDatesTouchCaption == "Applies to board cards on Mac.")
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

    /// **[[T-12602]]: both list headers draw one edit glyph in the list's own colour.** iOS drew
    /// `slider.horizontal.3` in plain text colour; the Mac a pencil in `colorHex` ([[T-8201]]).
    @Test func bothListHeadersDrawTheSharedEditGlyphInTheListColour() throws {
        #expect(ListDetailHeaderAccessibility.editGlyph == "pencil")
        let phone = try Self.ios("Cadence/iOS/iOSListDetailView.swift")
        let header = try #require(CadenceSourceScan.declarationBody("private struct iOSListDetailHeader: View", in: phone))
        let mac = try Self.ios("Cadence/macOS/Views/ListDetailView.swift")
        let call = "systemImage: ListDetailHeaderAccessibility\\.editGlyph,\\s*"
            + "accessibilityLabel: ListDetailHeaderAccessibility\\.editLabel\\(listName: \\w+\\),\\s*"
            + "tint: Color\\(hex: colorHex\\)"
        #expect(CadenceSourceScan.matchCount(call, in: header) == 1, "the iOS header's edit control is not the shared pencil in the list colour")
        #expect(CadenceSourceScan.matchCount(call, in: mac) == 1, "the Mac header's edit control is not the shared pencil in the list colour")
        #expect(!header.contains("slider.horizontal.3"), "the iOS header draws the view-options glyph for edit again")
        #expect(!header.contains("systemImage: \"pencil\""), "the iOS header hand-types its edit glyph")
        #expect(!mac.contains("systemImage: \"pencil\",\n                    accessibilityLabel: ListDetailHeaderAccessibility"), "the Mac header hand-types its edit glyph")
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
        // Read over the file's string literals, i.e. its copy: since [[T-11614]] group (1) the
        // wind-down's code calls `CadenceListEditSnapshot.restore`, which is an undo, not a word.
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\\n]|\\.)*)""#)
        let windDownCopy = literal.matches(in: windDown, range: NSRange(windDown.startIndex..., in: windDown))
            .compactMap { Range($0.range(at: 1), in: windDown).map { String(windDown[$0]) } }
            .joined(separator: "\n")
        #expect(windDownCopy.contains("moves to Archived and can be unarchived from there"), "non-vacuity: the copy reader found no copy")
        #expect(windDownCopy.range(of: "restor", options: .caseInsensitive) == nil, "the archive confirmation says restore")

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
        // [[T-14582]]: the task half carries its touch caption under the shared words, because on
        // this device the switch changes nothing on screen (the touch card draws no empty token).
        #expect(editor.contains(
            "Toggle(isOn: $hideEmptyDueDates) {\n                        VStack(alignment: .leading, spacing: 2) {\n"
                + "                            Text(CadenceListVocabularyCopy.hideEmptyTaskDueDatesToggle)\n"
                + "                            Text(CadenceListVocabularyCopy.hideEmptyTaskDueDatesTouchCaption)\n"
        ))
        #expect(CadenceSourceScan.matchCount(#"CadenceListVocabularyCopy\.hideEmptyTaskDueDatesToggle"#, in: editor) == 1)
        #expect(editor.contains("Toggle(CadenceListVocabularyCopy.hideEmptyColumnDueDatesToggle,"))
        #expect(!editor.contains("Toggle(\"Hide empty"), "the iOS editor spells its own toggle")

        // CreateListSheet draws one pair; EditListSheet draws one per editor (area, project).
        for (path, pairs) in [("Cadence/macOS/Sheets/CreateListSheet.swift", 1), ("Cadence/macOS/Sheets/EditListSheet.swift", 2)] {
            let code = try Self.ios(path)
            #expect(CadenceSourceScan.matchCount(#"label: CadenceListVocabularyCopy\.hideEmptyTaskDueDatesToggle,"#, in: code) == pairs, "\(path)")
            #expect(CadenceSourceScan.matchCount(#"label: CadenceListVocabularyCopy\.hideEmptyColumnDueDatesToggle,"#, in: code) == pairs, "\(path)")
            #expect(!code.contains("\"Hide empty"), "\(path) spells its own due-date toggle")
            // The Mac half acts on the Mac's own board card, so it carries no "on Mac" caption.
            #expect(!code.contains("hideEmptyTaskDueDatesTouchCaption"), "\(path)")
        }
    }

    /// [[T-14582]]: the switch's whole reach, stated so a new reader has to update the copy. The
    /// stored flag answers one view field, `AppTask.shouldShowDueDateField`, and that is read by the
    /// Mac board card alone -- not by any task row, and not by the touch board card.
    @Test func theHideEmptyDueDatesFlagReachesOnlyTheMacBoardCard() throws {
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(paths.count > 300, "non-vacuity: the walk found \(paths.count) files")
        let readers = try paths.filter { path in
            guard !path.hasPrefix("Cadence/Models/") else { return false }
            return CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path)).contains("shouldShowDueDateField")
        }
        #expect(readers == ["Cadence/macOS/Views/KanbanCardView.swift"])
        let card = try Self.ios("Cadence/iOS/iOSBoardCards.swift")
        #expect(card.contains("struct iOSBoardTaskCard: View"), "non-vacuity")
        #expect(!card.contains("showsEmptyDueDate"))
        #expect(!card.contains("placeholders: true"))
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

    /// [[T-10571]]: an archived context or tag comes back through the same "Unarchive" as an
    /// archived list, on both platforms -- the archived-context rows, the Settings tag sections'
    /// "is archived" notices, the tag-completion subtitles and the Mac tag picker's row. Backup
    /// restore and the cancelled-task undo keep "Restore"; neither file is read here.
    @Test func anArchivedContextOrTagIsUnarchivedThroughTheSharedWord() throws {
        #expect(CadenceListVocabularyCopy.unarchiveTagSubtitle == "Unarchive tag")
        #expect(CadenceListVocabularyCopy.unarchiveRowTitle(name: "bug") == "Unarchive \"bug\"")
        #expect(CadenceTagChipStyle.unarchiveControlLabel(name: "Work", slug: "work") == "Unarchive Work")

        let sites: [(path: String, needle: String)] = [
            ("Cadence/iOS/iOSSettingsContextSection.swift", "title: CadenceListVocabularyCopy.unarchiveActionTitle,"),
            ("Cadence/macOS/Views/SettingsSupportViews.swift", "CadenceActionButton(title: CadenceListVocabularyCopy.unarchiveActionTitle, role: .secondary"),
            ("Cadence/iOS/iOSSettingsTagsSection.swift", "actionTitle: CadenceListVocabularyCopy.unarchiveActionTitle,"),
            ("Cadence/macOS/Views/SettingsTagsSection.swift", "actionTitle: CadenceListVocabularyCopy.unarchiveActionTitle"),
            ("Cadence/iOS/iOSMarkdownAccessoryViews.swift", "tag.isArchived ? CadenceListVocabularyCopy.unarchiveTagSubtitle :"),
            ("Cadence/macOS/Editor/MarkdownSlashCommandSupport.swift", "tag.isArchived ? CadenceListVocabularyCopy.unarchiveTagSubtitle :"),
            ("Cadence/macOS/Views/TagPickerPopoverViews.swift", "Text(CadenceListVocabularyCopy.unarchiveRowTitle(name: archivedQueryMatch.name))")
        ]
        for site in sites {
            let code = try Self.ios(site.path)
            #expect(code.contains(site.needle), "\(site.path) does not read the shared Unarchive")
            #expect(!code.contains("\"Restore"), "\(site.path) brings an archived thing back through Restore again")
        }
    }

    /// **[[T-12711]]: the phone's New List says what each type is for, as the Mac's does.** The
    /// Mac's type cards carried a line under Area and Project; the phone's segment drew the bare
    /// words ([[T-8201]]). Both now read one shared line, and the phone's follows the selection.
    @Test func theListTypeDescriptionFollowsTheChosenType() {
        #expect(CadenceListVocabularyCopy.listTypeDescription(isProject: false) == CadenceListVocabularyCopy.areaTypeDescription)
        #expect(CadenceListVocabularyCopy.listTypeDescription(isProject: true) == CadenceListVocabularyCopy.projectTypeDescription)
        #expect(CadenceListVocabularyCopy.areaTypeDescription == "Ongoing responsibility, no end date")
        #expect(CadenceListVocabularyCopy.projectTypeDescription == "Finite effort with a clear outcome")
        #if os(macOS)
        #expect(CreateListSheet.ListType.area.description == CadenceListVocabularyCopy.areaTypeDescription)
        #expect(CreateListSheet.ListType.project.description == CadenceListVocabularyCopy.projectTypeDescription)
        #endif
    }

    @Test func bothNewListTypeChoicesDrawTheSharedDescription() throws {
        let phone = try Self.ios("Cadence/iOS/iOSListEditorViews.swift")
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: phone))
        let chooser = try #require(CadenceSourceScan.declarationBody("if !isEditing", in: body))
        #expect(chooser.contains("iOSSegmentedChoice("), "non-vacuity: the chooser block is not the type segment")
        #expect(
            chooser.contains("Text(CadenceListVocabularyCopy.listTypeDescription(isProject: createsProject))"),
            "the phone's New List type segment draws no description of the chosen type"
        )

        let mac = try Self.ios("Cadence/macOS/Sheets/CreateListSheet.swift")
        #expect(mac.contains("case .area:    return CadenceListVocabularyCopy.areaTypeDescription"))
        #expect(mac.contains("case .project: return CadenceListVocabularyCopy.projectTypeDescription"))
        #expect(!mac.contains("\"Ongoing responsibility"), "the Mac type card spells its own description again")
        #expect(mac.contains("Text(type.description)"), "the Mac type card no longer draws its description")
    }
}
