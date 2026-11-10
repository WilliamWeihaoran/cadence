import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-12744]] — the tag pickers' query, one decision on both platforms.**
///
/// macOS's `TagPickerPopover` narrowed its list as you typed and iOS's `iOSTaskTagPickerPopover`
/// could not. Both now read `TagSupport.pickerQuery`; this drives it against a real in-memory
/// container. That both popovers call it is pinned by `CadenceNoteTagEditingTests`.
struct CadenceTagPickerQueryTests {

    private func makeTags() throws -> (ModelContainer, [Cadence.Tag]) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let work = Cadence.Tag(name: "Work", slug: "work")
        let homework = Cadence.Tag(name: "Homework", slug: "homework")
        let deepWork = Cadence.Tag(name: "Deep Work", slug: "deep-work")
        let errands = Cadence.Tag(name: "Errands", slug: "errands")
        let old = Cadence.Tag(name: "Old Project", slug: "old-project")
        old.isArchived = true
        let tags = [work, homework, deepWork, errands, old]
        for tag in tags { context.insert(tag) }
        return (container, tags)
    }

    @Test func anEmptyQueryListsEveryActiveChoiceAndOffersNothingElse() throws {
        let (_, tags) = try makeTags()
        for query in ["", "   "] {
            let decision = TagSupport.pickerQuery(query, in: tags)
            #expect(decision.matches.map(\.slug) == TagSupport.pickerChoices(from: tags).map(\.slug))
            #expect(decision.matches.count == 4, "the archived tag is not a choice")
            #expect(decision.createName == nil)
            #expect(decision.archivedMatch == nil)
            #expect(decision.placeholder == .none)
        }
    }

    @Test func typingNarrowsTheListByNameOrSlug() throws {
        let (_, tags) = try makeTags()
        // Case-insensitive on the name.
        #expect(Set(TagSupport.pickerQuery("WORK", in: tags).matches.map(\.slug)) == ["work", "homework", "deep-work"])
        // A space in the query reaches the hyphen in the slug.
        #expect(TagSupport.pickerQuery("p-wo", in: tags).matches.map(\.slug) == ["deep-work"])
        #expect(TagSupport.pickerQuery("errand", in: tags).matches.map(\.slug) == ["errands"])
        // An archived name is never a row, only an Unarchive offer.
        #expect(TagSupport.pickerQuery("old", in: tags).matches.isEmpty)
    }

    @Test func createIsOfferedOnlyWhenNoTagCarriesTheSlug() throws {
        let (_, tags) = try makeTags()
        // A prefix of an existing name: rows narrow, and the new name may still be made.
        let partial = TagSupport.pickerQuery("Wor", in: tags)
        #expect(partial.createName == "Wor")
        #expect(partial.placeholder == .none)
        // An existing name in another case is picked, not created again.
        let exact = TagSupport.pickerQuery("  deep work ", in: tags)
        #expect(exact.createName == nil)
        #expect(exact.matches.map(\.slug) == ["deep-work"])
        // A leading `#` is the same name.
        #expect(TagSupport.pickerQuery("#work", in: tags).createName == nil)
        // No alphanumeric, nothing to create.
        #expect(TagSupport.pickerQuery("#", in: tags).createName == nil)
        // A name nothing carries.
        #expect(TagSupport.pickerQuery("Garden", in: tags).createName == "Garden")
    }

    /// [[T-14472]]: the note editor's `#` picker holds slugs, not `Tag` rows, so it asks
    /// `creatableName(for:existingSlugs:)`; over one store that answers exactly as `pickerQuery`'s
    /// `createName`, and the `#` list leads with that Create row exactly when the task pickers
    /// would offer one.
    @Test @MainActor func theNoteHashPickerOffersCreateExactlyWhenTheTaskPickersDo() throws {
        let (_, tags) = try makeTags()
        let suggestions = MarkdownTagSuggestion.suggestions(from: tags)
        let queries = ["", "  ", "work", "Work", "wor", "home", "deep work", "deep-work", "old project",
                       "old", "errand", "Errands", "--", "#", "new tag", "  spaced  "]
        for query in queries {
            let createName = TagSupport.pickerQuery(query, in: tags).createName
            #expect(
                TagSupport.creatableName(for: query, existingSlugs: tags.map(\.slug)) == createName,
                "the slug form and pickerQuery disagree over \(query)"
            )
            let first = MarkdownTagPickerChoice.choices(query: query, suggestions: suggestions).first
            if let createName {
                #expect(first == .create(createName), "the # picker does not lead with Create for \(query)")
            } else if case .create = first {
                Issue.record("the # picker offers Create for \(query), which the task pickers refuse")
            }
        }
        #expect(TagSupport.pickerQuery("wor", in: tags).createName != nil, "non-vacuity: a partial match is creatable")
        #expect(TagSupport.pickerQuery("old project", in: tags).createName == nil, "non-vacuity: an archived slug is not")
    }

    @Test func anArchivedMatchIsNamedInsteadOfCreatingASecondRow() throws {
        let (_, tags) = try makeTags()
        let decision = TagSupport.pickerQuery("old project", in: tags)
        #expect(decision.archivedMatch?.slug == "old-project")
        #expect(decision.createName == nil, "a Create row would mint a duplicate of the archived slug")
        #expect(decision.matches.isEmpty)
        #expect(decision.placeholder == .none, "the Unarchive row is the picker's row, not No matching tags")
    }

    /// [[T-12772]]: the popover's `+`, Return and dismiss-add read this. An archived name is
    /// un-archived (keeper decision, [[T-12780]]) rather than resolved through `committedTag`,
    /// which would attach it still archived; any other usable name is resolved as before.
    @Test func theFieldUnarchivesAnArchivedNameRatherThanResolvingIt() throws {
        let (_, tags) = try makeTags()
        for query in ["old project", "  #Old Project ", "OLD-PROJECT"] {
            guard case let .unarchive(tag) = TagSupport.pickerFieldCommit(query, in: tags) else {
                Issue.record("\(query) resolved an archived tag instead of un-archiving it")
                continue
            }
            #expect(tag.slug == "old-project")
            #expect(tag.isArchived, "the decision itself writes nothing")
        }
        guard case let .resolve(existing) = TagSupport.pickerFieldCommit(" deep work ", in: tags) else {
            Issue.record("an active name must resolve"); return
        }
        #expect(existing == "deep work")
        guard case let .resolve(fresh) = TagSupport.pickerFieldCommit("Garden", in: tags) else {
            Issue.record("a new name must resolve"); return
        }
        #expect(fresh == "Garden")
        for blank in ["", "   ", "#"] {
            guard case .nothing = TagSupport.pickerFieldCommit(blank, in: tags) else {
                Issue.record("\(blank) must do nothing"); continue
            }
        }
    }

    /// **[[T-13501]].** A name `creationDecision` calls unusable (non-empty, no letter or digit)
    /// draws `No matching tags` and no Create row; the field must not mint it either. The iOS `+`,
    /// Return and dismiss-add all go through `pickerFieldCommit`, so `.nothing` here is the refusal.
    @Test func theFieldRefusesANameTheListWillNotOfferToCreate() throws {
        let (_, tags) = try makeTags()
        for unusable in ["--", "...", " -_- ", "#!"] {
            let query = TagSupport.pickerQuery(unusable, in: tags)
            #expect(query.createName == nil, "non-vacuity: the list offers Create for \(unusable)")
            #expect(query.archivedMatch == nil)
            let commit = TagSupport.pickerFieldCommit(unusable, in: tags)
            guard case .nothing = commit else {
                Issue.record("\(unusable) would be minted by the field the list refuses: \(commit)")
                continue
            }
            #expect(!commit.commits, "the footer + stays enabled for \(unusable)")
        }
        // The refusal is the unusable name alone: a usable new name still commits.
        #expect(TagSupport.pickerFieldCommit("a-b", in: tags).commits)
        // An archived `tag` is still offered for `--` (slug fallback), so the field un-archives it.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let archivedTag = Cadence.Tag(name: "Tag", slug: "tag")
        archivedTag.isArchived = true
        context.insert(archivedTag)
        guard case let .unarchive(restored) = TagSupport.pickerFieldCommit("--", in: [archivedTag]) else {
            Issue.record("an archived `tag` must still be un-archived for --"); return
        }
        #expect(restored.slug == "tag")
    }

    /// [[T-13501]]: the iOS footer `+` is enabled by the field's commit decision, not by a bare
    /// non-empty test, so it cannot be live for a name the field refuses.
    @Test func theIOSFooterPlusIsGatedByTheFieldCommitDecision() throws {
        let file = CadenceSourceScan.codeOnly(CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        ))
        let popover = try #require(
            CadenceSourceScan.declarationBody("struct iOSTaskTagPickerPopover: View", in: file)
        )
        #expect(popover.contains("TagSupport.pickerFieldCommit(newTagName, in: allTags).commits"))
        #expect(popover.contains(".disabled(!fieldCommits)"))
        #expect(CadenceSourceScan.matchCount(#"\.disabled\(trimmedNewTagName\.isEmpty\)"#, in: popover) == 0)
    }

    @Test func aQueryThatReachesNothingSaysNoMatchesAndAnEmptyCatalogueOffersTheDefaults() throws {
        let (_, tags) = try makeTags()
        #expect(TagSupport.pickerQuery("#", in: tags).placeholder == .noMatches)

        let archivedOnly = tags.filter(\.isArchived)
        #expect(TagSupport.pickerQuery("", in: archivedOnly).placeholder == .offerDefaultTags)
        #expect(TagSupport.pickerQuery("", in: []).placeholder == .offerDefaultTags)
        // Something typed on an empty catalogue gets the Create row, not the offer beside it.
        #expect(TagSupport.pickerQuery("Garden", in: []).placeholder == .none)
    }

    // MARK: - [[T-13963]]: the capture card's `#` strip

    /// The strip offered `Create “old project”` for an archived tag's name, because it compared the
    /// query only against its own (archived-free) matches; the create then resolved the slug to the
    /// archived row and attached it, still archived. It now asks `creationDecision`, as every other
    /// tag entry point does: an archived name is an Unarchive offer, never a Create.
    @Test func theCaptureStripOffersUnarchiveNotCreateForAnArchivedName() throws {
        let (_, tags) = try makeTags()
        let old = try #require(tags.first { $0.isArchived })
        for query in ["old project", "Old Project", "old-project", "#old-project"] {
            #expect(!CadenceTaskComposerSupport.canCreateSuggestedTag(query: query, allTags: tags), "\(query)")
            #expect(CadenceTaskComposerSupport.archivedSuggestedTag(query: query, allTags: tags)?.id == old.id, "\(query)")
            #expect(CadenceTaskComposerSupport.tagSuggestions(from: tags, query: query).isEmpty, "an archived tag is never a chip")
            // The Unarchive chip is a row, so the strip does not also say nothing matched.
            #expect(CadenceTaskComposerSupport.tagSuggestionPlaceholder(allTags: tags, query: query) == .none)
        }
        // A new name still creates, and is not mistaken for an archived one.
        #expect(CadenceTaskComposerSupport.canCreateSuggestedTag(query: "Wor", allTags: tags))
        #expect(CadenceTaskComposerSupport.archivedSuggestedTag(query: "Wor", allTags: tags) == nil)
        #expect(CadenceTaskComposerSupport.archivedSuggestedTag(query: "  ", allTags: tags) == nil)
    }

    /// The comparison is by slug, not drawn name: `day-job` against an existing `Day Job` used to
    /// read as Create (and the create resolved straight back to `Day Job`). Now the slug finds the
    /// chip to pick, and no Create is drawn beside it. A query with no letter or digit has no slug
    /// of its own and neither matches by slug nor creates.
    @Test func theCaptureStripComparesTheQueryBySlug() throws {
        let (container, tags) = try makeTags()
        let dayJob = Cadence.Tag(name: "Day Job", slug: "day-job")
        ModelContext(container).insert(dayJob)
        let all = tags + [dayJob]

        #expect(!CadenceTaskComposerSupport.canCreateSuggestedTag(query: "day-job", allTags: all))
        #expect(CadenceTaskComposerSupport.tagSuggestions(from: all, query: "day-job").map(\.slug) == ["day-job"])
        #expect(CadenceTaskComposerSupport.tagSuggestions(from: all, query: "day-j").map(\.slug) == ["day-job"])
        // The drawn-name prefix still works on its own.
        #expect(Set(CadenceTaskComposerSupport.tagSuggestions(from: all, query: "Wo").map(\.slug)) == ["work"])

        #expect(!CadenceTaskComposerSupport.canCreateSuggestedTag(query: "--", allTags: all))
        #expect(CadenceTaskComposerSupport.tagSuggestions(from: all, query: "--").isEmpty)
    }

    /// What the Unarchive chip runs: the tag is un-archived **in the store** (read back through a
    /// second context), and a refused commit puts both fields back and answers `false`, so the
    /// sheet keeps the `#` query and says so instead of selecting a tag the store still hides.
    @MainActor
    @Test func theStripsUnarchiveCommitsAndARefusalUndoes() throws {
        struct CommitRefused: Error {}
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tag = Cadence.Tag(name: "Old Project", slug: "old-project")
        tag.isArchived = true
        context.insert(tag)
        try context.save()
        let archivedAt = tag.updatedAt

        #expect(!TagSupport.committedUnarchive(tag, in: context, commit: { _ in throw CommitRefused() }))
        #expect(tag.isArchived)
        #expect(tag.updatedAt == archivedAt)

        #expect(TagSupport.committedUnarchive(tag, in: context))
        #expect(!context.hasChanges)
        let stored = try ModelContext(container).fetch(FetchDescriptor<Cadence.Tag>())
        #expect(stored.count == 1)
        #expect(stored.first?.isArchived == false)
    }

    /// Both capture sheets hand the strip an Unarchive action that commits through the shared
    /// helper; the strip draws it in place of Create. Source shape, because the sheets are views.
    @Test func bothCaptureSheetsWireTheStripsUnarchiveChip() throws {
        let strip = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceTaskComposerMarkerSuggestions.swift"))
        #expect(strip.contains("CadenceTaskComposerSupport.canCreateSuggestedTag(query: shortcut.query, allTags: allTags)"))
        #expect(strip.contains("onUnarchiveTag(archivedTagMatch)"))
        for path in ["Cadence/iOS/iOSCreateTaskSheet.swift", "Cadence/macOS/Sheets/CreateTaskSheet.swift"] {
            let sheet = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(sheet.contains("onUnarchiveTag: { tag in"), "\(path)")
            #expect(sheet.contains("TagSupport.committedUnarchive(tag, in: modelContext)"), "\(path)")
        }
    }
}
