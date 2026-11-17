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

    /// [[T-17935]]: the iOS dismiss-add ([[T-5175]]) commits only a query that drew no active row.
    /// `wor` narrows the list to `Work` and `Homework`, so dismissing it creates nothing -- while the
    /// `+` would still mint `wor`, which is what the dismiss used to do.
    @Test func dismissingCommitsOnlyAQueryThatMatchedNoRow() throws {
        let (_, tags) = try makeTags()
        for partial in ["wor", "WORK", "Deep", " errand "] {
            #expect(!TagSupport.pickerQuery(partial, in: tags).matches.isEmpty, "non-vacuity: \(partial)")
            #expect(TagSupport.pickerFieldCommit(partial, in: tags).commits, "non-vacuity: \(partial)")
            #expect(
                !TagSupport.pickerDismissCommits(partial, in: tags),
                "dismissing a search for \(partial) creates or attaches it (T-17935)"
            )
        }
        // A name that matches nothing is still the user's work (owner option (a), T-5175), and an
        // archived exact name -- never a row -- still un-archives through the field.
        #expect(TagSupport.pickerDismissCommits("Garden", in: tags))
        #expect(TagSupport.pickerDismissCommits("Old Project", in: tags))
        // Nothing the `+` refuses is committed on dismiss either.
        for refused in ["", "  ", "--"] {
            #expect(!TagSupport.pickerDismissCommits(refused, in: tags))
        }
        #expect(!TagSupport.pickerDismissCommits("", in: []), "an empty store and an empty field")
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

#if os(macOS)
/// **[[T-16583]] — the Mac title field's `#` panel offers Unarchive for an archived tag's name.**
///
/// The panel a board column's inline composer opens (`TaskTitleEntryField` +
/// `TaskTitleInlineTagPicker`) spelled its own filter and Create rule and had no archived match, so
/// typing an archived tag's name drew `No matching tags` and Return did nothing -- the one tag
/// picker left that could not bring an archived tag back ([[T-12744]], [[T-13963]]).
struct TaskTitleInlineTagUnarchiveTests {

    private func makeTags() throws -> (ModelContainer, [Cadence.Tag]) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let work = Cadence.Tag(name: "Work", slug: "work")
        let old = Cadence.Tag(name: "Old Project", slug: "old-project")
        old.isArchived = true
        let tags = [work, old]
        for tag in tags { context.insert(tag) }
        return (container, tags)
    }

    private func submit(_ query: String, highlight: Int = 0, offersUnarchive: Bool = true, in tags: [Cadence.Tag]) -> TaskTitleInlineTagSubmit {
        let decision = TagSupport.pickerQuery(query, in: tags)
        return TaskTitleInlineTagSubmit.action(
            highlightIndex: highlight,
            matches: decision.matches,
            canCreate: decision.canCreate,
            archivedMatch: offersUnarchive ? decision.archivedMatch : nil
        )
    }

    @Test func returnOnAnArchivedTagsNameUnarchivesIt() throws {
        let (_, tags) = try makeTags()
        for query in ["Old Project", "old project", "#old-project"] {
            guard case .unarchive(let tag) = submit(query, in: tags) else {
                Issue.record("Return on \(query) does not unarchive")
                continue
            }
            #expect(tag.slug == "old-project")
        }
        // The panel draws exactly one row for it, where it used to draw none.
        #expect(TaskTitleInlineTagSubmit.optionCount(matchCount: 0, canCreate: false, offersUnarchive: true) == 1)
    }

    @Test func activeMatchesAndCreateKeepTheirRows() throws {
        let (_, tags) = try makeTags()
        guard case .select(let tag) = submit("wor", in: tags) else {
            Issue.record("an active match is not selected")
            return
        }
        #expect(tag.slug == "work")
        // Past the match, the trailing row is Create for a new name.
        guard case .create = submit("wor", highlight: 1, in: tags) else {
            Issue.record("the Create row is not reached")
            return
        }
        guard case .nothing = submit("--", in: tags) else {
            Issue.record("an unusable name does something")
            return
        }
    }

    @Test func aHostWithNoUnarchiveOffersNothingForTheArchivedName() throws {
        let (_, tags) = try makeTags()
        guard case .nothing = submit("Old Project", offersUnarchive: false, in: tags) else {
            Issue.record("no unarchive host, yet Return acted")
            return
        }
        #expect(TaskTitleInlineTagSubmit.optionCount(matchCount: 0, canCreate: false, offersUnarchive: false) == 0)
    }

    /// Source shape: the field, the panel and the composer are views.
    @Test func theFieldThePanelAndTheBoardComposerWireTheUnarchiveRow() throws {
        let field = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskTitleEntryField.swift"))
        #expect(field.contains("TagSupport.pickerQuery(tagSearchQuery, in: allTags)"))
        #expect(field.contains("onUnarchiveTag == nil ? nil : tagQuery.archivedMatch"))
        #expect(field.contains("archivedMatch: archivedInlineTagMatch,"))
        #expect(field.contains("TaskTitleInlineTagSubmit.action("))

        let panel = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskTitleInlineTagPicker.swift"))
        #expect(panel.contains("if let archivedMatch {"))
        #expect(panel.contains("canRestore: archivedMatch != nil"))
        #expect(panel.contains("CadenceListVocabularyCopy.unarchiveRowTitle(name: tag.name)"))

        let composer = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/InlineTaskComposerView.swift"))
        #expect(composer.contains("onUnarchiveTag: unarchiveTag,"))
        #expect(composer.contains("guard TagSupport.committedUnarchive(tag, in: modelContext) else {"))
    }
}

