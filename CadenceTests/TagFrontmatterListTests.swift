import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-17010]] and [[T-17011]]: what a note's frontmatter `tags:` line reads back as.
///
/// A tag name with a comma in it is legal everywhere a tag is made, and the writer quotes it, so
/// the reader has to honour the quotes. And a `tags:` block list (`  - a`) is how other markdown
/// tools spell the same line, so it has to read as tags and be replaced whole when Cadence rewrites.
@MainActor
struct TagFrontmatterListTests {
    @Test func aQuotedNameWithACommaReadsBackAsOneTag() {
        let written = MarkdownMetadataParser.content("Body", replacingFrontmatterTags: ["Q1, Q2", "Work"])

        #expect(MarkdownMetadataParser.frontmatterTagNames(in: written) == ["Q1, Q2", "Work"])
        #expect(MarkdownMetadataParser.metadata(in: written).tags == ["Q1, Q2", "Work"])
    }

    @Test func anUnquotedListStillSplitsOnEveryComma() {
        #expect(MarkdownMetadataParser.frontmatterTagNames(in: "---\ntags: [a, b]\n---\n\nBody") == ["a", "b"])
        // An apostrophe inside an unquoted name opens nothing.
        #expect(MarkdownMetadataParser.frontmatterTagNames(in: "---\ntags: [Bob's, Work]\n---\n\nBody") == ["Bob's", "Work"])
        #expect(MarkdownMetadataParser.frontmatterTagNames(in: "---\ntags: work, docs\n---\n\nBody") == ["work", "docs"])
    }

    /// The owner-visible half: attaching a comma-named tag and letting the sweep run left the note
    /// on two minted tags, `Q1` and `Q2`, and off the one it was given.
    @Test func theSweepKeepsANoteOnItsCommaNamedTag() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let note = Note(kind: .daily, title: "Today", content: "Body")
        context.insert(note)

        TagSupport.setTags(named: ["Q1, Q2"], on: note, in: context, writeFrontmatter: true)
        TagSupport.syncNoteTagsFromMarkdown(note, in: context)

        #expect(note.sortedTags.map(\.name) == ["Q1, Q2"])
        #expect(try context.fetch(FetchDescriptor<Cadence.Tag>()).map(\.name) == ["Q1, Q2"])
    }

    @Test func aBlockListReadsAsTags() {
        let content = "---\ntags:\n  - a\n  - \"b, c\"\nstatus: active\n---\n\nBody #inline"
        let metadata = MarkdownMetadataParser.metadata(in: content)

        #expect(MarkdownMetadataParser.frontmatterTagNames(in: content) == ["a", "b, c"])
        #expect(metadata.tags == ["a", "b, c", "inline"])
        #expect(metadata.frontmatter.properties["status"] == "active")
    }

    @Test func rewritingABlockListReplacesItsItems() throws {
        let content = "---\ntags:\n  - a\n  - b\nstatus: active\n---\n\nBody"
        let rewritten = MarkdownMetadataParser.content(content, replacingFrontmatterTags: ["x"])

        #expect(rewritten == "---\ntags: [\"x\"]\nstatus: active\n---\n\nBody")
        #expect(MarkdownMetadataParser.frontmatterTagNames(in: rewritten) == ["x"])
    }

    /// The sweep reads a block-listed note's tags rather than finding none.
    @Test func theSweepAttachesABlockListsTags() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let note = Note(kind: .daily, title: "Today", content: "---\ntags:\n  - work\n  - docs\n---\n\nBody")
        context.insert(note)

        TagSupport.syncNoteTagsFromMarkdown(note, in: context)

        #expect(Set(note.sortedTags.map(\.slug)) == ["work", "docs"])
    }
}
