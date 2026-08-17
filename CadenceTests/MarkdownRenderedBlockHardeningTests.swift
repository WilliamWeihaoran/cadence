import Foundation
import Testing
@testable import Cadence

/// The rendered-block layer — tables, fenced code, dividers, images, task embeds — shipped three
/// days before this file with no tests at all, and every bug found in it up to now was found by a
/// person looking at a screen. These are the edges: foreign line endings, escaped pipes, mismatched
/// column counts, unterminated blocks, blocks at the first and last line, and emoji.
struct MarkdownRenderedBlockHardeningTests {

    // MARK: - One line-splitting convention

    @Test func sourceLineRangesTileTheSourceExactly() {
        // The invariant every styler depends on: line ranges plus one separator each cover the
        // whole string. Break it and a block hides a run that starts one character off.
        for markdown in ["", "a", "a\nb", "a\n\nb\n", "\n\n", "a\r\nb", "a\u{2028}b", "🙂\n值得做"] {
            let lines = MarkdownSourceLines.lines(in: markdown)
            let nsLength = (markdown as NSString).length
            let covered = lines.reduce(0) { $0 + $1.range.length } + max(0, lines.count - 1)
            #expect(covered == nsLength, "line ranges did not tile \(markdown.debugDescription)")
            for line in lines {
                #expect((markdown as NSString).substring(with: line.range) == line.text)
            }
        }
    }

    @Test func crlfMarkdownGivesEveryParserTheSameLineNumbers() {
        // `components(separatedBy: .newlines)` counts `\r\n` as two separators and invents an empty
        // line between them. `fencedCodeBlocks` and the preview parser both used it, so on markdown
        // pasted from a browser their line indexes drifted away from the line-record tables built
        // by splitting on "\n" — and the fence stayed visible above a mis-ranged block.
        let markdown = "Intro\r\n```swift\r\nlet x = 1\r\n```\r\nAfter"

        #expect(MarkdownSourceLines.texts(in: markdown).count == 5)

        let blocks = MarkdownBlockSupport.fencedCodeBlocks(in: markdown)
        #expect(blocks.count == 1)
        #expect(blocks.first?.startLineIndex == 1)
        #expect(blocks.first?.endLineIndex == 3)
        #expect(blocks.first?.isClosed == true)
        #expect(blocks.first?.language == "swift")
    }

    @Test func crlfTableIsStillATable() {
        let markdown = "| Name | Status |\r\n| --- | --- |\r\n| Alpha | Open |"
        let styles = MarkdownTableParser.rowStyles(in: markdown)

        #expect(styles[0]?.isHeader == true)
        #expect(styles[1]?.isDelimiter == true)
        #expect(styles[2]?.columnCount == 2)
        #expect(MarkdownBlockSupport.tableCells(in: "| Alpha | Open |\r", expectedCount: 2) == ["Alpha", "Open"])
    }

    @Test func lineSeparatorCharactersDoNotRenumberRenderedBlocks() {
        // `NSString.lineRange(for:)` breaks on U+2028 as well; the deletion support numbered its
        // lines that way while the parsers feeding it did not, so a block was handed another
        // line's deletion range.
        let markdown = "a\u{2028}b\n---\ntail"
        let divider = MarkdownRenderedBlockDeletionSupport.renderedBlockRanges(in: markdown)
            .first { $0.kind == .divider }

        #expect(divider != nil)
        #expect((markdown as NSString).substring(with: divider?.storageRange ?? NSRange()) == "---")
    }

    // MARK: - Table cells