/// **[[T-16584]] -- Return in the Mac tag popover attaches an active tag's typed name**, as the
/// phone's field does through `pickerFieldCommit`'s `.resolve`. It used to do nothing.
struct MacTagPickerReturnPickTests {

    private func makeTags() throws -> (ModelContainer, [Cadence.Tag]) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let work = Cadence.Tag(name: "Work", slug: "work")
        let deepWork = Cadence.Tag(name: "Deep Work", slug: "deep-work")
        let old = Cadence.Tag(name: "Old Project", slug: "old-project")
        old.isArchived = true
        let tags = [work, deepWork, old]
        for tag in tags { context.insert(tag) }
        return (container, tags)
    }

    @Test func anActiveTagsTypedNameIsAttached() throws {
        let (_, tags) = try makeTags()
        for query in ["work", " WORK ", "#Work"] {
            let picked = try #require(TagPickerPopover.returnPick(query, in: tags, selected: []), "\(query)")
            #expect(picked.map(\.slug) == ["work"], "\(query)")
        }
        let beside = try #require(TagPickerPopover.returnPick("deep work", in: tags, selected: [tags[0]]))
        #expect(beside.map(\.slug) == ["work", "deep-work"])
    }

    @Test func anAttachedTagStaysAttached() throws {
        let (_, tags) = try makeTags()
        let picked = try #require(TagPickerPopover.returnPick("work", in: tags, selected: [tags[0]]))
        #expect(picked.map(\.slug) == ["work"], "Return on a typed name never toggles it off")
    }

    @Test func newArchivedAndPartialNamesAreNotPicked() throws {
        let (_, tags) = try makeTags()
        #expect(TagPickerPopover.returnPick("Garden", in: tags, selected: []) == nil, "a new name is Create's")
        #expect(TagPickerPopover.returnPick("Old Project", in: tags, selected: []) == nil, "an archived name is Unarchive's")
        #expect(TagPickerPopover.returnPick("wor", in: tags, selected: []) == nil, "a prefix names no tag")
        #expect(TagPickerPopover.returnPick("", in: tags, selected: []) == nil)
    }

    /// Source shape: `.onSubmit` is not callable. Unarchive first, then the pick, then Create.
    @Test func returnAsksThePickBetweenUnarchiveAndCreate() throws {
        let popover = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TagPickerPopoverViews.swift"))
        let body = try #require(CadenceSourceScan.functionBody(named: "commitQueriedField", in: popover))
        let restore = try #require(body.range(of: "restore(archived)"))
        let pick = try #require(body.range(of: "if let picked = Self.returnPick(query, in: allTags, selected: selectedTags) {"))
        let create = try #require(body.range(of: "createQueriedTagIfNeeded()"))
        #expect(restore.upperBound < pick.lowerBound)
        #expect(pick.upperBound < create.lowerBound)
        #expect(body.contains("selectedTags = picked"))
    }
}

