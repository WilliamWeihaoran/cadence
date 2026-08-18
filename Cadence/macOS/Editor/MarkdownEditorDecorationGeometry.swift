#if os(macOS)
import AppKit

/// The rect arithmetic behind the markdown editor's drawn decorations.
///
/// Every decoration pass in `CadenceLayoutManager` (and the two that moved onto `CadenceTextView`)
/// used to compute its own rects inline, which made a ~2,000-line AppKit drawing file the only
/// place the numbers existed and left them unverifiable — the passes need a live `NSLayoutManager`,
/// a laid-out `NSTextContainer` and a focused graphics context to run at all. The measurements
/// themselves need none of that: given a line fragment and a container width they are pure
/// arithmetic.
///
/// So they live here, where `CadenceTests` can run them. The precedent is
/// `MarkdownChecklistBoxDrawing`, which is in this folder for the same reason and is already unit
/// tested. `Services/` would be the wrong home: it is cross-platform and compiled into the widget
/// and MCP targets, and this is `NSRect`/AppKit-typed and macOS-only.
///
/// This is measurement only. Nothing here fills, strokes or reads a colour, and extracting it does
/// not change any pass's isolation — the colours and the view caches were the isolation problem,
/// never the geometry.
nonisolated enum MarkdownDecorationGeometry {

    // MARK: - ==highlight==

    /// The rounded wash behind a `==highlight==` run.
    ///
    /// `enclosingRect` is one of the rects `enumerateEnclosingRects` hands back, in container
    /// space; the inset bleeds the wash past the glyphs so short runs still read as a marker
    /// stroke rather than a tight box.
    static func highlightRect(enclosingRect: NSRect, origin: NSPoint) -> NSRect {
        enclosingRect
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: -5, dy: -3)
    }

    /// Fully round the ends once the wash is shorter than it is tall, so it never reads as a chip.
    static func highlightCornerRadius(for rect: NSRect) -> CGFloat {
        min(8, rect.height / 2)
    }

    // MARK: - Tables

    /// One table row's banded background.
    ///
    /// Anchored to the container rather than to the row's own glyphs so every row in a table lines
    /// up even when their contents are different widths.
    static func tableRowRect(lineRect: NSRect, origin: NSPoint, containerWidth: CGFloat) -> NSRect {
        NSRect(
            x: origin.x + 8,
            y: lineRect.minY - 1,
            width: max(120, containerWidth - 16),
            height: max(12, lineRect.height + 3)
        )
    }

    static func tableRowCornerRadius(isHeader: Bool) -> CGFloat {
        isHeader ? 9 : 6
    }

    /// The hairline along a row's top edge, inset at both ends so it stops short of the rounded
    /// corners instead of cutting across them.
    static func tableRowTopBorder(in rowRect: NSRect) -> (start: NSPoint, end: NSPoint) {
        (
            NSPoint(x: rowRect.minX + 8, y: rowRect.maxY),
            NSPoint(x: rowRect.maxX - 8, y: rowRect.maxY)
        )
    }

    // MARK: - Code

    /// The chip behind one line's worth of an inline `code` run.
    static func inlineCodeChipRect(glyphBounds: NSRect, origin: NSPoint) -> NSRect {
        glyphBounds
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: -4, dy: -1)
    }

    static func inlineCodeCornerRadius(for rect: NSRect) -> CGFloat {
        min(6, rect.height / 2)
    }

    /// The slab behind a fenced code block, measured from its first and last line fragments.
    ///
    /// Container-width like a table row, so consecutive blocks stack as one column.
    static func codeBlockRect(
        firstLineRect: NSRect,
        lastLineRect: NSRect,
        origin: NSPoint,
        containerWidth: CGFloat
    ) -> NSRect {
        let minY = min(firstLineRect.minY, lastLineRect.minY)
        let maxY = max(firstLineRect.maxY, lastLineRect.maxY)
        return NSRect(
            x: firstLineRect.minX + origin.x + 8,
            y: minY + origin.y + 2,
            width: max(80, containerWidth - 16),
            height: max(18, maxY - minY - 4)
        )
    }

    // MARK: - Block quotes

    /// Horizontal step per nesting level, applied to both the wash and the bar so a nested quote
    /// keeps its bar against its own left edge.
    static let quoteLevelStep: CGFloat = 12

    static func quoteLevelInset(depth: Int) -> CGFloat {
        CGFloat(max(depth - 1, 0)) * quoteLevelStep
    }

    /// The wash behind a quote line. It reaches back into the gutter the paragraph style opened up
    /// for the bar, which is why the origin moves left as the width grows.
    static func quoteBackgroundRect(lineRect: NSRect, depth: Int) -> NSRect {
        let levelInset = quoteLevelInset(depth: depth)
        return NSRect(
            x: lineRect.minX - 14 - levelInset,
            y: lineRect.minY + 1,
            width: lineRect.width + 26 + levelInset,
            height: max(0, lineRect.height - 2)
        )
    }

    /// The vertical bar inside the wash.
    static func quoteBarRect(backgroundRect: NSRect, depth: Int) -> NSRect {
        let levelInset = quoteLevelInset(depth: depth)
        return NSRect(
            x: backgroundRect.minX + 5 + levelInset,
            y: backgroundRect.minY + 2,
            width: 4,
            height: max(0, backgroundRect.height - 4)
        )
    }

    // MARK: - Dividers

    /// The rule a `---` line draws in place of its hidden glyphs. Clamped at both ends so it reads
    /// as a deliberate ornament rather than a full-bleed border in either a narrow or a wide pane.
    static func dividerRuleRect(lineRect: NSRect) -> NSRect {
        let ruleWidth = max(160, min(280, lineRect.width + 140))
        return NSRect(
            x: lineRect.midX - (ruleWidth / 2),
            y: lineRect.midY - 1,
            width: ruleWidth,
            height: 2
        )
    }

    // MARK: - Images

    /// Width available to a drawn image, i.e. the text view minus both container insets and the
    /// same 24pt the styler subtracted when it reserved the line's height. The two must agree or
    /// the image overflows the fragment it was given.
    static func imageContentWidth(viewWidth: CGFloat, textContainerInsetWidth: CGFloat) -> CGFloat {
        max(1, viewWidth - (textContainerInsetWidth * 2) - 24)
    }

    /// Vertical padding `MarkdownStylist` reserves around a drawn image — 9pt above and 9pt below,
    /// matching the offset `imageRect(lineRect:imageSize:)` draws at.
    static let imageLinePadding: CGFloat = 18

    /// The line height a standalone image's paragraph style must reserve so the drawn image is
    /// entirely contained by its own line fragment.
    static func imageLineHeight(for imageSize: CGSize) -> CGFloat {
        imageSize.height + imageLinePadding
    }

    /// Where a standalone image draws inside its (fully hidden) line fragment.
    ///
    /// The 9pt top offset is half of the 18pt `MarkdownStylist` adds to the line height, so the
    /// image is vertically centred in its fragment and — the part partial-redraw correctness rests
    /// on — entirely contained by it.
    static func imageRect(lineRect: NSRect, imageSize: CGSize) -> NSRect {
        NSRect(
            x: lineRect.minX + 8,
            y: lineRect.minY + (imageLinePadding / 2),
            width: imageSize.width,
            height: imageSize.height
        )
    }
}
#endif
