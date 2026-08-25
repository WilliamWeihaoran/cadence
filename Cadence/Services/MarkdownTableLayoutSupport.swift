import CoreGraphics
import Foundation

/// **Where a rendered table's cells sit, decided once so the draw pass and the click agree.**
///
/// Same division as `MarkdownDecorationGeometry`: the arithmetic that says where a cell is has to
/// be the arithmetic that says what was drawn there, or a click lands one column over. It is here
/// rather than in `macOS/Editor/` for two reasons — it is pure and testable, and the iOS half of
/// T-221 needs exactly these numbers.
///
/// Text *measurement* is not here. Intrinsic cell widths come in as numbers the caller measured
/// with its own font, so this file compiles with no AppKit and no UIKit.
nonisolated enum MarkdownTableMetrics {
    /// Inset from the text container's leading and trailing edges, matching the band the source
    /// rows were drawn in before they became a grid.
    static let outerInset: CGFloat = 8
    static let cellPaddingX: CGFloat = 9
    static let cellPaddingY: CGFloat = 5
    static let minimumColumnWidth: CGFloat = 46
    static let cornerRadius: CGFloat = 9
    /// Breathing room above and below the grid inside the line fragment it is drawn into.
    static let verticalPadding: CGFloat = 5

    static func rowHeight(forTextHeight textHeight: CGFloat) -> CGFloat {
        max(24, (textHeight + cellPaddingY * 2).rounded(.up))
    }

    static func gridHeight(rowCount: Int, rowHeight: CGFloat) -> CGFloat {
        CGFloat(max(rowCount, 1)) * rowHeight
    }

    /// The line height the styler must reserve on the table's first source line.
    ///
    /// The whole grid is drawn into that one fragment — every other line of the table is collapsed
    /// — so this is what stops the block from overlapping the paragraph after it. Width-independent
    /// by construction, because cells clip rather than wrap; that is what lets the reserved height
    /// survive a window resize with no restyle, which the image block's reserved height does not.
    static func reservedLineHeight(rowCount: Int, rowHeight: CGFloat) -> CGFloat {
        gridHeight(rowCount: rowCount, rowHeight: rowHeight) + verticalPadding * 2
    }

    static func gridRect(lineRect: CGRect, containerWidth: CGFloat, rowCount: Int, rowHeight: CGFloat) -> CGRect {
        CGRect(
            x: lineRect.minX + outerInset,
            y: lineRect.minY + verticalPadding,
            width: max(minimumColumnWidth, containerWidth - outerInset * 2),
            height: gridHeight(rowCount: rowCount, rowHeight: rowHeight)
        )
    }
}

nonisolated struct MarkdownTableLayout: Equatable {
    let columnWidths: [CGFloat]
    let rowHeight: CGFloat
    let rowCount: Int

    var gridWidth: CGFloat { columnWidths.reduce(0, +) }
    var gridHeight: CGFloat { MarkdownTableMetrics.gridHeight(rowCount: rowCount, rowHeight: rowHeight) }

    /// Column widths for one table.
    ///
    /// Three rules, in order:
    /// 1. every column is at least as wide as its widest cell plus padding, and never narrower than
    ///    `minimumColumnWidth` — a one-character column still has to be clickable;
    /// 2. if that fits, the slack is shared out **in proportion to what each column asked for**, so
    ///    the grid spans the container the way the banded source rows did and a prose column gets
    ///    more of the extra than a `Yes`/`No` column;
    /// 3. if it does not fit, columns shrink proportionally but never past the minimum. When even
    ///    the minimums overflow, the minimums win and the grid clips — a grid narrower than its own
    ///    hit targets is worse than one that runs off the edge.
    static func compute(
        intrinsicCellWidths: [[CGFloat]],
        columnCount: Int,
        availableWidth: CGFloat,
        rowHeight: CGFloat
    ) -> MarkdownTableLayout {
        let rowCount = max(intrinsicCellWidths.count, 1)
        guard columnCount > 0 else {
            return MarkdownTableLayout(columnWidths: [], rowHeight: rowHeight, rowCount: rowCount)
        }

        var desired = [CGFloat](repeating: MarkdownTableMetrics.minimumColumnWidth, count: columnCount)
        for row in intrinsicCellWidths {
            for (column, width) in row.enumerated() where column < columnCount {
                desired[column] = max(desired[column], width + MarkdownTableMetrics.cellPaddingX * 2)
            }
        }

        let total = desired.reduce(0, +)
        let target = max(availableWidth, 0)
        guard total > 0, target > 0 else {
            return MarkdownTableLayout(columnWidths: desired, rowHeight: rowHeight, rowCount: rowCount)
        }

        if total <= target {
            let slack = target - total
            var widths = desired.map { $0 + slack * ($0 / total) }
            widths[columnCount - 1] += target - widths.reduce(0, +)
            return MarkdownTableLayout(columnWidths: widths, rowHeight: rowHeight, rowCount: rowCount)
        }

        let floors = [CGFloat](repeating: MarkdownTableMetrics.minimumColumnWidth, count: columnCount)
        let floorTotal = floors.reduce(0, +)
        guard floorTotal < target else {
            return MarkdownTableLayout(columnWidths: floors, rowHeight: rowHeight, rowCount: rowCount)
        }
        let shrinkable = total - floorTotal
        let mustLose = total - target
        var widths = desired.enumerated().map { index, width -> CGFloat in
            let headroom = width - floors[index]
            return width - mustLose * (headroom / shrinkable)
        }
        widths[columnCount - 1] += target - widths.reduce(0, +)
        return MarkdownTableLayout(columnWidths: widths, rowHeight: rowHeight, rowCount: rowCount)
    }

    /// The rect of one cell inside a grid anchored at `gridRect`'s origin.
    ///
    /// Flipped-view convention (`NSTextView.isFlipped == true`): row 0 is at `gridRect.minY`.
    func cellRect(row: Int, column: Int, in gridRect: CGRect) -> CGRect? {
        guard row >= 0, row < rowCount, column >= 0, column < columnWidths.count else { return nil }
        let x = gridRect.minX + columnWidths.prefix(column).reduce(0, +)
        return CGRect(
            x: x,
            y: gridRect.minY + CGFloat(row) * rowHeight,
            width: columnWidths[column],
            height: rowHeight
        )
    }

    /// The cell under `point`, or `nil` when the point is outside the grid.
    ///
    /// The inverse of `cellRect`, and tested as such rather than re-derived: a hit test that walks
    /// the columns with its own arithmetic is the standard way a click starts landing one column
    /// over from what was drawn.
    func address(at point: CGPoint, in gridRect: CGRect) -> MarkdownTableCellAddress? {
        guard rowHeight > 0, !columnWidths.isEmpty else { return nil }
        guard point.y >= gridRect.minY, point.y < gridRect.minY + gridHeight else { return nil }
        guard point.x >= gridRect.minX else { return nil }

        let row = Int((point.y - gridRect.minY) / rowHeight)
        guard row >= 0, row < rowCount else { return nil }

        var x = gridRect.minX
        for (column, width) in columnWidths.enumerated() {
            if point.x < x + width {
                return MarkdownTableCellAddress(row: row, column: column)
            }
            x += width
        }
        return nil
    }
}
