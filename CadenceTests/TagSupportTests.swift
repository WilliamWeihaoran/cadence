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

        let resolved = TagSupport.resolveTags(named: ["bug", "docs"], in: context)

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
}
