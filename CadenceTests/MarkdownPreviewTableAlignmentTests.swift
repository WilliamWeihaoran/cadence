import SwiftUI
import Testing
@testable import Cadence

/// `:---:` and `---:` were parsed into `MarkdownPreviewTable.alignments` and then read by exactly
/// one surface — the live editor canvas. The read-only preview drew every cell leading, so the same
/// note showed a right-aligned numeric column right-aligned while editing and left-aligned while
/// previewing. Alignment is the one piece of table syntax with no other way to express it, so that
/// is a content difference rather than a styling one.
///
/// The mapping lives in `CadenceMarkdownPresentationSupport` rather than in the preview view
/// because the view is under `Cadence/iOS/`, inside `#if os(iOS)`, where this macOS-built target
/// cannot see it — the same reason `CadenceTodayLayoutSupport` exists.
struct MarkdownPreviewTableAlignmentTests {
    private func table(in markdown: String) throws -> MarkdownPreviewTable {
        let blocks = MarkdownPreviewParser.blocks(in: markdown)
        guard case .table(let table) = try #require(blocks.first) else {
            Issue.record("Expected a table block")
            throw TableExpectationFailure()
        }
        return table
    }

    private struct TableExpectationFailure: Error {}

    @Test func everyDelimiterSpellingReachesTheCellItDescribes() throws {
        let table = try table(in: """
        | Item | Cost | Note |
        | :--- | ---: | :--: |
        | Rope | 12 | coil |
        """)

        #expect(CadenceMarkdownPresentationSupport.tableColumnAlignment(0, in: table.alignments) == .leading)
        #expect(CadenceMarkdownPresentationSupport.tableColumnAlignment(1, in: table.alignments) == .trailing)
        #expect(CadenceMarkdownPresentationSupport.tableColumnAlignment(2, in: table.alignments) == .center)
    }

    /// The regression this closes, stated as the assertion that fails if the preview goes back to a
    /// hardcoded `.topLeading`: a right-aligned column must not resolve to a leading cell.
    @Test func aRightAlignedColumnDoesNotRenderLeading() throws {
        let table = try table(in: """
        | Item | Cost |
        | --- | ---: |
        | Rope | 12 |
        """)

        #expect(CadenceMarkdownPresentationSupport.tableCellAlignment(1, in: table.alignments) == .topTrailing)
        #expect(CadenceMarkdownPresentationSupport.tableCellAlignment(1, in: table.alignments) != .topLeading)
        #expect(CadenceMarkdownPresentationSupport.tableColumnTextAlignment(1, in: table.alignments) == .trailing)
    }

    /// A delimiter row with no colons is markdown's own "unaligned", and it must keep drawing the
    /// left-aligned table both surfaces drew before any of this existed.
    @Test func aTableWithNoColonsIsUnchanged() throws {
        let table = try table(in: """
        | Item | Cost |
        | --- | --- |
        | Rope | 12 |
        """)

        for column in 0..<2 {
            #expect(CadenceMarkdownPresentationSupport.tableColumnAlignment(column, in: table.alignments) == .leading)
            #expect(CadenceMarkdownPresentationSupport.tableCellAlignment(column, in: table.alignments) == .topLeading)
            #expect(CadenceMarkdownPresentationSupport.tableColumnTextAlignment(column, in: table.alignments) == .leading)
        }
    }

    /// The preview sizes its grid from `max(headers.count, widest row)` and the canvas defaults
    /// `alignments` to `[]` outright, so both can ask about a column the delimiter row never
    /// reached. Out of range is `.leading`, not a crash and not a wrap-around.
    @Test func aColumnPastTheDelimiterRowFallsBackToLeading() {
        let alignments: [MarkdownTableAlignment] = [.trailing]

        #expect(CadenceMarkdownPresentationSupport.tableColumnAlignment(1, in: alignments) == .leading)
        #expect(CadenceMarkdownPresentationSupport.tableColumnAlignment(99, in: alignments) == .leading)
        #expect(CadenceMarkdownPresentationSupport.tableColumnAlignment(-1, in: alignments) == .leading)
        #expect(CadenceMarkdownPresentationSupport.tableColumnAlignment(0, in: []) == .leading)
    }

    /// Only the horizontal half of a cell's alignment comes from the delimiter row. Rows stay
    /// top-anchored, or a cell that wraps to a second line would drag the single-line cells beside
    /// it down to its own centre.
    @Test func cellsStayTopAnchoredWhateverTheColumnSays() {
        let alignments: [MarkdownTableAlignment] = [.leading, .center, .trailing]
        let expected: [Alignment] = [.topLeading, .top, .topTrailing]

        for (column, alignment) in expected.enumerated() {
            let resolved = CadenceMarkdownPresentationSupport.tableCellAlignment(column, in: alignments)
            #expect(resolved == alignment)
            #expect(resolved.vertical == .top)
        }
    }
}