    @Test func escapedPipesStayInsideTheirCell() {
        // A raw split on `|` treats `\|` as a column break, which shifts every later cell left and
        // drops the last off the end — silently, because the row still has the right shape.
        let cells = MarkdownBlockSupport.tableCells(in: #"| a \| b | c |"#, expectedCount: 2)

        #expect(cells == ["a | b", "c"])
    }

    @Test func aTrailingEscapedPipeIsNotARowDelimiter() {
        #expect(MarkdownBlockSupport.tableRowCells(in: #"| a | b \|"#) == ["a", "b |"])
    }

    @Test func nonPipeBackslashesAreLeftAlone() {
        // `\|` is the only escape a table cell defines. A Windows path is the user's text.
        #expect(MarkdownBlockSupport.tableRowCells(in: #"| C:\Users\me | x |"#) == [#"C:\Users\me"#, "x"])
    }

    @Test func emptyCellsSurviveAtBothEnds() {
        #expect(MarkdownBlockSupport.tableRowCells(in: "|  | b |  |") == ["", "b", ""])
    }

    @Test func headerCellsAreNeverDroppedWhenTheDelimiterRowIsNarrower() {
        // The delimiter row used to decide the column count on its own, so a header with a column
        // the delimiter had not reached lost that column — a named column deleted from the render
        // of a note whose source plainly has it.
        let markdown = """
        | Name | Status | Notes |
        | --- | --- |
        | Alpha | Open | Later |
        """
        let styles = MarkdownTableParser.rowStyles(in: markdown)

        #expect(styles[0]?.columnCount == 3)
        #expect(MarkdownBlockSupport.tableCells(in: "| Name | Status | Notes |", expectedCount: 3)
            == ["Name", "Status", "Notes"])
    }

    @Test func shortBodyRowsArePaddedRatherThanRagged() {
        #expect(MarkdownBlockSupport.tableCells(in: "| only |", expectedCount: 3) == ["only", "", ""])
    }

    // MARK: - Delimiter rows and alignment

    @Test func singleDashDelimiterCellsAreLegalTables() {
        // GFM allows `|-|-|`; the old rule demanded three characters per cell and rejected it, so a
        // perfectly ordinary generated table rendered as literal pipes.
        let styles = MarkdownTableParser.rowStyles(in: "| a | b |\n|-|-|\n| 1 | 2 |")

        #expect(styles[0]?.isHeader == true)
        #expect(styles[2]?.columnCount == 2)
    }

    @Test func alignmentColonsAreParsedRatherThanDiscarded() {
        let styles = MarkdownTableParser.rowStyles(in: "| a | b | c | d |\n| :--- | ---: | :-: | --- |\n| 1 | 2 | 3 | 4 |")

        #expect(styles[0]?.alignments == [.leading, .trailing, .center, .leading])
        #expect(styles[2]?.alignments == [.leading, .trailing, .center, .leading])
    }

    @Test func columnsPastTheDelimiterRowFallBackToLeading() {
        let styles = MarkdownTableParser.rowStyles(in: "| a | b | c |\n| ---: | ---: |\n| 1 | 2 | 3 |")

        #expect(styles[0]?.alignments == [.trailing, .trailing, .leading])
    }

