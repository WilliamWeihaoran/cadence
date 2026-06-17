import Foundation
import Testing
@testable import Cadence

struct MarkdownBlockSupportTests {
    @Test func parsesHeadingLineInfoWithMarkerAndContentRanges() throws {
        let heading = try #require(MarkdownBlockSupport.headingLineInfo(in: "### Ship iOS notes"))

        #expect(heading.level == 3)
        #expect(heading.markerRange == NSRange(location: 0, length: 4))
        #expect(heading.contentRange == NSRange(location: 4, length: 14))
        #expect(heading.content == "Ship iOS notes")
    }

    @Test func rejectsEmptyHeadingsSoLiveEditorCanShowRawMarker() {
        #expect(MarkdownBlockSupport.headingLineInfo(in: "## ") == nil)
    }

    @Test func recognizesCommonDividerLinesWithSpacing() {
        #expect(MarkdownBlockSupport.isDividerLine("---"))
        #expect(MarkdownBlockSupport.isDividerLine("* * *"))
        #expect(MarkdownBlockSupport.isDividerLine("_ _ _"))
        #expect(!MarkdownBlockSupport.isDividerLine("--"))
        #expect(!MarkdownBlockSupport.isDividerLine("- * -"))
    }

    @Test func returnsStandaloneImageReferencesOnlyForWholeLines() throws {
        let imageID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let line = "![Diagram](cadence-image://\(imageID.uuidString))"

        let reference = try #require(MarkdownBlockSupport.standaloneImageReference(in: line))

        #expect(reference.id == imageID)
        #expect(reference.altText == "Diagram")
        #expect(MarkdownBlockSupport.standaloneImageReference(in: "Inline \(line)") == nil)
    }

    @Test func normalizesTableCellsToExpectedColumnCount() {
        #expect(MarkdownBlockSupport.tableCells(in: "| Area | Status |", expectedCount: 3) == ["Area", "Status", ""])
        #expect(MarkdownBlockSupport.tableCells(in: "Area | Status | Notes", expectedCount: 2) == ["Area", "Status"])
    }

    @Test func parsesFencedCodeBlocksWithLanguageAndLineIndexes() throws {
        let markdown = """
        Before

        ```swift
        let mode = "live"
        print(mode)
        ```

        After
        """

        let blocks = MarkdownBlockSupport.fencedCodeBlocks(in: markdown)

        #expect(blocks.count == 1)
        let block = try #require(blocks.first)
        #expect(block.startLineIndex == 2)
        #expect(block.endLineIndex == 5)
        #expect(block.language == "swift")
        #expect(block.content == "let mode = \"live\"\nprint(mode)")
        #expect(block.isClosed)
    }

    @Test func parsesPlainAndUnclosedFencedCodeBlocks() {
        let markdown = """
        ```
        no language
        ```

        ```json
        {"open": true}
        """

        let blocks = MarkdownBlockSupport.fencedCodeBlocks(in: markdown)

        #expect(blocks.count == 2)
        #expect(blocks[0].startLineIndex == 0)
        #expect(blocks[0].endLineIndex == 2)
        #expect(blocks[0].language == nil)
        #expect(blocks[0].content == "no language")
        #expect(blocks[0].isClosed)

        #expect(blocks[1].startLineIndex == 4)
        #expect(blocks[1].endLineIndex == 5)
        #expect(blocks[1].language == "json")
        #expect(blocks[1].content == #"{"open": true}"#)
        #expect(!blocks[1].isClosed)
    }
}
