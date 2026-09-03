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
}
