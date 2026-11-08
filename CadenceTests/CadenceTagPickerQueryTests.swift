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
}
