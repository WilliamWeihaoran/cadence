import Foundation
import Testing
@testable import Cadence

/// **[[T-8584]]: the note editor offers one command set on the Mac and on iPhone/iPad.**
///
/// The Mac's format toolbar had Highlight and no Paragraph, iOS's had Paragraph and no Highlight;
/// the Mac's `/` menu listed the note's templates and iOS's did not; the Mac's `[[` picker kept
/// eight matches and iOS's strip six. None answered a hardware or input constraint ([[T-8201]]),
/// so each platform now has the union, read from one shared answer. The catalog and the `/` offer
/// are pure `Services/` values and are tested as behaviour; the iOS call sites are SwiftUI views
/// this macOS target does not compile, so their half is a source scan that they read the shared
/// answer and add nothing to it.
struct CadenceNoteEditorCommandParityTests {
    private static let macToolbarPath = "Cadence/macOS/Editor/MarkdownEditorView.swift"
    private static let iOSToolbarPath = "Cadence/iOS/iOSMarkdownAccessoryViews.swift"
    private static let iOSSurfacePath = "Cadence/iOS/iOSMarkdownEditingSurface.swift"

    private func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: - The toolbar

    @Test func theToolbarCatalogCarriesTheUnionOfBothPlatformsCommands() {
        let commands = MarkdownFormatToolbarCatalog.items.map(\.command)
        // The two the platforms each lacked.
        #expect(commands.contains(.paragraph), "iOS's Paragraph is missing from the shared toolbar")
        #expect(commands.contains(.highlight), "the Mac's Highlight is missing from the shared toolbar")
        // And everything both already had.
        let both: [MarkdownFormatCommand] = [
            .heading(1), .heading(2), .bold, .italic, .strikethrough, .inlineCode, .link, .noteLink,
            .taskReference, .unorderedList, .orderedList, .todoList, .quote, .codeBlock, .divider,
        ]
        for command in both {
            #expect(commands.contains(command), "the shared toolbar dropped .\(command)")
        }
        #expect(commands.count == both.count + 2)
        #expect(Set(commands).count == commands.count, "a command appears twice")
        #expect(Set(MarkdownFormatToolbarCatalog.items.map(\.id)).count == commands.count, "two items share an id")
    }

    @Test func everyItemIsNamedByTheSharedTitleTable() {
        for item in MarkdownFormatToolbarCatalog.items {
            #expect(item.title == MarkdownFormatCommandTitle.sentenceCase(for: item.command))
            #expect(item.title != "Insert", "a snippet command reached the toolbar")
        }
        #expect(MarkdownFormatToolbarCatalog.items.first?.glyph == .text("P"))
    }

    /// The compact row is the one width answer left: it keeps a few items in line and moves the
    /// rest into its overflow menu, so between them they must be the whole catalog, each once.
    @Test func theCompactRowAndItsOverflowPartitionTheCatalog() {
        let all = MarkdownFormatToolbarCatalog.items.map(\.command)
        let compact = MarkdownFormatToolbarCatalog.compactItems.map(\.command)
        let overflow = MarkdownFormatToolbarCatalog.compactOverflowItems.map(\.command)

        #expect(compact == MarkdownFormatToolbarCatalog.compactCommands, "a compact command is not in the catalog")
        #expect(compact.count + overflow.count == all.count)
        #expect(Set(compact).isDisjoint(with: overflow))
        #expect(Set(compact).union(overflow) == Set(all))
        // Overflow keeps catalog order.
        #expect(overflow == all.filter { !compact.contains($0) })
        // The width reason: fewer in-line items than the full row.
        #expect(compact.count < all.count)
        #expect(overflow.contains(.highlight) && overflow.contains(.paragraph))
    }

    @Test func separatorsFallBetweenGroups() {
        let groups = MarkdownFormatToolbarCatalog.groups
        let indices = MarkdownFormatToolbarCatalog.separatorIndices
        #expect(indices.count == groups.count - 1)
        var start = 0
        for group in groups.dropLast() {
            start += group.count
            #expect(indices.contains(start))
        }
        #expect(!indices.contains(0))
    }

    @Test func theMacToolbarDrawsTheSharedCatalog() throws {
        let source = try code(Self.macToolbarPath)
        let toolbar = try #require(CadenceSourceScan.declarationBody("private struct MarkdownEditorToolbar: View", in: source))
        #expect(toolbar.contains("ForEach(Array(MarkdownFormatToolbarCatalog.groups.enumerated()), id: \\.offset)"))
        #expect(toolbar.contains("toolbarControl(for: item)"))
        // The only commands spelled out are the two reference menus' blank actions; every other
        // button runs `item.command`.
        #expect(CadenceSourceScan.matchCount(#"performMarkdownFormatCommand\(\.[a-zA-Z]+"#, in: toolbar) == 2)
        #expect(CadenceSourceScan.matchCount(#"performMarkdownFormatCommand\(item\.command\)"#, in: toolbar) == 2)
        #expect(!toolbar.contains("\"highlighter\""), "the Mac toolbar spells its own items again")
    }

