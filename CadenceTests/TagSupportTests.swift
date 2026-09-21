import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct TagSupportTests {
    @Test func slugNormalizationDedupesCaseAndPunctuation() throws {
        #expect(TagSupport.slug(for: " Bug Fix ") == "bug-fix")
        #expect(TagSupport.slug(for: "#Enhancement!") == "enhancement")
        #expect(TagSupport.normalizedTagNames(["Bug", "bug", "#bug", "Feature Request"]) == ["Bug", "Feature Request"])
    }

    @Test func defaultSeedIsIdempotent() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        TagSupport.seedDefaultTags(in: context)
        TagSupport.seedDefaultTags(in: context)

        let tags = try context.fetch(FetchDescriptor<Cadence.Tag>())
        #expect(tags.count == TagSupport.defaultTags.count)
        #expect(tags.map(\.slug).contains("bug"))
        #expect(tags.map(\.slug).contains("enhancement"))
    }

    @Test func duplicateExistingSlugsDoNotCrashResolution() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Cadence.Tag(name: "Bug", slug: "bug", colorHex: "#ff6b6b", order: 0))
        context.insert(Cadence.Tag(name: "Bug copy", slug: "bug", colorHex: "#7b8492", order: 1))

        let resolved = try #require(TagSupport.resolveTags(named: ["bug", "docs"], in: context))

        #expect(resolved.map(\.slug) == ["bug", "docs"])
        #expect(try context.fetch(FetchDescriptor<Cadence.Tag>()).filter { $0.slug == "bug" }.count == 2)
    }

    @Test func markdownFrontmatterWritebackPreservesBody() throws {
        let original = """
        # Heading

        Body #inline
        """

        let updated = MarkdownMetadataParser.content(original, replacingFrontmatterTags: ["bug", "docs"])
        let metadata = MarkdownMetadataParser.metadata(in: updated)

        #expect(updated.contains("# Heading"))
        #expect(updated.contains("Body #inline"))
        #expect(metadata.tags == ["bug", "docs", "inline"])
    }

    @Test func frontmatterRangeCoversTheWholeBlockAndNothingElse() throws {
        // The editor hides exactly this range, so its bounds decide where the visible note
        // begins. It must stop at the closing fence and never reach into the body.
        let content = "---\ntags: [\"a\"]\n---\n\nBody"
        let range = try #require(MarkdownMetadataParser.frontmatterRange(in: content))

        #expect(range.location == 0)
        #expect((content as NSString).substring(with: range) == "---\ntags: [\"a\"]\n---\n")
        #expect(MarkdownMetadataParser.frontmatterRange(in: "# Heading\n\nBody") == nil)
        // A fence partway down the note is a divider, not frontmatter.
        #expect(MarkdownMetadataParser.frontmatterRange(in: "Body\n\n---\ntags: [a]\n---") == nil)
    }

    @Test func aDividerPairIsNotFrontmatter() throws {
        // `---` is also the editor's horizontal rule, so "divider, prose, divider" is an ordinary
        // note, not a block. The parsed range is hidden outright, so guessing wrong here erases
        // everything the user wrote between the two rules.
        let content = "---\nA thought worth keeping.\n\nAnd another.\n---\n\nAfter"

        #expect(MarkdownMetadataParser.frontmatterRange(in: content) == nil)

        let parts = MarkdownMetadataParser.splitFrontmatter(in: content)
        #expect(parts.frontmatter.isEmpty)
        #expect(parts.body == content)
    }

    @Test func aBlockWithoutAWellFormedPropertyIsNotFrontmatter() throws {
        // The boundary of the rule: a block has to carry at least one `key: value` line. Both of
        // these are two rules the user typed, and neither holds anything Cadence reads back.
        #expect(MarkdownMetadataParser.frontmatterRange(in: "---\n---\n\nBody") == nil)
        #expect(MarkdownMetadataParser.frontmatterRange(in: "---\nDraft\n---\n\nBody") == nil)
        // A key is a bare scalar, so a prose line that merely contains a colon does not qualify.
        #expect(MarkdownMetadataParser.frontmatterRange(in: "---\nOne more thing: be kind\n---") == nil)
        // ...but a real property spelled the same way does.
        #expect(MarkdownMetadataParser.frontmatterRange(in: "---\nstatus: active\n---") != nil)
    }

    @Test func frontmatterCoversOnlyItsOwnBlockWhenTheBodyHasDividers() throws {
        let content = "---\ntags: [\"a\"]\n---\n\nIntro\n\n---\n\nOutro"
        let range = try #require(MarkdownMetadataParser.frontmatterRange(in: content))

        #expect((content as NSString).substring(with: range) == "---\ntags: [\"a\"]\n---\n")
        #expect(MarkdownMetadataParser.metadata(in: content).tags == ["a"])
    }

    @Test func multiLineYAMLValuesStillParse() throws {
        // Blocks written by other markdown tools indent their list values instead of inlining them.
        let content = "---\ntags:\n  - a\n  - b\nstatus: active\n---\n\nBody"
        let range = try #require(MarkdownMetadataParser.frontmatterRange(in: content))

        #expect((content as NSString).substring(with: range) == "---\ntags:\n  - a\n  - b\nstatus: active\n---\n")
        #expect(MarkdownMetadataParser.metadata(in: content).frontmatter.properties["status"] == "active")
    }

    @Test func hiddenFrontmatterRangeSwallowsTheBlankLinesBelowTheBlock() throws {
        // What both editors actually suppress. macOS spelled this out inline and iOS suppressed
        // nothing; hiding the block to two different extents would put the caret in two different
        // places for the same note, because the caret's first legal position is this range's end.
        let content = "---\ntags: [\"a\"]\n---\n\n\n# Title\n\nBody"
        let range = try #require(MarkdownMetadataParser.hiddenFrontmatterRange(in: content))

        #expect(range.location == 0)
        #expect((content as NSString).substring(with: range) == "---\ntags: [\"a\"]\n---\n\n\n")
        // The first visible character is the body's, not a blank row above it.
        #expect((content as NSString).substring(from: NSMaxRange(range)).hasPrefix("# Title"))

        // No block, nothing hidden — and a divider pair is still not a block.
        #expect(MarkdownMetadataParser.hiddenFrontmatterRange(in: "# Title\n\nBody") == nil)
        #expect(MarkdownMetadataParser.hiddenFrontmatterRange(in: "---\nDraft\n---\n\nBody") == nil)
    }

    /// Both of a block's fences are also divider lines, so both stylers have already turned them
    /// into horizontal rules by the time the frontmatter pass runs — and the pass then collapses
    /// their line boxes to nothing, which drops those rules on top of the note's first visible
    /// line. The hidden range is what a styler has to strip its rule decoration over, so this pins
    /// that the range really does contain both fences.
    @Test func hiddenFrontmatterRangeCoversBothFencesWhichAreAlsoDividerLines() throws {
        let content = "---\ntags: [\"review\"]\n---\n\nZ# Heading\n\nBody."
        let range = try #require(MarkdownMetadataParser.hiddenFrontmatterRange(in: content))
        let hidden = (content as NSString).substring(with: range)

        let fences = hidden.components(separatedBy: "\n").filter(MarkdownBlockSupport.isDividerLine)
        #expect(fences.count == 2)
        #expect((content as NSString).substring(from: NSMaxRange(range)).hasPrefix("Z# Heading"))
    }

    @Test func frontmatterLineCountMatchesTheLinesTheBlockOccupies() throws {
        // The preview parser skips this many lines rather than parsing a stripped string, so that
        // the `lineIndex` it hands back still addresses the original note.
        #expect(MarkdownMetadataParser.frontmatterLineCount(in: "---\ntags: [\"a\"]\n---\n\nBody") == 3)
        // A block that runs to the end of the note carries no trailing newline and still occupies
        // three lines — the off-by-one a newline count alone would get wrong.
        #expect(MarkdownMetadataParser.frontmatterLineCount(in: "---\ntags: [\"a\"]\n---") == 3)
        #expect(MarkdownMetadataParser.frontmatterLineCount(in: "---\ntags:\n  - a\n  - b\n---\n\nBody") == 5)
        #expect(MarkdownMetadataParser.frontmatterLineCount(in: "Body only") == 0)
        #expect(MarkdownMetadataParser.frontmatterLineCount(in: "---\nA thought.\n---\n\nAfter") == 0)
    }

    @Test func splittingAndReassemblingANotePreservesItsFrontmatter() throws {
        // Applying a template rewrites the note wholesale. Because the block is invisible in the
        // editor, doing that without splitting it off first would silently drop the note's tags.
        let content = "---\ntags: [\"a\"]\n---\n\nOld body"
        let parts = MarkdownMetadataParser.splitFrontmatter(in: content)

        #expect(parts.frontmatter == "---\ntags: [\"a\"]\n---\n")
        #expect(parts.body == "\nOld body")

        let rebuilt = MarkdownMetadataParser.content(frontmatter: parts.frontmatter, body: "New body")
        #expect(rebuilt == "---\ntags: [\"a\"]\n---\n\nNew body")
        #expect(MarkdownMetadataParser.metadata(in: rebuilt).tags == ["a"])

        let plain = MarkdownMetadataParser.splitFrontmatter(in: "Just a body")
        #expect(plain.frontmatter.isEmpty)
        #expect(MarkdownMetadataParser.content(frontmatter: plain.frontmatter, body: "New") == "New")
    }

    @Test func standaloneInlineTagsDoNotGetMistakenForHeadings() throws {
        let content = """
        # Heading
        #bug

        ## Details
        #enhancement note
        """

        let metadata = MarkdownMetadataParser.metadata(in: content)

        #expect(metadata.tags == ["bug", "enhancement"])
    }

    @Test func urlFragmentsAndCodeSpansDoNotBecomeTags() throws {
        // Tag sync runs unattended at launch and *inserts* whatever it finds, so anything it
        // mistakes for a tag becomes a row the user never created.
        let content = """
        See [Docs](https://example.com/#quickstart) and [Anchor](#top).

        Set `background: #ff6b6b` in the theme, or read <https://example.com/#anchor>.

        Real #followup here.
        """

        #expect(MarkdownMetadataParser.metadata(in: content).tags == ["followup"])
    }

    @Test func rawHTMLAttributesDoNotBecomeTags() throws {
        // An autolink has no spaces; a real HTML tag does, so `<a href="#quickstart">` slipped
        // past the mask and invented a "quickstart" tag at the next launch.
        let content = """
        <a href="#quickstart">Quick start</a> and <img src="x.png" alt="#hero">.

        Prose stays prose: a < b, 1<2, and 3 <4> 5.

        See `code` #realtag.
        """

        #expect(MarkdownMetadataParser.metadata(in: content).tags == ["realtag"])
    }

    @Test func noteMarkdownSyncCreatesTagsAndAssignments() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let note = Note(kind: .daily, title: "Today", content: """
        ---
        tags: [bug]
        ---

        Follow up on #docs
        """)
        context.insert(note)

        TagSupport.syncNoteTagsFromMarkdown(note, in: context)
        try context.save()

        #expect(note.sortedTags.map(\.slug) == ["bug", "docs"])
        #expect(try context.fetch(FetchDescriptor<Cadence.Tag>()).map(\.slug).sorted() == ["bug", "docs"])
    }

    @Test func tagSyncAndWritebackSurviveDividersInTheBody() throws {
        // The block still parses when the body below it uses horizontal rules, and a tag edit
        // rewrites that block rather than prepending a second one above it.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let note = Note(kind: .daily, title: "Today", content: "---\ntags: [bug]\n---\n\nIntro\n\n---\n\nOutro")
        context.insert(note)

        TagSupport.syncNoteTagsFromMarkdown(note, in: context)
        #expect(note.sortedTags.map(\.slug) == ["bug"])

        TagSupport.setTags(named: ["docs"], on: note, in: context, writeFrontmatter: true)

        #expect(note.content == "---\ntags: [\"docs\"]\n---\n\nIntro\n\n---\n\nOutro")
        #expect(note.sortedTags.map(\.slug) == ["docs"])
    }

    @Test func tagWritebackOnADividerNoteAddsABlockInsteadOfRewritingTheDividers() throws {
        // The counterpart: a note that merely *starts* with a rule has no block to update, so the
        // writeback prepends one and leaves every line the user wrote untouched.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let body = "---\nA thought worth keeping.\n---\n\nAfter"
        let note = Note(kind: .daily, title: "Today", content: body)
        context.insert(note)

        TagSupport.setTags(named: ["docs"], on: note, in: context, writeFrontmatter: true)

        #expect(note.content == "---\ntags: [\"docs\"]\n---\n\n" + body)
        #expect(MarkdownMetadataParser.splitFrontmatter(in: note.content).body == "\n" + body)
    }

    // MARK: - Ordering determinism (T-160)

    /// `order` + name-ignoring-case was the whole of the old comparator, so tags that tie on both
    /// came out in whatever order the input happened to be in. Both real inputs are
    /// `Array(someDictionary.values)`, whose order is unspecified and seeded per process.
    private func tiedTag(_ idPrefix: String, name: String, slug: String) -> Cadence.Tag {
        Cadence.Tag(
            id: UUID(uuidString: "\(idPrefix)-0000-0000-0000-000000000000")!,
            name: name,
            slug: slug,
            order: 0
        )
    }

    @Test func tiedTagsSortIdenticallyFromAnyInputOrder() throws {
        // Same `order`, names equal under `localizedCaseInsensitiveCompare`, distinct stored
        // slugs so nothing is deduped away. Only the final tie-break can order these.
        let a = tiedTag("AAAAAAAA", name: "Bug", slug: "bug-a")
        let b = tiedTag("BBBBBBBB", name: "bug", slug: "bug-b")
        let c = tiedTag("CCCCCCCC", name: "BUG", slug: "bug-c")

        let expected = ["bug-a", "bug-b", "bug-c"]
        #expect(TagSupport.sorted([a, b, c]).map(\.slug) == expected)
        #expect(TagSupport.sorted([c, b, a]).map(\.slug) == expected)
        #expect(TagSupport.sorted([b, a, c]).map(\.slug) == expected)
    }

    @Test func duplicateSlugWinnerDoesNotDependOnInputOrder() throws {
        // `tagsBySlug` keeps the first tag per slug in `TagSupport.sorted` order, so a tie inside
        // the comparator decides which duplicate becomes the canonical tag for that slug — the
        // one the `#` picker offers and the one Settings counts.
        let a = tiedTag("AAAAAAAA", name: "Bug", slug: "bug")
        let b = tiedTag("BBBBBBBB", name: "bug", slug: "bug")
        let c = tiedTag("CCCCCCCC", name: "BUG", slug: "bug")

        for permutation in [[a, b, c], [c, b, a], [b, a, c], [c, a, b]] {
            #expect(TagSupport.uniqueBySlug(permutation).map(\.id) == [a.id])
        }
    }

    @Test func tagPickerOffersTheSameEightTagsEveryTime() throws {
        // `TagPickerSupportViews` shows `uniqueBySlug(...).prefix(8)`. `uniqueBySlug` sorts
        // `Array(tagsBySlug(tags).values)`, so without a total comparator *which eight tags are
        // offered* is decided by dictionary order — different on every launch of the same store.
        let hexDigits = "0123456789"
        let tags = hexDigits.map { digit in
            tiedTag(String(repeating: String(digit), count: 8), name: "Bug", slug: "bug-\(digit)")
        }

        let offered = Array(TagSupport.uniqueBySlug(tags).prefix(8)).map(\.slug)

        #expect(offered == (0..<8).map { "bug-\($0)" })
        #expect(Array(TagSupport.uniqueBySlug(tags.reversed().map { $0 }).prefix(8)).map(\.slug) == offered)
    }

    @Test func taskSortedTagsDoesNotDependOnRelationshipOrder() throws {
        // The call site, not the helper: `AppTask.sortedTags` is what task rows and the inspector
        // render. A stored to-many relationship has no promised order, so this has to hold for
        // any order SwiftData hands back.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let a = tiedTag("AAAAAAAA", name: "Bug", slug: "bug-a")
        let b = tiedTag("BBBBBBBB", name: "bug", slug: "bug-b")
        let c = tiedTag("CCCCCCCC", name: "BUG", slug: "bug-c")
        for tag in [a, b, c] { context.insert(tag) }
        let task = AppTask(title: "Ordering")
        context.insert(task)

        task.tags = [c, a, b]
        #expect(task.sortedTags.map(\.slug) == ["bug-a", "bug-b", "bug-c"])

        task.tags = [b, c, a]
        #expect(task.sortedTags.map(\.slug) == ["bug-a", "bug-b", "bug-c"])
    }

    // MARK: - Duplicate merge policy (T-360)

    /// A same-slug duplicate with one explicit timestamp for both `createdAt` and `updatedAt`.
    /// Every case below runs through `deduplicateTags`, the merge's only caller.
    private func duplicateTag(
        _ idPrefix: String,
        name: String,
        desc: String = "",
        colorHex: String,
        order: Int,
        isArchived: Bool = false,
        stamp: Date
    ) -> Cadence.Tag {
        Cadence.Tag(
            id: UUID(uuidString: "\(idPrefix)-0000-0000-0000-000000000000")!,
            name: name,
            slug: "bug",
            desc: desc,
            colorHex: colorHex,
            order: order,
            isArchived: isArchived,
            createdAt: stamp,
            updatedAt: stamp
        )
    }

    @Test func duplicateMergeKeepsTheCanonicalColourAndDoesNotInheritTheDuplicatesFreshness() throws {
        // The chosen policy: canonical metadata wins, and `updatedAt` describes what the survivor
        // is actually showing. The survivor keeps its own colour, so it keeps its own stamp.
        // T-360 was the pair of rules disagreeing — `max(updatedAt)` unconditionally, next to a
        // colour copy that could not fire, so the record advertised an edit it had discarded.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(86_400)

        // Why the old colour guard was dead rather than merely conservative: `Tag.colorHex`
        // defaults to a non-empty hex, so `target.colorHex.isEmpty` is unreachable for any tag the
        // app created. Pinned so the unreachable form cannot come back.
        #expect(!Cadence.Tag(name: "Bug").colorHex.isEmpty)

        let canonical = duplicateTag(
            "AAAAAAAA", name: "Bug", desc: "Something broken.", colorHex: "#ff6b6b", order: 0, stamp: older
        )
        let newerDuplicate = duplicateTag(
            "BBBBBBBB", name: "bug", desc: "Also broken.", colorHex: "#4ecb71", order: 1, stamp: newer
        )
        context.insert(canonical)
        context.insert(newerDuplicate)

        #expect(TagSupport.deduplicateTags(in: context))

        let survivors = try context.fetch(FetchDescriptor<Cadence.Tag>())
        #expect(survivors.count == 1)
        let survivor = try #require(survivors.first)
        #expect(survivor.id == canonical.id)
        #expect(survivor.colorHex == "#ff6b6b")
        #expect(survivor.desc == "Something broken.")
        #expect(survivor.name == "Bug")
        // Oldest creation still wins; that is a correction, not a claim of freshness.
        #expect(survivor.createdAt == older)
        // The one T-360 asserts: nothing of the newer row survived, so nothing may say it did.
        #expect(survivor.updatedAt == older)
    }

    @Test func duplicateMergeStillAdoptsADescriptionTheCanonicalLacksAndEarnsThatStamp() throws {
        // The `desc` branch has the same shape as the colour one and is genuinely live, because a
        // tag really can have no description. Pinned so a later reader cannot collapse the two
        // branches into one rule in either direction. Here the canonical wins on `isArchived`,
        // which `preferredDuplicateTagSort` ranks above `desc` — otherwise the described row would
        // be the canonical one and there would be nothing to adopt.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(86_400)

        let canonical = duplicateTag(
            "AAAAAAAA", name: "Bug", colorHex: "#ff6b6b", order: 0, stamp: older
        )
        let describedDuplicate = duplicateTag(
            "BBBBBBBB",
            name: "bug",
            desc: "Something broken.",
            colorHex: "#4ecb71",
            order: 1,
            isArchived: true,
            stamp: newer
        )
        context.insert(canonical)
        context.insert(describedDuplicate)

        #expect(TagSupport.deduplicateTags(in: context))

        let survivors = try context.fetch(FetchDescriptor<Cadence.Tag>())
        #expect(survivors.count == 1)
        let survivor = try #require(survivors.first)
        #expect(survivor.id == canonical.id)
        #expect(survivor.desc == "Something broken.")
        #expect(survivor.isArchived == false)
        // Not the mirror case: the canonical already has a usable colour, so it keeps it.
        #expect(survivor.colorHex == "#ff6b6b")
        // The survivor really is showing the newer row's description, so this stamp is earned.
        #expect(survivor.updatedAt == newer)
    }

    @Test func duplicateMergeFillsAColourTheCanonicalDoesNotUsablyHave() throws {
        // "The canonical has no colour" has to mean *no usable colour*, not `isEmpty`: a row from
        // CloudKit, an import, or a legacy store can carry a string the app cannot render, and an
        // empty-string test never fires on anything the app itself wrote. When the fill does
        // happen the survivor is showing the duplicate's colour, so the stamp moves with it.
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(86_400)

        for unusable in ["not-a-colour", ""] {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let context = ModelContext(container)
            let canonical = duplicateTag(
                "AAAAAAAA", name: "Bug", desc: "Something broken.", colorHex: unusable, order: 0, stamp: older
            )
            let newerDuplicate = duplicateTag(
                "BBBBBBBB", name: "bug", desc: "Also broken.", colorHex: "#4ECB71", order: 1, stamp: newer
            )
            context.insert(canonical)
            context.insert(newerDuplicate)

            #expect(TagSupport.deduplicateTags(in: context))

            let survivors = try context.fetch(FetchDescriptor<Cadence.Tag>())
            #expect(survivors.count == 1)
            let survivor = try #require(survivors.first)
            #expect(survivor.id == canonical.id)
            #expect(survivor.colorHex == "#4ecb71")
            #expect(survivor.updatedAt == newer)
        }
    }

    // MARK: - T-653: `seedDefaultTagsCommitting`

    private struct SeedCommitRefused: Error {}

    /// **Behavioural.** The success path: `seedDefaultTagsCommitting` both seeds and commits in one
    /// call, so a second context — never the one that did the seeding — can already read every
    /// default tag.
    @Test func seedDefaultTagsCommittingSeedsAndCommitsInOneShot() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let changed = try TagSupport.seedDefaultTagsCommitting(in: context)

        #expect(changed)
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<Cadence.Tag>()).count == TagSupport.defaultTags.count,
            "the seed committed nothing a second context, and so the picker, could read"
        )
    }

    /// **Behavioural, and the reason this is `commitDelete` and not `commitInsert`.**
    /// `seedDefaultTags` runs `deduplicateTags` first, so one call can both insert new default tags
    /// and delete a duplicate merged into its canonical — a mixed cascade, not an insert-only unit
    /// of work. A refused commit must roll back both halves together, or the store is left holding
    /// a table that is half seeded and half merged, which nothing downstream asked for.
    @Test func arefusedSeedCommitRollsBackBothTheInsertAndTheMerge() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let canonical = duplicateTag("AAAAAAAA", name: "Bug", colorHex: "#ff6b6b", order: 0, stamp: stamp)
        let duplicate = duplicateTag("BBBBBBBB", name: "bug", colorHex: "#4ecb71", order: 1, stamp: stamp)
        context.insert(canonical)
        context.insert(duplicate)
        try context.save()

        #expect(throws: SeedCommitRefused.self) {
            try TagSupport.seedDefaultTagsCommitting(in: context, commit: { _ in throw SeedCommitRefused() })
        }

        // The claim this pins is "rolled back", not merely "never reached the store" — those read
        // identically from a second context, because an uncommitted insert or delete is invisible
        // across contexts whether or not it was rolled back. So the same context saves again,
        // exactly like the next unrelated screen's autosave would: without `commitDelete`'s
        // rollback, the half-merged, half-seeded cascade is still pending here and this save takes
        // it — which is the whole failure mode a mixed cascade's own commit must prevent.
        try context.save()

        let survivors = try ModelContext(container).fetch(FetchDescriptor<Cadence.Tag>())
        #expect(
            Set(survivors.map(\.id)) == Set([canonical.id, duplicate.id]),
            "the next unrelated save committed a seed the store had already refused: \(survivors.map(\.name))"
        )
    }

    // MARK: - The startup sweep reads the tag table once (T-1314)

    /// Builds a store of `notes` notes whose frontmatter cycles through `tags` tag names, on top of
    /// `existingTags` tag rows already in the table. The shape the launch path actually meets: many
    /// notes, a tag vocabulary much smaller than the note count, most tags already existing.
    private func seedTaggedNotes(
        in context: ModelContext,
        notes noteCount: Int,
        tagVocabulary: Int,
        existingTags: Int,
        tagsPerNote: Int = 3
    ) {
        for index in 0..<existingTags {
            context.insert(Cadence.Tag(name: "tag-\(index)", slug: "tag-\(index)", order: index))
        }
        for index in 0..<noteCount {
            let names = (0..<tagsPerNote).map { "tag-\((index * tagsPerNote + $0) % tagVocabulary)" }
            // Built by concatenation, not by an interpolated closure: a string literal holding
            // `\(names.map { "\"..." })` desynchronises every brace-counting source scanner in
            // this repository, and `scripts/test-suite-index.sh` then reports the tests below it
            // as `<file scope>` — which is a hygiene-test failure and an unscopeable suite.
            let frontmatter = "---\ntags: [" + names.joined(separator: ", ") + "]\n---\n\nNote \(index)"
            context.insert(Note(kind: .list, title: "Note \(index)", content: frontmatter))
        }
    }

    /// **The fetch-count gate (T-1314).** One read of the `Tag` table for the whole sweep, whatever
    /// the store holds — this is the assertion the fix exists to make true, and the one that fails
    /// if the index construction moves back inside the loop, which is what the old code was.
    ///
    /// It counts by owning the seam: `makingTagIndex` is called once per index built, so 200 notes
    /// answering 1 is the claim, and a per-note rebuild answers 200.
    @Test func theStartupSweepReadsTheWholeTagTableExactlyOnce() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        seedTaggedNotes(in: context, notes: 200, tagVocabulary: 40, existingTags: 40)

        var indexBuilds = 0
        let changed = TagSupport.syncAllNoteTagsFromMarkdown(
            in: context,
            saveChanges: false,
            makingTagIndex: { ctx in
                indexBuilds += 1
                return TagSupport.makeTagIndex(in: ctx)
            }
        )

        #expect(changed, "non-vacuity: the sweep must have had work to do for the count to mean anything")
        #expect(indexBuilds == 1, "the tag table was read \(indexBuilds) times for 200 notes")
        // And the sweep really did the work the single read was for.
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.allSatisfy { ($0.tags ?? []).count == 3 })
    }

    /// **Every note in the pass, not just the first one.** The count above proves the sweep builds
    /// one index; this proves the sweep *uses* it for every note, which is the other way the
    /// quadratic comes back — a loop body that keeps calling the single-note path with no index
    /// while the sweep's own index sits unused would still answer 1 to that counter.
    ///
    /// The lever is a snapshot the store disagrees with: an index of nothing, handed to a sweep
    /// over a store that already holds both tags. Honoured, the first note mints duplicates and the
    /// other two reuse them — four tags. Refetched anywhere underneath, the existing rows are found
    /// and nothing is minted — two tags. The two outcomes are a whole tag apart, so there is no
    /// reading of this that a per-note fetch also satisfies.
    @Test func everyNoteInTheSweepResolvesThroughTheOneIndexItWasGiven() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        context.insert(Cadence.Tag(name: "alpha", slug: "alpha", order: 0))
        context.insert(Cadence.Tag(name: "beta", slug: "beta", order: 1))
        for index in 0..<3 {
            context.insert(Note(kind: .list, title: "Note \(index)", content: "---\ntags: [alpha, beta]\n---\nBody"))
        }
        try context.save()

        let changed = TagSupport.syncAllNoteTagsFromMarkdown(
            in: context,
            saveChanges: false,
            makingTagIndex: { _ in TagSlugIndex(tags: []) }
        )

        #expect(changed)
        let tags = try context.fetch(FetchDescriptor<Cadence.Tag>())
        #expect(
            tags.count == 4,
            "expected the empty index to be honoured for all three notes; got \(tags.count) tags"
        )
        #expect(tags.filter { $0.slug == "alpha" }.count == 2)
        // All three notes ended up on the same two rows: the index carried its own mints forward.
        let noteTagIDs = try context.fetch(FetchDescriptor<Note>()).map { Set(($0.tags ?? []).map(\.id)) }
        #expect(Set(noteTagIDs).count == 1)
    }

    /// The other half of the same claim, one frame down: a `resolution` handed an index reads
    /// nothing at all.
    ///
    /// Proved by making the index deliberately stale — a tag inserted into the store *after* the
    /// index was built. A call that refetches would find that row and reuse it; a call that honours
    /// the handed index cannot see it and mints its own. The duplicate is the detector, not the
    /// intended production outcome: nothing writes tags during the sweep, which is why the sweep is
    /// allowed to hold one snapshot for its whole run.
    @Test func aHandedIndexIsTheWholeTableForThatCallSoNothingRefetchesIt() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let index = try #require(TagSupport.makeTagIndex(in: context))

        context.insert(Cadence.Tag(name: "Alpha", slug: "alpha", order: 7))
        let resolved = try #require(TagSupport.resolution(named: ["alpha"], in: context, index: index))

        #expect(resolved.inserted.count == 1, "the handed index was bypassed by a fresh fetch")
        // Without an index the same call reads the table and finds both.
        let refetched = try #require(TagSupport.resolution(named: ["alpha"], in: context))
        #expect(refetched.inserted.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Cadence.Tag>()).count == 2)
    }

    /// **Semantic equivalence, by running both implementations.** The per-note path is still
    /// production code — `resolution` with no index is what every picker calls — so the old
    /// algorithm is replayed against an identically seeded store rather than imitated here.
    ///
    /// What is compared is what the sweep is *for*: which tags exist afterwards and which tags
    /// each note carries. The `order` numbers the two runs mint are deliberately **not** compared
    /// across legs, and that is a fact about the old code rather than a concession by the new one:
    /// an unsorted `FetchDescriptor<Note>()` hands back two identically seeded stores in two
    /// different sequences — measured repeatedly here, with random ids, with fixed ids, and with
    /// the context saved first — and the numbers follow the sequence in both implementations
    /// equally. The rule that assigns them is pinned exactly, in a deterministic setting, by
    /// `aHandedIndexAssignsTheOrdersARepeatedFetchWouldHave` below.
    @Test func theSweptStoreMatchesTheOldPerNoteResolution() throws {
        func seededContext() throws -> ModelContext {
            let context = ModelContext(try CadenceTestStore.container())
            // Deliberately awkward: an existing tag with a high `order`, notes that introduce new
            // names beside already-known ones, and a note whose names are all new.
            context.insert(Cadence.Tag(name: "known", slug: "known", order: 12))
            let contents = [
                "---\ntags: [known, fresh-a]\n---\nOne",
                "---\ntags: [fresh-b, known, fresh-c]\n---\nTwo",
                "---\ntags: [fresh-d]\n---\nThree",
                "---\ntags: [fresh-a, fresh-d]\n---\nFour",
            ]
            for (index, content) in contents.enumerated() {
                context.insert(Note(kind: .list, title: "Note \(index)", content: content))
            }
            try context.save()
            return context
        }

        func fingerprint(_ context: ModelContext) throws -> (Set<String>, [String], Set<Int>) {
            let tags = try context.fetch(FetchDescriptor<Cadence.Tag>())
            let notes = try context.fetch(FetchDescriptor<Note>())
                .sorted { $0.title < $1.title }
                .map { "\($0.title)=\(TagSupport.tagSlugs($0.tags ?? []).joined(separator: ","))" }
            return (Set(tags.map(\.slug)), notes, Set(tags.map(\.order)))
        }

        let sweptContext = try seededContext()
        #expect(TagSupport.syncAllNoteTagsFromMarkdown(in: sweptContext, saveChanges: false))

        let perNoteContext = try seededContext()
        for note in try perNoteContext.fetch(FetchDescriptor<Note>()) {
            // The pre-T-1314 body, verbatim: one `resolution` per note, each one its own fetch.
            TagSupport.syncNoteTagsFromMarkdown(note, in: perNoteContext)
        }

        let swept = try fingerprint(sweptContext)
        let perNote = try fingerprint(perNoteContext)
        #expect(swept.0 == perNote.0, "tag rows diverged: \(swept.0) vs \(perNote.0)")
        #expect(swept.1 == perNote.1, "note tag sets diverged: \(swept.1) vs \(perNote.1)")
        // Non-vacuity: four new tags beside the known one, and five distinct `order` values — a
        // running counter that restarted, or an index that forgot what it minted, collides here.
        #expect(swept.0.count == 5)
        #expect(swept.2.count == 5)
        #expect(swept.2.allSatisfy { $0 >= 12 })
    }

    /// The `order` rule itself, where it *is* deterministic: the same four resolutions, in the same
    /// sequence, once through a shared index and once through a fresh fetch each time.
    ///
    /// This is the part a plausible rewrite gets wrong. `order` is the first key of
    /// `TagSupport.precedes`, and an index holding a running counter rather than the highest
    /// `order` it has seen assigns different numbers than `(max order) + 1 + offset within the
    /// call` — which is a different tag order on screen, minted by the launch sweep, for a user who
    /// arranged their tags by hand.
    @Test func aHandedIndexAssignsTheOrdersARepeatedFetchWouldHave() throws {
        let sequences = [
            ["known", "fresh-a"],
            ["fresh-b", "known", "fresh-c"],
            ["fresh-d"],
            ["fresh-a", "fresh-d"],
        ]

        func run(sharingIndex: Bool) throws -> [String] {
            let context = ModelContext(try CadenceTestStore.container())
            context.insert(Cadence.Tag(name: "known", slug: "known", order: 12))
            let index = sharingIndex ? TagSupport.makeTagIndex(in: context) : nil
            for names in sequences {
                _ = TagSupport.resolution(named: names, in: context, index: index)
            }
            return try context.fetch(FetchDescriptor<Cadence.Tag>())
                .sorted(by: TagSupport.precedes)
                .map { "\($0.slug)#\($0.order)" }
        }

        let shared = try run(sharingIndex: true)
        let refetched = try run(sharingIndex: false)
        #expect(shared == refetched, "\(shared) vs \(refetched)")
        #expect(shared.count == 5)
    }

    /// A tag table that cannot be read is still a refusal, not an empty index — the distinction
    /// T-631's predecessor lost, which re-pointed every note in the store at fresh duplicates.
    /// The sweep now asks once instead of once per note, so this is where that answer is checked.
    @Test func aTagTableThatCannotBeReadStillWritesNothing() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        seedTaggedNotes(in: context, notes: 5, tagVocabulary: 3, existingTags: 3)

        let changed = TagSupport.syncAllNoteTagsFromMarkdown(
            in: context,
            saveChanges: false,
            makingTagIndex: { _ in nil }
        )

        #expect(!changed)
        #expect(try context.fetch(FetchDescriptor<Note>()).allSatisfy { ($0.tags ?? []).isEmpty })
        #expect(try context.fetch(FetchDescriptor<Cadence.Tag>()).count == 3, "a refused read minted tags")
    }

    /// An empty store still costs exactly one fetch on the launch path — the notes fetch — and
    /// never reads the tag table at all, which is what it did before the index existed.
    @Test func aStoreWithNoNotesNeverReadsTheTagTable() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)

        var indexBuilds = 0
        let changed = TagSupport.syncAllNoteTagsFromMarkdown(
            in: context,
            saveChanges: false,
            makingTagIndex: { ctx in
                indexBuilds += 1
                return TagSupport.makeTagIndex(in: ctx)
            }
        )

        #expect(!changed)
        #expect(indexBuilds == 0)
    }
}
