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
}