    @Test func theIOSToolbarDrawsTheSharedCatalog() throws {
        let source = try code(Self.iOSToolbarPath)
        let toolbar = try #require(CadenceSourceScan.declarationBody("struct iOSMarkdownFormatToolbar: View", in: source))
        #expect(toolbar.contains("MarkdownFormatToolbarCatalog.items"))
        #expect(toolbar.contains("MarkdownFormatToolbarCatalog.compactItems"))
        #expect(toolbar.contains("MarkdownFormatToolbarCatalog.compactOverflowItems"))
        #expect(toolbar.contains("MarkdownFormatToolbarCatalog.separatorIndices.contains(index)"))
        #expect(!source.contains("iOSMarkdownFormatToolbarItem"), "iOS keeps a second item list")
        #expect(CadenceSourceScan.matchCount(#"\.icon\("[a-zA-Z.]+", \."#, in: source) == 0)
    }

    // MARK: - The `/` menu

    @Test func theSharedSlashOfferAppendsTemplatesAndDropsRefusedImages() {
        let template = NoteTemplate(id: "probe", title: "Probe", subtitle: "Probe", body: "# Probe")
        let builtIns = MarkdownSlashCommand.all.map(\.id)

        let offered = MarkdownSlashCommand.offered(templates: [template], allowingImages: true)
        #expect(offered.map(\.id) == builtIns + ["probe"])

        let refused = MarkdownSlashCommand.offered(templates: [template], allowingImages: false)
        #expect(refused.map(\.id) == builtIns.filter { $0 != "image" } + ["probe"])

        #expect(MarkdownSlashCommand.offered(templates: [], allowingImages: true).map(\.id) == builtIns)
    }

    @Test func bothPlatformsSlashMenusReadTheSharedOffer() throws {
        let mac = try code(Self.macToolbarPath)
        #expect(mac.contains("MarkdownSlashCommand.offered(templates: slashTemplates, allowingImages: allowsImageInsertion)"))

        let surface = try code(Self.iOSSurfacePath)
        let choices = try #require(CadenceSourceScan.functionBody(named: "slashCommandChoices", in: surface))
        #expect(choices.contains("MarkdownSlashCommand.offered("))
        #expect(choices.contains("templates: slashTemplates,"))
        #expect(surface.contains("NoteTemplateLibrary.templates(for: slashTemplateKind, overridesRaw: noteTemplateOverridesRaw)"))
    }

    /// The iOS hosts that pass templates are the note editors — the hosts that pass
    /// `slashTemplates:` on the Mac edit a note too — and the editor still defaults to none.
    @Test func theIOSNoteEditorsHandTheirTemplatesToSlash() throws {
        #expect(try code(Self.iOSSurfacePath).contains("var slashTemplateKind: NoteKind? = nil"))
        let notes = try code("Cadence/iOS/iOSNotesView.swift")
        #expect(CadenceSourceScan.matchCount(#"slashTemplateKind: note\.kind,"#, in: notes) == 2)
        let listNotes = try code("Cadence/iOS/iOSListNotesView.swift")
        #expect(CadenceSourceScan.matchCount(#"slashTemplateKind: note\.kind,"#, in: listNotes) == 1)
        // A task's notes, an event draft and a template body offer none, as on the Mac.
        for path in [
            "Cadence/iOS/iOSTaskDetailSheetSections.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift",
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
        ] {
            #expect(!(try code(path)).contains("slashTemplateKind:"), "\(path) offers templates from /")
        }
    }

    // MARK: - The `[[` shortlist

    @Test func bothPlatformsReferenceShortlistsReadOneLimit() throws {
        #expect(MarkdownReferenceCompletionSupport.inlineShortlistLimit == 8)

        let surface = try code(Self.iOSSurfacePath)
        let choices = try #require(CadenceSourceScan.functionBody(named: "referenceCompletionChoices", in: surface))
        #expect(CadenceSourceScan.matchCount(#"\.prefix\(MarkdownReferenceCompletionSupport\.inlineShortlistLimit\)"#, in: choices) == 2)
        #expect(CadenceSourceScan.matchCount(#"\.prefix\(\d+\)"#, in: choices) == 0)

        let picker = try code("Cadence/macOS/Editor/MarkdownSlashCommandSupport.swift")
        #expect(picker.contains(".prefix(MarkdownReferenceCompletionSupport.inlineShortlistLimit)"))
    }
}
