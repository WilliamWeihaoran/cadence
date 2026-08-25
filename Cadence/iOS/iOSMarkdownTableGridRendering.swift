#if os(iOS)
import SwiftUI
import UIKit

/// **A table drawn as a real grid, in vectors, straight into the glyph pass.**
///
/// Every other rendered block on this platform is a `UIImage` raster hung on
/// `cadenceMarkdownBlockCanvas` and rebuilt on every styling pass — which is every keystroke — and
/// `MarkdownRenderedBlockLimits` exists because that cost grows with the block. A table that can be
/// *edited* cannot be capped at sixteen rows: the seventeenth row would be a row you can neither
/// see nor reach. So this one block draws itself instead, the way the macOS editor already draws
/// its grid, and the cap stops applying to it. A twenty-row table costs a few dozen strokes rather
/// than a two-megapixel bitmap.
///
/// Nothing here decides anything about markdown or about geometry. Column widths, cell rects and
/// the hit test are `MarkdownTableLayout`'s; the grid, its cells and its source ranges are
/// `MarkdownTableEditor`'s. Both are in `Services/`, pure, and covered — which is what T-221's
/// macOS half was built for.
nonisolated enum iOSMarkdownTableGridMetrics {
    static let cellFont = UIFont.systemFont(ofSize: 15)
    static let headerCellFont = UIFont.systemFont(ofSize: 15, weight: .semibold)

    /// One row's height, for every table on this platform.
    ///
    /// The shared floor is 24pt, which is right for a pointer and wrong for a finger: a row is the
    /// hit target for opening a cell, and 24pt is well under what a thumb can land on in a grid of
    /// them. The larger of the two wins, so the type still decides the height whenever the type is
    /// the bigger constraint.
    static let rowHeight: CGFloat = max(
        34,
        MarkdownTableMetrics.rowHeight(
            forTextHeight: (headerCellFont.ascender - headerCellFont.descender).rounded(.up)
        )
    )

    static func font(isHeader: Bool) -> UIFont {
        isHeader ? headerCellFont : cellFont
    }

    static func textAlignment(_ alignment: MarkdownTableAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

/// What the styler measured for one rendered table, carried on `cadenceMarkdownTable`.
///
/// **It carries the layout, not just the grid, and that is the difference from macOS.** There the
/// draw pass computes column widths and writes them into a hit cache the click reads back. Here the
/// draw pass is `nonisolated` inside a layout manager and cannot write to anything, so the widths
/// have to be decided once — at styling time, on the main actor — and read by *both* the draw and
/// the touch. Re-deriving them at hit-test time would be the exact failure `MarkdownTableLayout`'s
/// own doc comment warns about: a tap landing one column over from what was drawn.
nonisolated final class iOSMarkdownTableRenderInfo: NSObject {
    let grid: MarkdownTableGrid
    let layout: MarkdownTableLayout
    /// The text container width the layout was computed against, kept so `gridRect(inLineFragment:)`
    /// can go back through `MarkdownTableMetrics.gridRect` rather than re-spelling its insets.
    let containerWidth: CGFloat

    /// The table's first character. Stable across every edit made *inside* the table — a cell
    /// rewrite, a row insert and a whole-table column rewrite all start at or after it — which is
    /// what lets an open cell editor survive its own commit.
    var anchor: Int { grid.storageRange.location }

    init(grid: MarkdownTableGrid, layout: MarkdownTableLayout, containerWidth: CGFloat) {
        self.grid = grid
        self.layout = layout
        self.containerWidth = containerWidth
        super.init()
    }

    static func make(grid: MarkdownTableGrid, containerWidth: CGFloat) -> iOSMarkdownTableRenderInfo {
        let width = MarkdownTableMetrics.gridRect(
            lineRect: .zero,
            containerWidth: containerWidth,
            rowCount: grid.rowCount,
            rowHeight: iOSMarkdownTableGridMetrics.rowHeight
        ).width
        let layout = MarkdownTableLayout.compute(
            intrinsicCellWidths: iOSMarkdownTableGridDrawing.intrinsicCellWidths(for: grid),
            columnCount: grid.columnCount,
            availableWidth: width,
            rowHeight: iOSMarkdownTableGridMetrics.rowHeight
        )
        return iOSMarkdownTableRenderInfo(grid: grid, layout: layout, containerWidth: containerWidth)
    }

    /// Where the grid sits inside the one line fragment the styler reserved for it, in text
    /// container coordinates.
    ///
    /// **The one definition of "where the table is"** — the same role
    /// `iOSMarkdownBlockCanvas.blockRect` plays for every raster block, and used by the drawing pass
    /// and by the touch for the same reason.
    func gridRect(inLineFragment fragment: CGRect) -> CGRect {
        MarkdownTableMetrics.gridRect(
            lineRect: fragment,
            containerWidth: containerWidth,
            rowCount: grid.rowCount,
            rowHeight: iOSMarkdownTableGridMetrics.rowHeight
        )
    }

    func cellRect(_ address: MarkdownTableCellAddress, inLineFragment fragment: CGRect) -> CGRect? {
        layout.cellRect(row: address.row, column: address.column, in: gridRect(inLineFragment: fragment))
    }

    func address(atTextPoint point: CGPoint, inLineFragment fragment: CGRect) -> MarkdownTableCellAddress? {
        layout.address(at: point, in: gridRect(inLineFragment: fragment))
    }
}

nonisolated enum iOSMarkdownTableGridDrawing {
    static func intrinsicCellWidths(for grid: MarkdownTableGrid) -> [[CGFloat]] {
        grid.rows.enumerated().map { rowIndex, cells in
            let font = iOSMarkdownTableGridMetrics.font(isHeader: rowIndex == 0)
            return cells.map { cell in
                (cell as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
            }
        }
    }

    static func draw(_ info: iOSMarkdownTableRenderInfo, in gridRect: CGRect) {
        guard gridRect.width > 0, gridRect.height > 0 else { return }
        let layout = info.layout
        let outline = UIBezierPath(roundedRect: gridRect, cornerRadius: MarkdownTableMetrics.cornerRadius)

        UIGraphicsGetCurrentContext()?.saveGState()
        outline.addClip()

        UIColor(Theme.surfaceElevated).withAlphaComponent(0.54).setFill()
        UIBezierPath(rect: gridRect).fill()

        for row in 0..<layout.rowCount {
            let rowRect = CGRect(
                x: gridRect.minX,
                y: gridRect.minY + CGFloat(row) * layout.rowHeight,
                width: gridRect.width,
                height: layout.rowHeight
            )
            if row == 0 {
                UIColor(Theme.surfaceHighlight).withAlphaComponent(0.92).setFill()
                UIBezierPath(rect: rowRect).fill()
            } else if row % 2 == 0 {
                UIColor(Theme.surface).withAlphaComponent(0.45).setFill()
                UIBezierPath(rect: rowRect).fill()
            }
        }

        UIColor(Theme.borderSubtle).withAlphaComponent(0.62).setStroke()
        let separators = UIBezierPath()
        separators.lineWidth = 0.7
        for row in 1..<max(layout.rowCount, 1) {
            let y = gridRect.minY + CGFloat(row) * layout.rowHeight
            separators.move(to: CGPoint(x: gridRect.minX, y: y))
            separators.addLine(to: CGPoint(x: gridRect.maxX, y: y))
        }
        var x = gridRect.minX
        for width in layout.columnWidths.dropLast() {
            x += width
            separators.move(to: CGPoint(x: x, y: gridRect.minY))
            separators.addLine(to: CGPoint(x: x, y: gridRect.maxY))
        }
        separators.stroke()

        for (rowIndex, cells) in info.grid.rows.enumerated() where rowIndex < layout.rowCount {
            for (columnIndex, cell) in cells.enumerated() where columnIndex < layout.columnWidths.count {
                guard let rect = layout.cellRect(row: rowIndex, column: columnIndex, in: gridRect) else { continue }
                draw(
                    cell: cell,
                    in: rect,
                    isHeader: rowIndex == 0,
                    alignment: info.grid.alignments[min(columnIndex, info.grid.alignments.count - 1)]
                )
            }
        }

        UIGraphicsGetCurrentContext()?.restoreGState()

        UIColor(Theme.borderSubtle).withAlphaComponent(0.85).setStroke()
        outline.lineWidth = 0.8
        outline.stroke()
    }

    private static func draw(
        cell: String,
        in rect: CGRect,
        isHeader: Bool,
        alignment: MarkdownTableAlignment
    ) {
        guard !cell.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = iOSMarkdownTableGridMetrics.textAlignment(alignment)
        let font = iOSMarkdownTableGridMetrics.font(isHeader: isHeader)
        // Muted header over full-contrast body, matching the Mac's grid and every other column
        // header in the app. The data is the thing you read; the header names it.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(isHeader ? Theme.muted : Theme.text),
            .paragraphStyle: paragraph
        ]
        let textRect = CGRect(
            x: rect.minX + MarkdownTableMetrics.cellPaddingX,
            y: rect.midY - (font.ascender - font.descender) / 2,
            width: max(0, rect.width - MarkdownTableMetrics.cellPaddingX * 2),
            height: (font.ascender - font.descender).rounded(.up)
        )
        (cell as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
#endif
