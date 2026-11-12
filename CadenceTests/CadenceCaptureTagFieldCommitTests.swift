import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-17326]] and [[T-17327]] -- two tag doors that answered differently from every other.**
///
/// [[T-17326]]: the capture card's "New tag" field (the Mac's Cmd+N sheet and the iOS New Task
/// sheet) handed any non-blank name to `committedTag`. An archived tag's name therefore selected
/// the archived row, which the card's tag list hides -- the field cleared, no chip appeared, and
/// the task was created carrying it -- and `--` minted a tag named `--`, a name Create Tag, the
/// pickers' fields and rename all refuse.
///
/// [[T-17327]]: the Mac tag picker's Edit Tag sheet saved a half-typed Hex field as the default
/// grey, where both Settings > Tags editors keep the tag's saved colour.
struct CadenceCaptureTagFieldCommitTests {

    private struct Refused: Error {}

    private func makeStore() throws -> (ModelContainer, ModelContext, active: Cadence.Tag, archived: Cadence.Tag) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let work = Cadence.Tag(name: "Work", slug: "work", order: 0)
        let errand = Cadence.Tag(name: "Errand", slug: "errand", order: 1, isArchived: true)
        context.insert(work)
        context.insert(errand)
        try context.save()
        return (container, context, work, errand)
    }

    private func allTags(_ context: ModelContext) throws -> [Cadence.Tag] {
        try context.fetch(FetchDescriptor<Cadence.Tag>())
    }

    /// **Behavioural.** An archived tag's typed name comes back un-archived, so the chip it selects
    /// is one the card's list (active tags only) draws -- and no second `errand` is minted.
    @Test func anArchivedTagsNameIsUnarchivedNotSelectedHidden() throws {
        let (_, context, _, archived) = try makeStore()
        let tags = try allTags(context)

        let picked = try #require(TagSupport.committedFieldTag(named: "errand", in: tags, context: context))
        #expect(picked.id == archived.id)
        #expect(!picked.isArchived, "the card would select a tag its own list hides")
        #expect(!context.hasChanges, "the un-archive was left pending")
        #expect(try allTags(context).count == 2, "a second errand was minted")
        let captureChoices = TagSupport.uniqueBySlug(try allTags(context).filter { !$0.isArchived })
        #expect(captureChoices.contains { $0.id == picked.id }, "the selected chip is not in the card's list")
    }

    /// **Behavioural.** An active tag's name still resolves to it, and a new name still mints one.
    @Test func anActiveNameResolvesAndANewNameMints() throws {
        let (_, context, active, _) = try makeStore()
        let tags = try allTags(context)

        let resolved = try #require(TagSupport.committedFieldTag(named: "work", in: tags, context: context))
        #expect(resolved.id == active.id)

        let minted = try #require(TagSupport.committedFieldTag(named: "Garden", in: tags, context: context))
        #expect(minted.name == "Garden")
        #expect(!minted.isArchived)
        #expect(try allTags(context).count == 3)
    }

    /// **Behavioural.** A refused un-archive puts the flag back and answers `nil`, which the sheets
    /// turn into their failure notice.
    @Test func aRefusedUnarchiveLeavesTheTagArchived() throws {
        let (_, context, _, archived) = try makeStore()
        let tags = try allTags(context)

        let picked = TagSupport.committedFieldTag(
            named: "Errand", in: tags, context: context, commit: { _ in throw Refused() }
        )
        #expect(picked == nil)
        #expect(archived.isArchived)
    }

    /// **Behavioural.** The field's Add/Return gate refuses a name with no letter or digit, as the
    /// iOS picker's `+` does ([[T-13501]]); any script's letters still count.
    @Test func theNewTagFieldRefusesANameWithNoLetterOrDigit() {
        for name in ["--", " !! ", "#", "###", "-_-"] {
            #expect(CadenceCaptureTagEntry.submittableName(name) == nil, "\(name) would mint an unusable tag")
        }
        #expect(CadenceCaptureTagEntry.submittableName(" q1 ") == "q1")
        #expect(CadenceCaptureTagEntry.submittableName("工作") == "工作")
        #expect(CadenceCaptureTagEntry.submittableName("#work") == "#work")
    }

    /// **Source shape.** Both capture sheets reach the field decision, not `committedTag` directly.
    @Test func bothCaptureSheetsCommitTheirNewTagFieldThroughTheFieldDecision() throws {
        for path in ["Cadence/macOS/Sheets/CreateTaskSheet.swift", "Cadence/iOS/iOSCreateTaskSheet.swift"] {
            let sheet = try CadenceCommitSurfaceScan.scanned(path)
            let body = try CadenceCommitSurfaceScan.declarationBody(named: "createTag", in: sheet)
            #expect(body.contains("TagSupport.committedFieldTag(named: name, in: tags, context: modelContext)"), "\(path)")
            #expect(!body.contains("TagSupport.committedTag("), "\(path) skips the archived match")
        }
    }

    /// **[[T-17327]], source shape.** Every tag editor's Save keeps the saved colour for a draft
    /// that is not yet a colour. The macOS target cannot drive a SwiftUI sheet's private save, so
    /// the three saves are read from source; the rule they share is asserted as a value below.
    @Test func everyTagEditorSaveFallsBackToTheSavedColour() throws {
        let saves: [(path: String, draft: String)] = [
            ("Cadence/macOS/Views/TagPickerPopoverViews.swift", "editColorHex"),
            ("Cadence/macOS/Views/SettingsTagsSection.swift", "draftColorHex"),
            ("Cadence/iOS/iOSSettingsTagsSection.swift", "colorHex"),
        ]
        for save in saves {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(save.path))
            #expect(
                source.contains("tag.colorHex = TagSupport.normalizedColorHex(\(save.draft), fallback: tag.colorHex)"),
                "\(save.path) saves a half-typed hex as the default grey"
            )
            #expect(
                CadenceSourceScan.matchCount(#"tag\.colorHex = TagSupport\.normalizedColorHex\(\w+\)"#, in: source) == 0,
                "\(save.path) still stores a colour with no fallback"
            )
        }
        #expect(TagSupport.normalizedColorHex("#ff6", fallback: "#ff6b6b") == "#ff6b6b")
        #expect(TagSupport.normalizedColorHex("", fallback: "#ff6b6b") == "#ff6b6b")
        #expect(TagSupport.normalizedColorHex("#5AA2FF", fallback: "#ff6b6b") == "#5aa2ff")
    }
}