    @Test func aRowOfNonDelimiterCellsIsNotADelimiterRow() {
        for delimiter in ["| :: | :: |", "| abc | --- |", "|  |  |", "| -x- | --- |"] {
            #expect(MarkdownTableParser.rowStyles(in: "| a | b |\n\(delimiter)\n| 1 | 2 |").isEmpty,
                    "\(delimiter) should not open a table")
        }
    }

    @Test func proseAfterATableIsNotSwallowedAsARow() {
        let markdown = """
        | a | b |
        | --- | --- |
        | 1 | 2 |
        Ship it | maybe
        """
        let styles = MarkdownTableParser.rowStyles(in: markdown)

        #expect(styles[3] == nil)
    }

    // MARK: - Fenced code

    @Test func anUnterminatedFenceAtEndOfFileIsStillABlock() {
        let blocks = MarkdownBlockSupport.fencedCodeBlocks(in: "Before\n```json\n{\"live\": true}")

        #expect(blocks.count == 1)
        #expect(blocks.first?.isClosed == false)
        #expect(blocks.first?.startLineIndex == 1)
        #expect(blocks.first?.endLineIndex == 2)
        #expect(blocks.first?.content == "{\"live\": true}")
    }

    @Test func aFenceOnTheVeryLastLineIsAnEmptyOpenBlock() {
        let blocks = MarkdownBlockSupport.fencedCodeBlocks(in: "text\n```")

        #expect(blocks.count == 1)
        #expect(blocks.first?.isClosed == false)
        #expect(blocks.first?.content.isEmpty == true)
        #expect(blocks.first?.lineIndexes == 1...1)
    }

    @Test func aFenceOnTheVeryFirstLineIsFound() {
        let blocks = MarkdownBlockSupport.fencedCodeBlocks(in: "```\nbody\n```")

        #expect(blocks.first?.startLineIndex == 0)
        #expect(blocks.first?.language == nil)
        #expect(blocks.first?.content == "body")
    }

    @Test func aClosingFenceWithACarriageReturnStillCloses() {
        #expect(MarkdownBlockSupport.isClosingCodeFence("```\r"))
        #expect(MarkdownBlockSupport.isClosingCodeFence("  ```  "))
        #expect(!MarkdownBlockSupport.isClosingCodeFence("```swift"))
    }

    @Test func blankLinesInsideACodeBlockAreKeptAsContent() {
        let blocks = MarkdownBlockSupport.fencedCodeBlocks(in: "```\na\n\nb\n```")

        #expect(blocks.first?.content == "a\n\nb")
        #expect(blocks.first?.lineIndexes == 0...4)
    }

    // MARK: - Truncation policy

    @Test func truncationReportsWhatItCutRatherThanCuttingSilently() {
        let short = MarkdownRenderedBlockLimits.tableRowTruncation(ofTotal: 3)
        #expect(short.visibleCount == 3)
        #expect(!short.isTruncated)
        #expect(short.overflowLabel(unit: "row") == nil)

        let long = MarkdownRenderedBlockLimits.tableRowTruncation(
            ofTotal: MarkdownRenderedBlockLimits.tableRowLimit + 4
        )
        #expect(long.visibleCount == MarkdownRenderedBlockLimits.tableRowLimit)
        #expect(long.overflowLabel(unit: "row") == "+ 4 more rows")

        let one = MarkdownRenderedBlockLimits.codeLineTruncation(
            ofTotal: MarkdownRenderedBlockLimits.codeLineLimit + 1
        )
        #expect(one.overflowLabel(unit: "line") == "+ 1 more line")
    }

    @Test func truncationHandlesAnEmptyBlock() {
        let none = MarkdownRenderedBlockLimits.codeLineTruncation(ofTotal: 0)

        #expect(none.visibleCount == 0)
        #expect(!none.isTruncated)
    }

    // MARK: - Preview and canvas read the same parse

    @Test func previewTableCarriesTheAlignmentsTheParseFound() throws {
        let markdown = """
        | Item | Cost |
        | :--- | ---: |
        | Rope | 12 |
        """
        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        guard case .table(let table) = try #require(blocks.first) else {
            Issue.record("Expected a table block")
            return
        }
        #expect(table.headers == ["Item", "Cost"])
        #expect(table.rows == [["Rope", "12"]])
        #expect(table.alignments == [.leading, .trailing])
    }

    @Test func previewTableKeepsAnEscapedPipeAsText() throws {
        let markdown = """
        | Expression | Meaning |
        | --- | --- |
        | a \\| b | or |
        """
        let blocks = MarkdownPreviewParser.blocks(in: markdown)

        guard case .table(let table) = try #require(blocks.first) else {
            Issue.record("Expected a table block")
            return
        }
        #expect(table.rows == [["a | b", "or"]])
    }

    // MARK: - Rendered block ranges

    @Test func aTableAtTheEndOfTheNoteHasARangeInsideTheNote() throws {
        let markdown = "Intro\n\n| a | b |\n| --- | --- |\n| 1 | 2 |"
        let table = try #require(
            MarkdownRenderedBlockDeletionSupport.renderedBlockRanges(in: markdown).first { $0.kind == .table }
        )

        #expect(NSMaxRange(table.storageRange) <= (markdown as NSString).length)
        #expect((markdown as NSString).substring(with: table.storageRange).hasPrefix("| a | b |"))
        #expect((markdown as NSString).substring(with: table.storageRange).hasSuffix("| 1 | 2 |"))
    }

    @Test func aDividerOnTheFirstAndLastLineIsFoundAtBothEnds() {
        let markdown = "---\nbody\n---"
        let dividers = MarkdownRenderedBlockDeletionSupport.renderedBlockRanges(in: markdown)
            .filter { $0.kind == .divider }

        #expect(dividers.map(\.storageRange) == [
            NSRange(location: 0, length: 3),
            NSRange(location: 9, length: 3)
        ])
    }

    @Test func aNoteEndingInANewlineDoesNotProduceAnOutOfBoundsRange() {
        // The line-record rebuild has to keep every range inside the string, including the empty
        // final line a trailing newline creates.
        let markdown = "---\n"
        let blocks = MarkdownRenderedBlockDeletionSupport.renderedBlockRanges(in: markdown)

        for block in blocks {
            #expect(NSMaxRange(block.storageRange) <= (markdown as NSString).length)
            #expect(NSMaxRange(block.deletionRange) <= (markdown as NSString).length)
        }
    }

    @Test func caretMovingOutOfATableLeavesItsRangeSoTheCanvasComesBack() {
        // The reveal round trip: inside the block reports the block, on the line after it reports
        // nothing, so the styler draws the canvas again.
        let markdown = "| a | b |\n| --- | --- |\n| 1 | 2 |\nafter"
        let nsMarkdown = markdown as NSString
        let insideTable = nsMarkdown.range(of: "| 1 | 2 |").location + 2
        let afterTable = nsMarkdown.range(of: "after").location

        #expect(MarkdownRenderedBlockDeletionSupport.renderedBlock(atUTF16Location: insideTable, in: markdown)?.kind == .table)
        #expect(MarkdownRenderedBlockDeletionSupport.renderedBlock(atUTF16Location: afterTable, in: markdown) == nil)
    }

    @Test func caretRoundTripIsCleanForCodeDividerImageAndTaskEmbed() throws {
        let imageID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let taskID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let markdown = """
        ```swift
        let a = 1
        ```

        ---

        ![Shot](cadence-image://\(imageID.uuidString))

        [[task:\(taskID.uuidString)|Ship it]]

        tail
        """
        let nsMarkdown = markdown as NSString

        let expectations: [(String, MarkdownRenderedBlockKind)] = [
            ("let a = 1", .code),
            ("---", .divider),
            ("![Shot]", .image),
            ("[[task:", .task)
        ]
        for (needle, kind) in expectations {
            let location = nsMarkdown.range(of: needle).location
            let block = MarkdownRenderedBlockDeletionSupport.renderedBlock(atUTF16Location: location, in: markdown)
            #expect(block?.kind == kind, "\(needle) should report \(kind)")
        }

        // Out of every block again, and the source is untouched — nothing here mutates.
        let tail = nsMarkdown.range(of: "tail").location
        #expect(MarkdownRenderedBlockDeletionSupport.renderedBlock(atUTF16Location: tail, in: markdown) == nil)
    }

    @Test func blockRangesStayInUTF16UnitsAroundEmojiAndCJK() throws {
        // Character-indexed arithmetic would land mid-surrogate here and hide the wrong run.
        let markdown = "🙂 前言\n\n| 名前 | 状態 |\n| --- | --- |\n| 値 🙂 | 開 |\n\n尾"
        let nsMarkdown = markdown as NSString
        let table = try #require(
            MarkdownRenderedBlockDeletionSupport.renderedBlockRanges(in: markdown).first { $0.kind == .table }
        )

        #expect(nsMarkdown.substring(with: table.storageRange) == "| 名前 | 状態 |\n| --- | --- |\n| 値 🙂 | 開 |")
        #expect(MarkdownBlockSupport.tableCells(in: "| 値 🙂 | 開 |", expectedCount: 2) == ["値 🙂", "開"])
    }
}
