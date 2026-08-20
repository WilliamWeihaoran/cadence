import Foundation
import Testing
@testable import Cadence

/// **One table walk, and the two readings of it.**
///
/// "Take the header row, then consume every following line `rowStyles` still calls a row" was
/// written out three times: in `MarkdownPreviewParser` for the read-only preview, in the iOS live
/// styler for its canvas, and in `MarkdownRenderedBlockDeletionSupport` for its deletion ranges.
/// The styler's copy also collected the line indexes it had consumed, because it has to collapse
/// them; the preview's did not. That asymmetry is how the canvas and the preview came to disagree
/// about tables the first time, which is what `MarkdownRenderedBlockLimits` was written to stop
/// recurring — a shared *number* does not help if the walk feeding it is duplicated.
///
/// T-121 moved the walk into `MarkdownTableParser.tableBlock` and pointed the first two at it. The
/// third still has its own, because it works on line *records* and never reads a cell.
struct MarkdownTableBlockTests {
    private let markdown = """
    intro
    | Item | Cost | Note |
    | :--- | ---: | :--: |
    | Rope | 12 | coil |
    | Axe | 30 | steel |
    outro
    """

    private func block(startingAt index: Int, in markdown: String) -> MarkdownTableBlock? {
        MarkdownTableParser.tableBlock(
            startingAt: index,
            lines: MarkdownSourceLines.texts(in: markdown),
            tableRows: MarkdownTableParser.rowStyles(in: markdown)
        )
    }

    @Test
    func aTableBlockReportsItsHeaderRowsAndAlignments() throws {
        let table = try #require(block(startingAt: 1, in: markdown))
        #expect(table.headers == ["Item", "Cost", "Note"])
        #expect(table.rows == [["Rope", "12", "coil"], ["Axe", "30", "steel"]])
        #expect(table.alignments == [.leading, .trailing, .center])
    }

    /// The delimiter row is consumed but is never a *row* — it is syntax, not data.
    @Test
    func theDelimiterRowIsConsumedWithoutBecomingARow() throws {
        let table = try #require(block(startingAt: 1, in: markdown))
        #expect(table.lineIndexes == [1, 2, 3, 4])
        #expect(table.rows.count == 2)
    }

    /// `nextIndex` is the first line *after* the table, which is what both callers advance to.
    @Test
    func nextIndexIsTheLineAfterTheTable() throws {
        let table = try #require(block(startingAt: 1, in: markdown))
        #expect(table.nextIndex == 5)
        #expect(MarkdownSourceLines.texts(in: markdown)[table.nextIndex] == "outro")
    }

    @Test
    func noTableStartsAtAPlainLineOrAtADelimiterRow() {
        #expect(block(startingAt: 0, in: markdown) == nil)
        #expect(block(startingAt: 2, in: markdown) == nil)
        #expect(block(startingAt: 5, in: markdown) == nil)
    }

    /// Out-of-range indexes return `nil` rather than trapping — the callers walk a cursor over
    /// lines and one of them clamps with `max(nextIndex, cursor + 1)`.
    @Test
    func anIndexPastTheEndOfTheDocumentIsNotATable() {
        #expect(block(startingAt: 99, in: markdown) == nil)
        #expect(block(startingAt: -1, in: markdown) == nil)
    }

    /// The preview reads the same walk, so its table has to agree cell for cell.
    @Test
    func thePreviewParserReportsTheSameCellsAsTheSharedWalk() throws {
        let shared = try #require(block(startingAt: 1, in: markdown))
        let blocks = MarkdownPreviewParser.blocks(in: markdown)
        let previewTable = try #require(blocks.compactMap { block -> MarkdownPreviewTable? in
            if case .table(let table) = block { return table }
            return nil
        }.first)

        #expect(previewTable.headers == shared.headers)
        #expect(previewTable.rows == shared.rows)
        #expect(previewTable.alignments == shared.alignments)
    }

    /// A header row narrower than its delimiter row keeps every cell it has and is padded, rather
    /// than being truncated or rejected — the widening rule `rowStyles` documents, reaching the
    /// cells through the shared walk.
    @Test
    func aNarrowHeaderRowIsPaddedRatherThanTruncated() throws {
        let narrow = """
        | Item | Cost |
        | - | - | - |
        | Rope | 12 | coil |
        """
        let table = try #require(block(startingAt: 0, in: narrow))
        #expect(table.headers == ["Item", "Cost", ""])
        #expect(table.rows == [["Rope", "12", "coil"]])
        #expect(table.nextIndex == 3)
    }
}
