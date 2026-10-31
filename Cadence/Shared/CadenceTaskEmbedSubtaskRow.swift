import CoreGraphics
import Foundation

/// One subtask's place on a task-embed card's subtask row: a checkbox glyph, then its title.
///
/// `label` is the subtask's **title alone**. [[T-9273]]: the iOS card used to draw `"[ ] Buy milk"`
/// / `"[x] Call Sam"` as one string — markdown checkbox syntax spelled out on a card that draws a
/// real circle for the task itself — and took the first ~34pt of that text as the tap target.
/// The state is the glyph's job now, and the label never carries it.
nonisolated struct CadenceTaskEmbedSubtaskRowItem: Equatable {
    let subtaskID: UUID
    let label: String
    let isDone: Bool
    let full: CGRect
    let checkbox: CGRect
    let text: CGRect
}

nonisolated struct CadenceTaskEmbedSubtaskRowLayout: Equatable {
    let items: [CadenceTaskEmbedSubtaskRowItem]
    /// Where the next thing on the row (an overflow count) may start.
    let trailingX: CGFloat
}

/// The subtask row both task-embed cards draw: the Mac's (`MarkdownTaskEmbedDrawingSupport`) and
/// the iOS note editor's (`iOSMarkdownTaskEmbedLayoutInfo`). Geometry only, in a y-down space,
/// which both an `NSTextView`'s flipped coordinates and UIKit share; each platform paints the
/// rects with its own bezier type.
///
/// The one per-platform number is the tap slop in `checkboxHit` — a pointer lands on a 10pt
/// glyph, a fingertip does not.
nonisolated enum CadenceTaskEmbedSubtaskRow {
    static let checkboxSide: CGFloat = 10
    static let checkboxLeading: CGFloat = 3
    static let checkboxTextGap: CGFloat = 5
    static let minimumItemWidth: CGFloat = 58
    static let maximumItemWidth: CGFloat = 150
    static let itemSpacing: CGFloat = 6

    /// Lays the subtasks out left to right from `minX`, each item as wide as its title plus the
    /// glyph (clamped to `minimumItemWidth...maximumItemWidth`), stopping at the first that would
    /// cross `maxX`. `measure(title, isDone)` is the drawn width of a title in the caller's font.
    static func layout(
        _ subtasks: [MarkdownTaskEmbedSubtaskRenderInfo],
        fallbackTitle: String,
        minX: CGFloat,
        maxX: CGFloat,
        rowY: CGFloat,
        rowHeight: CGFloat,
        measure: (String, Bool) -> CGFloat
    ) -> CadenceTaskEmbedSubtaskRowLayout {
        var x = minX
        var items: [CadenceTaskEmbedSubtaskRowItem] = []
        let textInset = checkboxLeading + checkboxSide + checkboxTextGap

        for subtask in subtasks {
            let label = TaskTitleSupport.displayTitle(subtask.title, fallback: fallbackTitle)
            let width = min(max(minimumItemWidth, measure(label, subtask.isDone) + 28), maximumItemWidth)
            guard x + width <= maxX else { break }

            let full = CGRect(x: x, y: rowY, width: width, height: rowHeight)
            let checkbox = CGRect(
                x: full.minX + checkboxLeading,
                y: full.midY - checkboxSide / 2,
                width: checkboxSide,
                height: checkboxSide
            )
            let text = CGRect(
                x: full.minX + textInset,
                y: full.minY + 1,
                width: max(16, full.width - textInset - 3),
                height: rowHeight - 2
            )
            items.append(CadenceTaskEmbedSubtaskRowItem(
                subtaskID: subtask.id,
                label: label,
                isDone: subtask.isDone,
                full: full,
                checkbox: checkbox,
                text: text
            ))
            x = full.maxX + itemSpacing
        }

        return CadenceTaskEmbedSubtaskRowLayout(items: items, trailingX: x)
    }

    /// [[T-9322]]: `layout` plus the `+N` overflow chip, counted against every subtask the task
    /// has (`totalCount`), not only those never offered to the row. When the chip does not fit
    /// after the placed items, the last placed item gives up its room and joins the count — a
    /// subtask is either drawn or counted, never silently lost. `overflowWidth(count)` is the
    /// chip's drawn width for that count. `overflow` is nil when nothing is left over, or when
    /// not even the chip fits on an empty row.
    static func layoutWithOverflow(
        _ subtasks: [MarkdownTaskEmbedSubtaskRenderInfo],
        totalCount: Int,
        fallbackTitle: String,
        minX: CGFloat,
        maxX: CGFloat,
        rowY: CGFloat,
        rowHeight: CGFloat,
        overflowWidth: (Int) -> CGFloat,
        measure: (String, Bool) -> CGFloat
    ) -> (row: CadenceTaskEmbedSubtaskRowLayout, overflow: (count: Int, full: CGRect)?) {
        let row = layout(
            subtasks,
            fallbackTitle: fallbackTitle,
            minX: minX,
            maxX: maxX,
            rowY: rowY,
            rowHeight: rowHeight,
            measure: measure
        )
        var items = row.items
        var trailingX = row.trailingX
        while totalCount - items.count > 0 {
            let count = totalCount - items.count
            let width = overflowWidth(count)
            if trailingX + width <= maxX {
                let full = CGRect(x: trailingX, y: rowY, width: width, height: rowHeight)
                return (CadenceTaskEmbedSubtaskRowLayout(items: items, trailingX: trailingX), (count, full))
            }
            guard !items.isEmpty else { break }
            items.removeLast()
            trailingX = items.last.map { $0.full.maxX + itemSpacing } ?? minX
        }
        return (CadenceTaskEmbedSubtaskRowLayout(items: items, trailingX: trailingX), nil)
    }

    /// The tick inside a done subtask's glyph, y-down: short stroke down-right, long stroke up.
    static func checkPoints(in rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX + 2.4, y: rect.midY + 0.4),
            CGPoint(x: rect.minX + 4.7, y: rect.maxY - 3),
            CGPoint(x: rect.maxX - 2.2, y: rect.minY + 3),
        ]
    }

    /// The subtask whose glyph — grown by the slop — holds `point`. The text beside a glyph is not
    /// part of its target.
    static func checkboxHit(
        at point: CGPoint,
        in items: [CadenceTaskEmbedSubtaskRowItem],
        slopX: CGFloat,
        slopY: CGFloat
    ) -> UUID? {
        items.first { $0.checkbox.insetBy(dx: -slopX, dy: -slopY).contains(point) }?.subtaskID
    }
}
