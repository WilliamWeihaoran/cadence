import Foundation
import Testing
@testable import Cadence

@MainActor
struct MarkdownPreviewParserTests {
    @Test func parsesRichMarkdownBlocksInDisplayOrder() throws {
        let imageID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let taskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let markdown = """
        # Today

        Plan the day across two lines
        and keep the paragraph together.

        - Capture inbox
        1. Review plan
        - [ ] Write tests
        > Keep it calm

        | Area | Status |
        | --- | --- |
        | iOS | Live |
        | Mac | Stable |

        ```swift
        let mode = "live"
        ```

        ![Diagram](cadence-image://\(imageID.uuidString))

        [[task:\(taskID.uuidString)|Ship iOS notes]]

        ---
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks.count == 11)
        #expect(blocks[0] == .heading(level: 1, text: "Today"))
        #expect(blocks[1] == .paragraph("Plan the day across two lines and keep the paragraph together."))
        #expect(blocks[2] == .bullet(depth: 0, text: "Capture inbox"))
        #expect(blocks[3] == .ordered(depth: 0, number: "1.", text: "Review plan"))
        #expect(blocks[4] == .checklist(depth: 0, isDone: false, text: "Write tests", lineIndex: 7))
        #expect(blocks[5] == .quote(depth: 1, text: "Keep it calm"))

        guard case .table(let table) = blocks[6] else {
            Issue.record("Expected a table block")
            return
        }
        #expect(table.headers == ["Area", "Status"])
        #expect(table.rows == [["iOS", "Live"], ["Mac", "Stable"]])

        #expect(blocks[7] == .code(language: "swift", text: #"let mode = "live""#))

        guard case .image(let image) = blocks[8] else {
            Issue.record("Expected an image block")
            return
        }
        #expect(image.id == imageID)
        #expect(image.altText == "Diagram")

        guard case .taskEmbed(let task) = blocks[9] else {
            Issue.record("Expected a task embed block")
            return
        }
        #expect(task.id == taskID)
        #expect(task.title == "Ship iOS notes")

        #expect(blocks[10] == .divider)
    }

    @Test func skipsFrontmatterButKeepsTheNotesOwnLineNumbering() {
        // `---` is also divider syntax and `tags: ["a"]` is a perfectly good paragraph, so an
        // unfiltered parse rendered a tagged note as rule / prose / rule above its first heading.
        // The `lineIndex` a checklist carries is handed back to toggle that line in the *original*
        // note, so skipping the block must not renumber anything after it.
        let markdown = """
        ---
        tags: ["a"]
        ---

        # Title

        - [ ] Write tests
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .checklist(depth: 0, isDone: false, text: "Write tests", lineIndex: 6)
        ])
    }

    @Test func stillRendersADividerPairThatIsNotFrontmatter() {
        // The parser must not swallow content just because a note opens with a rule.
        let markdown = """
        ---
        A thought worth keeping.
        ---

        After
        """

        #expect(MarkdownPreviewParser.blocks(in: markdown) == [
            .divider,
            .paragraph("A thought worth keeping."),
            .divider,
            .paragraph("After")
        ])
    }

    @Test func keepsUnclosedCodeFenceAsCodeBlock() {
        let markdown = """
        Before

        ```json
        {"live": true}
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks.count == 2)
        #expect(blocks[0] == .paragraph("Before"))
        #expect(blocks[1] == .code(language: "json", text: #"{"live": true}"#))
    }

    @Test func treatsNonClosingFenceLinesInsideCodeAsCodeContent() {
        let markdown = """
        ```text
        ```swift
        still code
        ```
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks == [
            .code(language: "text", text: "```swift\nstill code")
        ])
    }

    @Test func ignoresInlineImagesAsStandaloneImageBlocks() throws {
        let imageID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let blocks = MarkdownPreviewParser.blocks(in: "Inline ![Sketch](cadence-image://\(imageID.uuidString)) stays text")

        #expect(blocks == [.paragraph("Inline ![Sketch](cadence-image://\(imageID.uuidString)) stays text")])
    }

    @Test func parsesIOSNativeListMarkers() {
        let markdown = """
        • Capture inbox
        ○ Draft note
        ✓ Review note
        ● Archive reference
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks.count == 4)
        #expect(blocks[0] == .bullet(depth: 0, text: "Capture inbox"))
        #expect(blocks[1] == .checklist(depth: 0, isDone: false, text: "Draft note", lineIndex: 1))
        #expect(blocks[2] == .checklist(depth: 0, isDone: true, text: "Review note", lineIndex: 2))
        #expect(blocks[3] == .checklist(depth: 0, isDone: true, text: "Archive reference", lineIndex: 3))
    }

    @Test func parsesNestedQuoteMarkersLikeLiveEditor() {
        let markdown = """
        > First level
        >> Nested level
        >   Trimmed spacing
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks == [
            .quote(depth: 1, text: "First level"),
            .quote(depth: 2, text: "Nested level"),
            .quote(depth: 1, text: "Trimmed spacing")
        ])
    }

    @Test func parsesIndentedQuotesWithSharedQuoteRules() {
        let markdown = """
            > Project note
            >> Nested note
        Score 3 > 2
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks == [
            .quote(depth: 1, text: "Project note"),
            .quote(depth: 2, text: "Nested note"),
            .paragraph("Score 3 > 2")
        ])
    }

    @Test func parsesNestedListDepthLikeLiveEditor() {
        let markdown = """
        • Root
            • Nested bullet
            ○ Nested todo
            2. Nested ordered
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks == [
            .bullet(depth: 0, text: "Root"),
            .bullet(depth: 1, text: "Nested bullet"),
            .checklist(depth: 1, isDone: false, text: "Nested todo", lineIndex: 2),
            .ordered(depth: 1, number: "2.", text: "Nested ordered")
        ])
    }

    @Test func usesSharedBlockRulesForHeadingsAndDividers() {
        let markdown = """
        ### Shared Heading

        * * *
        """

        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        #expect(blocks == [
            .heading(level: 3, text: "Shared Heading"),
            .divider
        ])
    }
}
