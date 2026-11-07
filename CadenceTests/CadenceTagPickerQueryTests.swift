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