/// **[[T-17962]] -- the Mac tag popover adds a no-match name on dismiss**, as the phone's does
/// (owner option (a), [[T-5175]]), through the one gate both ask, `TagSupport.pickerDismissCommits`.
/// It used to drop it. Driven against a real in-memory container; never the owner's store.
struct MacTagPickerDismissCommitTests {

    private func makeTags() throws -> (ModelContainer, [Cadence.Tag]) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let work = Cadence.Tag(name: "Work", slug: "work")
        let deepWork = Cadence.Tag(name: "Deep Work", slug: "deep-work")
        let old = Cadence.Tag(name: "Old Project", slug: "old-project")
        old.isArchived = true
        let tags = [work, deepWork, old]
        for tag in tags { context.insert(tag) }
        return (container, tags)
    }

    /// What the gate lets through, the Mac's Return path (`commitQueriedField`) can act on: a new
    /// name reaches the Create row's rules and an archived one the Unarchive row's, never the
    /// active-name pick, which belongs to a query that drew a row and so never commits on dismiss.
    @Test func theGateLetsThroughOnlyANameTheReturnPathCreatesOrRestores() throws {
        let (_, tags) = try makeTags()
        let decision = TagSupport.pickerQuery("Garden", in: tags)
        #expect(TagSupport.pickerDismissCommits("Garden", in: tags))
        #expect(decision.canCreate && decision.archivedMatch == nil)
        #expect(TagPickerPopover.returnPick("Garden", in: tags, selected: []) == nil)

        #expect(TagSupport.pickerDismissCommits("Old Project", in: tags))
        #expect(TagSupport.pickerQuery("Old Project", in: tags).archivedMatch?.slug == "old-project")

        for search in ["wor", "work", " WORK ", "deep"] {
            #expect(!TagSupport.pickerQuery(search, in: tags).matches.isEmpty, "non-vacuity: \(search)")
            #expect(!TagSupport.pickerDismissCommits(search, in: tags), "dismissing a search for \(search) commits it")
        }
        for refused in ["", "  ", "--", "#"] {
            #expect(!TagSupport.pickerDismissCommits(refused, in: tags), "\(refused) commits on dismiss")
        }
    }

    /// Source shape: `.onDisappear` is not callable. One dismiss handler, asking the shared gate
    /// on the popover's own `query` before the Return path runs.
    @Test func dismissingThePopoverRunsTheReturnPathBehindTheSharedGate() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TagPickerPopoverViews.swift")
        #expect(raw.count > 1_000)
        let file = CadenceSourceScan.codeOnly(CadenceSourceScan.strippingComments(raw))
        let popover = try #require(CadenceSourceScan.declarationBody("struct TagPickerPopover: View", in: file))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: popover))
        #expect(body.contains(".onDisappear(perform: commitQueriedFieldOnDismiss)"), "the Mac drops a no-match name on dismiss (T-17962)")
        #expect(CadenceSourceScan.matchCount(#"\.onDisappear"#, in: popover) == 1)
        let onDismiss = try #require(CadenceSourceScan.functionBody(named: "commitQueriedFieldOnDismiss", in: popover))
        let gated = try #require(
            onDismiss.range(
                // `codeOnly` blanks literals and their quotes, so `""` reads as two spaces here.
                of: #"guard TagSupport\.pickerDismissCommits\(query, in: allTags\) else \{\s*query = [" ]*\s*return\s*\}"#,
                options: .regularExpression
            ),
            "the dismiss no longer asks the shared gate, so a search commits (T-17935), or no longer clears a query it did not commit (T-18288)"
        )
        let committed = try #require(onDismiss.range(of: "commitQueriedField()"), "the dismiss no longer commits")
        #expect(gated.upperBound <= committed.lowerBound)
    }

    /// **[[T-18288]], the Mac twin of [[T-6471]] and [[T-5175]].** A refused commit on dismiss used
    /// to be silent for an archived name -- `restoreFailureNotice` is drawn inside the closing
    /// popover -- and the typed name died with the popover's `@State`. Now the refusal is handed to
    /// `onDismissRefusal`, which every caller with a failure line draws, and `query` is the
    /// control's state, so a refused name is back in the field on the next open.
    ///
    /// Source shape: `.onDisappear` is not callable and the popover's `@State` cannot be driven.
    /// The refusal's value is `restore(_:)`'s own, pinned by
    /// `CadenceTagAndNoteCommitSurfaceTests.theTagPickerSelectsARestoredTagOnlyOnceTheStoreTookTheUnarchive`.
    @Test func aRefusedDismissCommitIsNamedByTheCallerAndKeepsTheTypedName() throws {
        func scanned(_ path: String) throws -> String {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "non-vacuity: \(path)")
            return CadenceSourceScan.strippingComments(raw)
        }
        let file = try scanned("Cadence/macOS/Views/TagPickerPopoverViews.swift")
        let popover = try #require(CadenceSourceScan.declarationBody("struct TagPickerPopover: View", in: file))

        // The hand-off: the Return path's answer, not a re-read of the closing view's `@State`.
        let onDismiss = try #require(CadenceSourceScan.functionBody(named: "commitQueriedFieldOnDismiss", in: popover))
        #expect(
            onDismiss.range(
                of: #"if let refusal = commitQueriedField\(\) \{\s*onDismissRefusal\(refusal\)\s*\}"#,
                options: .regularExpression
            ) != nil,
            "a refusal on dismiss is no longer handed to the caller"
        )
        let commit = try #require(CadenceSourceScan.functionBody(named: "commitQueriedField", in: popover))
        #expect(commit.contains("return restore(archived)"), "the Return path drops restore's refusal")
        let restore = try #require(CadenceSourceScan.functionBody(named: "restore", in: popover))
        #expect(
            restore.range(
                of: #"catch \{\s*let refusal = CadencePendingChangePersistence\.editFailureNotice\s*restoreFailureNotice = refusal\s*return refusal\s*\}"#,
                options: .regularExpression
            ) != nil,
            "restore no longer answers the refusal it drew"
        )
        #expect(popover.contains("var onDismissRefusal: (String) -> Void = { _ in }"))

        // The typed name outlives the popover: the control owns it.
        #expect(popover.contains("@Binding var query: String"), "the field is popover state again, so a refused name is lost")
        #expect(!popover.contains("@State private var query"))
        let support = try scanned("Cadence/macOS/Views/TagPickerSupportViews.swift")
        let control = try #require(CadenceSourceScan.declarationBody("struct TagPickerControl: View", in: support))
        #expect(control.contains(#"@State private var query = """#))
        #expect(control.contains("query: $query,"), "the control no longer hands its field to the popover")
        #expect(control.contains("onDismissRefusal: onDismissRefusal"), "the control drops the popover's refusal")

        // Every caller with a failure line draws it there.
        let callers = [
            ("Cadence/macOS/Views/SchedulePanelComponents.swift", "onDismissRefusal: { tagFailureNotice = $0 }"),
            ("Cadence/macOS/Views/NoteEditorPane.swift", "onDismissRefusal: { tagFailureNotice = $0 }"),
            ("Cadence/macOS/Views/InlineTaskComposerView.swift", "onDismissRefusal: { actionError = $0 }"),
        ]
        for (path, hook) in callers {
            let source = try scanned(path)
            #expect(CadenceSourceScan.matchCount(#"TagPickerControl\("#, in: source) == 1, "\(path)")
            #expect(source.contains(hook), "\(path) no longer draws a refused dismiss commit")
        }
    }
}
#endif
