import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Where a rendered table's cells sit. The load-bearing property is that the rect a cell is *drawn*
/// in is the rect a click is *tested* against — one `MarkdownTableLayout` answers both, and these
/// pin that it stays one.
struct MarkdownTableLayoutSupportTests {
    private let rowHeight: CGFloat = 26

    private func layout(
        widths: [[CGFloat]],
        columns: Int,
        available: CGFloat
    ) -> MarkdownTableLayout {
        MarkdownTableLayout.compute(
            intrinsicCellWidths: widths,
            columnCount: columns,
            availableWidth: available,
            rowHeight: rowHeight
        )
    }

    @Test func columnsFillTheAvailableWidthExactly() {
        let layout = layout(widths: [[40, 40, 40]], columns: 3, available: 600)
        #expect(abs(layout.gridWidth - 600) < 0.001)
    }

    @Test func theSlackIsSharedInProportionToWhatEachColumnAskedFor() {
        let layout = layout(widths: [[300, 30, 30]], columns: 3, available: 600)
        #expect(layout.columnWidths[0] > layout.columnWidths[1])
        #expect(abs(layout.columnWidths[1] - layout.columnWidths[2]) < 0.001)
        #expect(abs(layout.gridWidth - 600) < 0.001)
    }

    @Test func aSqueezedTableNeverTakesAColumnBelowTheMinimum() {
        let layout = layout(widths: [[400, 400, 20]], columns: 3, available: 300)
        for width in layout.columnWidths {
            #expect(width >= MarkdownTableMetrics.minimumColumnWidth - 0.001)
        }
        #expect(abs(layout.gridWidth - 300) < 0.001)
    }

    /// When even the minimums overflow, the minimums win and the grid runs off the edge. A grid
    /// narrower than its own hit targets is worse than one that clips.
    @Test func whenEvenTheMinimumsDoNotFitTheMinimumsWin() {
        let columns = 12
        let layout = layout(widths: [Array(repeating: 200, count: columns)], columns: columns, available: 120)
        #expect(layout.columnWidths.allSatisfy { abs($0 - MarkdownTableMetrics.minimumColumnWidth) < 0.001 })
        #expect(layout.gridWidth > 120)
    }

    @Test func aColumnIsAtLeastAsWideAsItsWidestCellPlusPadding() {
        let layout = layout(widths: [[10, 10], [220, 10]], columns: 2, available: 600)
        #expect(layout.columnWidths[0] >= 220 + MarkdownTableMetrics.cellPaddingX * 2 - 0.001)
    }

    // MARK: - Rects

    private var gridRect: CGRect { CGRect(x: 20, y: 100, width: 600, height: 0) }

    @Test func theCentreOfEveryCellHitTestsBackToThatCell() {
        let rows = 4
        let layout = layout(widths: Array(repeating: [80, 200, 40], count: rows), columns: 3, available: 600)
        for row in 0..<rows {
            for column in 0..<3 {
                guard let rect = layout.cellRect(row: row, column: column, in: gridRect) else {
                    Issue.record("no rect for \(row),\(column)")
                    continue
                }
                let hit = layout.address(at: CGPoint(x: rect.midX, y: rect.midY), in: gridRect)
                #expect(hit == MarkdownTableCellAddress(row: row, column: column))
            }
        }
    }

    @Test func aPointOutsideTheGridHitsNothing() {
        let layout = layout(widths: [[40, 40]], columns: 2, available: 600)
        #expect(layout.address(at: CGPoint(x: 30, y: gridRect.minY - 4), in: gridRect) == nil)
        #expect(layout.address(at: CGPoint(x: 30, y: gridRect.minY + layout.gridHeight + 4), in: gridRect) == nil)
        #expect(layout.address(at: CGPoint(x: gridRect.minX - 4, y: gridRect.minY + 2), in: gridRect) == nil)
        #expect(layout.address(at: CGPoint(x: gridRect.minX + 10_000, y: gridRect.minY + 2), in: gridRect) == nil)
    }

    @Test func rowZeroSitsAtTheTopOfAFlippedGrid() {
        let layout = layout(widths: [[40, 40], [40, 40]], columns: 2, available: 600)
        let first = layout.cellRect(row: 0, column: 0, in: gridRect)
        let second = layout.cellRect(row: 1, column: 0, in: gridRect)
        #expect(first?.minY == gridRect.minY)
        #expect(second?.minY == gridRect.minY + rowHeight)
    }

    @Test func cellRectsForRowsAndColumnsThatDoNotExistAreNil() {
        let layout = layout(widths: [[40, 40]], columns: 2, available: 600)
        #expect(layout.cellRect(row: 1, column: 0, in: gridRect) == nil)
        #expect(layout.cellRect(row: 0, column: 2, in: gridRect) == nil)
        #expect(layout.cellRect(row: -1, column: 0, in: gridRect) == nil)
    }

    // MARK: - The styler / draw-pass agreement

    /// The styler reserves a line height and the draw pass fills it. If the reservation were ever
    /// smaller than the grid, the canvas would overflow its own line fragment and a partial redraw
    /// would clip it — the failure `MarkdownEditorTextViewDecorations` documents for the embed card.
    @Test func theReservedLineHeightAlwaysContainsTheGridItIsDrawnFor() {
        for rows in 1...12 {
            let reserved = MarkdownTableMetrics.reservedLineHeight(rowCount: rows, rowHeight: rowHeight)
            let grid = MarkdownTableMetrics.gridHeight(rowCount: rows, rowHeight: rowHeight)
            #expect(reserved >= grid + MarkdownTableMetrics.verticalPadding * 2 - 0.001)
        }
    }

    @Test func theGridRectSitsInsideTheLineFragmentItIsGiven() {
        let rows = 3
        let reserved = MarkdownTableMetrics.reservedLineHeight(rowCount: rows, rowHeight: rowHeight)
        let lineRect = CGRect(x: 12, y: 200, width: 560, height: reserved)
        let grid = MarkdownTableMetrics.gridRect(
            lineRect: lineRect,
            containerWidth: 560,
            rowCount: rows,
            rowHeight: rowHeight
        )
        #expect(grid.minY >= lineRect.minY)
        #expect(grid.maxY <= lineRect.maxY + 0.001)
        #expect(grid.minX >= lineRect.minX)
    }

    @Test func rowHeightIsNeverSmallerThanAComfortableTapTarget() {
        #expect(MarkdownTableMetrics.rowHeight(forTextHeight: 2) >= 24)
        #expect(MarkdownTableMetrics.rowHeight(forTextHeight: 40) >= 40)
    }
}
