#if os(macOS)
import AppKit

/// What the draw pass measured, kept so a click can ask the same question.
///
/// Same contract as `markdownTaskEmbedRects` and `markdownImageRects`: the rect a cell was drawn in
/// is the rect a click is tested against, because they come from one `MarkdownTableLayout` value
/// rather than from two walks of the column widths.
struct MarkdownTableHitInfo {
    /// The table's first character, in storage coordinates. Stable across every edit made inside
    /// the table — a cell rewrite, a row insert and a whole-table column rewrite all start at or
    /// after it — which is what lets a cell editor survive its own commit.
    let anchor: Int
    let grid: MarkdownTableGrid
    let layout: MarkdownTableLayout
    let gridRect: NSRect
}

/// The grid itself. Pure drawing over rects `MarkdownTableLayout` decided, and colours from
/// `Theme`'s AppKit mirrors by way of `MarkdownStylist`.
enum MarkdownTableCanvasDrawing {
    static func intrinsicCellWidths(for grid: MarkdownTableGrid) -> [[CGFloat]] {
        grid.rows.enumerated().map { rowIndex, cells in
            let font = rowIndex == 0 ? MarkdownStylist.tableHeaderCellFont : MarkdownStylist.tableCellFont
            return cells.map { cell in
                (cell as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
            }
        }
    }

    static func draw(
        grid: MarkdownTableGrid,
        layout: MarkdownTableLayout,
        gridRect: NSRect,
        editingAddress: MarkdownTableCellAddress?
    ) {
        guard gridRect.width > 0, gridRect.height > 0 else { return }
        let outline = NSBezierPath(
            roundedRect: gridRect,
            xRadius: MarkdownTableMetrics.cornerRadius,
            yRadius: MarkdownTableMetrics.cornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()

        MarkdownStylist.codeBackground.withAlphaComponent(0.94).setFill()
        gridRect.fill()

        for row in 0..<layout.rowCount {
            let rowRect = NSRect(
                x: gridRect.minX,
                y: gridRect.minY + CGFloat(row) * layout.rowHeight,
                width: gridRect.width,
                height: layout.rowHeight
            )
            if row == 0 {
                MarkdownStylist.highlightSurface.withAlphaComponent(0.92).setFill()
                rowRect.fill()
            } else if row % 2 == 0 {
                Theme.nsSurface.withAlphaComponent(0.45).setFill()
                rowRect.fill()
            }
        }

        MarkdownStylist.codeBorder.withAlphaComponent(0.45).setStroke()
        let separators = NSBezierPath()
        separators.lineWidth = 0.7
        for row in 1..<max(layout.rowCount, 1) {
            let y = gridRect.minY + CGFloat(row) * layout.rowHeight
            separators.move(to: NSPoint(x: gridRect.minX, y: y))
            separators.line(to: NSPoint(x: gridRect.maxX, y: y))
        }
        var x = gridRect.minX
        for width in layout.columnWidths.dropLast() {
            x += width
            separators.move(to: NSPoint(x: x, y: gridRect.minY))
            separators.line(to: NSPoint(x: x, y: gridRect.maxY))
        }
        separators.stroke()

        for (rowIndex, cells) in grid.rows.enumerated() where rowIndex < layout.rowCount {
            for (columnIndex, cell) in cells.enumerated() where columnIndex < layout.columnWidths.count {
                let address = MarkdownTableCellAddress(row: rowIndex, column: columnIndex)
                guard address != editingAddress,
                      let rect = layout.cellRect(row: rowIndex, column: columnIndex, in: gridRect) else { continue }
                draw(cell: cell, in: rect, isHeader: rowIndex == 0, alignment: grid.alignments[columnIndex])
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        MarkdownStylist.codeBorder.withAlphaComponent(0.6).setStroke()
        outline.lineWidth = 0.8
        outline.stroke()
    }

    private static func draw(cell: String, in rect: NSRect, isHeader: Bool, alignment: MarkdownTableAlignment) {
        guard !cell.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = {
            switch alignment {
            case .leading: return .left
            case .center: return .center
            case .trailing: return .right
            }
        }()
        let font = isHeader ? MarkdownStylist.tableHeaderCellFont : MarkdownStylist.tableCellFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            // Muted header over full-contrast body, the way every other column header in the app
            // is drawn (`CadenceBoardColumnHeader`, `SectionEyebrowLabel`). The first pass had it the
            // other way round and the data — the thing you actually read — came out dimmer than the
            // prose underneath the table.
            .foregroundColor: isHeader ? MarkdownStylist.mutedColor : MarkdownStylist.textColor,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(
            x: rect.minX + MarkdownTableMetrics.cellPaddingX,
            y: rect.midY - (font.ascender - font.descender) / 2,
            width: max(0, rect.width - MarkdownTableMetrics.cellPaddingX * 2),
            height: (font.ascender - font.descender).rounded(.up)
        )
        (cell as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
#endif
