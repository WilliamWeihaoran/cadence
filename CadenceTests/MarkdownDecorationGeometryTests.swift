import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// The markdown editor's drawn decorations, measured.
///
/// These passes need a live `NSLayoutManager`, a laid-out `NSTextContainer` and a focused graphics
/// context to run, which is why a ~2,000-line drawing file went unverified for so long. The
/// measurements need none of that, so they were lifted into `MarkdownDecorationGeometry` and are
/// checked here as *claims about the drawing* — a bar inside its wash, a row that lines up with
/// the row above it, a decoration contained by the line fragment reserved for it — rather than as
/// a second copy of the arithmetic.
struct MarkdownDecorationGeometryTests {

    // MARK: - ==highlight==

    /// The wash is a marker stroke, so it has to bleed past the glyphs it covers on every side;
    /// a rect tight to the glyph bounds reads as a code chip instead.
    @Test func theHighlightWashBleedsPastTheGlyphsItCovers() {
        let glyphs = NSRect(x: 40, y: 100, width: 90, height: 18)
        let wash = MarkdownDecorationGeometry.highlightRect(enclosingRect: glyphs, origin: .zero)

        #expect(wash.minX < glyphs.minX)
        #expect(wash.maxX > glyphs.maxX)
        #expect(wash.minY < glyphs.minY)
        #expect(wash.maxY > glyphs.maxY)
    }

    /// Enclosing rects come back in container space, so the container origin has to be added or
    /// every decoration on the page sits at the wrong place by the text container inset.
    @Test func theHighlightWashFollowsTheContainerOrigin() {
        let glyphs = NSRect(x: 40, y: 100, width: 90, height: 18)
        let atZero = MarkdownDecorationGeometry.highlightRect(enclosingRect: glyphs, origin: .zero)
        let offset = MarkdownDecorationGeometry.highlightRect(
            enclosingRect: glyphs,
            origin: NSPoint(x: 14, y: 26)
        )

        #expect(offset.origin.x == atZero.origin.x + 14)
        #expect(offset.origin.y == atZero.origin.y + 26)
        #expect(offset.size == atZero.size)
    }

    /// Short runs round fully into a lozenge; tall ones stop at a fixed corner so a highlighted
    /// heading does not turn into a pill.
    @Test func theHighlightCornerFullyRoundsShortRunsAndCapsOnTallOnes() {
        let short = NSRect(x: 0, y: 0, width: 60, height: 10)
        let tall = NSRect(x: 0, y: 0, width: 60, height: 40)

        #expect(MarkdownDecorationGeometry.highlightCornerRadius(for: short) == short.height / 2)
        #expect(MarkdownDecorationGeometry.highlightCornerRadius(for: tall) < tall.height / 2)
        #expect(MarkdownDecorationGeometry.highlightCornerRadius(for: tall) == 8)
    }

    // MARK: - Tables

    /// A table only reads as a table if its rows line up. The band is anchored to the text
    /// container, not to the row's own line fragment, so two rows still share an edge even when
    /// their glyphs start and end at different places — which is what happens the moment one row
    /// carries a head indent the other does not.
    @Test func tableRowsShareAnEdgeRegardlessOfTheirOwnLineFragment() {
        let origin = NSPoint(x: 12, y: 0)
        let narrow = MarkdownDecorationGeometry.tableRowRect(
            lineRect: NSRect(x: 20, y: 40, width: 60, height: 17),
            origin: origin,
            containerWidth: 520
        )
        let indented = MarkdownDecorationGeometry.tableRowRect(
            lineRect: NSRect(x: 68, y: 62, width: 380, height: 17),
            origin: origin,
            containerWidth: 520
        )

        #expect(narrow.minX == indented.minX)
        #expect(narrow.width == indented.width)
        #expect(narrow.maxY < indented.minY + indented.height)
    }

    /// And it is the *container* origin the band starts from, not the line's — the two coincide
    /// only for an unindented row, which is exactly why this drifted unnoticed.
    @Test func aTableBandStartsAtTheContainerOriginNotTheLine() {
        let origin = NSPoint(x: 12, y: 0)
        let row = MarkdownDecorationGeometry.tableRowRect(
            lineRect: NSRect(x: 68, y: 62, width: 380, height: 17),
            origin: origin,
            containerWidth: 520
        )

        #expect(row.minX < 68)
        #expect(row.minX - origin.x == 8)
    }

    /// The band has to cover the line it belongs to, with a little air, or the text sits on the
    /// band's edge.
    @Test func aTableBandCoversItsOwnLine() {
        let line = NSRect(x: 20, y: 40, width: 300, height: 17)
        let row = MarkdownDecorationGeometry.tableRowRect(lineRect: line, origin: .zero, containerWidth: 520)

        #expect(row.minY <= line.minY)
        #expect(row.maxY >= line.maxY)
    }

    /// A pane can be dragged narrower than any sensible table; the band stops shrinking before it
    /// disappears.
    @Test func aTableBandHasAFloorInABTightPane() {
        let row = MarkdownDecorationGeometry.tableRowRect(
            lineRect: NSRect(x: 0, y: 0, width: 10, height: 0),
            origin: .zero,
            containerWidth: 40
        )

        #expect(row.width == 120)
        #expect(row.height == 12)
    }

    /// The header band is the more rounded of the two, which is what separates it from the body
    /// rows stacked under it.
    @Test func theTableHeaderIsMoreRoundedThanABodyRow() {
        #expect(
            MarkdownDecorationGeometry.tableRowCornerRadius(isHeader: true)
                > MarkdownDecorationGeometry.tableRowCornerRadius(isHeader: false)
        )
    }

    /// The delimiter runs along the top edge and stops short of the corners, so it does not cut
    /// across the rounding it is drawn over.
    @Test func theTableRowBorderStopsShortOfTheRoundedCorners() {
        let row = NSRect(x: 12, y: 40, width: 500, height: 20)
        let border = MarkdownDecorationGeometry.tableRowTopBorder(in: row)

        #expect(border.start.y == row.maxY)
        #expect(border.end.y == row.maxY)
        #expect(border.start.x > row.minX)
        #expect(border.end.x < row.maxX)
        #expect(border.start.x - row.minX == row.maxX - border.end.x)
    }

    // MARK: - Code

    /// The chip has to wrap the glyphs it sits behind, and horizontally by more than vertically —
    /// inline code shares its line with prose, so a fat vertical inset would collide with the
    /// lines above and below.
    @Test func theInlineCodeChipWrapsItsGlyphsWiderThanItIsTall() {
        let glyphs = NSRect(x: 60, y: 200, width: 44, height: 16)
        let chip = MarkdownDecorationGeometry.inlineCodeChipRect(glyphBounds: glyphs, origin: .zero)

        #expect(chip.minX < glyphs.minX)
        #expect(chip.maxX > glyphs.maxX)
        #expect(glyphs.minX - chip.minX > glyphs.minY - chip.minY)
    }

    @Test func theInlineCodeChipNeverRoundsPastAHalfCircle() {
        let squat = NSRect(x: 0, y: 0, width: 30, height: 8)
        #expect(MarkdownDecorationGeometry.inlineCodeCornerRadius(for: squat) == squat.height / 2)

        let tall = NSRect(x: 0, y: 0, width: 30, height: 30)
        #expect(MarkdownDecorationGeometry.inlineCodeCornerRadius(for: tall) < tall.height / 2)
    }

    /// The slab is measured from the block's first and last line fragments and has to reach from
    /// one to the other — a fence that only covered its first line was the original bug shape here.
    @Test func theCodeSlabSpansEveryLineOfTheBlock() {
        let first = NSRect(x: 20, y: 100, width: 300, height: 18)
        let last = NSRect(x: 20, y: 172, width: 240, height: 18)
        let slab = MarkdownDecorationGeometry.codeBlockRect(
            firstLineRect: first,
            lastLineRect: last,
            origin: .zero,
            containerWidth: 520
        )

        #expect(slab.height >= last.maxY - first.minY - 4)
        #expect(slab.minY >= first.minY)
        #expect(slab.minX > first.minX)
    }

    /// Line fragments are not guaranteed to arrive in visual order, so the slab is measured from
    /// the extremes rather than from first-then-last.
    @Test func theCodeSlabIsTheSameWhicheverLineIsCalledFirst() {
        let a = NSRect(x: 20, y: 100, width: 300, height: 18)
        let b = NSRect(x: 20, y: 172, width: 240, height: 18)
        let forward = MarkdownDecorationGeometry.codeBlockRect(
            firstLineRect: a, lastLineRect: b, origin: .zero, containerWidth: 520
        )
        let backward = MarkdownDecorationGeometry.codeBlockRect(
            firstLineRect: b, lastLineRect: a, origin: .zero, containerWidth: 520
        )

        #expect(forward.minY == backward.minY)
        #expect(forward.height == backward.height)
    }

    /// A one-line fence still needs a visible slab rather than a hairline.
    @Test func aSingleLineCodeSlabKeepsAMinimumHeight() {
        let line = NSRect(x: 20, y: 100, width: 300, height: 14)
        let slab = MarkdownDecorationGeometry.codeBlockRect(
            firstLineRect: line, lastLineRect: line, origin: .zero, containerWidth: 520
        )

        #expect(slab.height == 18)
    }

    // MARK: - Block quotes

    /// The bar is the quote's whole affordance, so it has to be inside the wash it is drawn on and
    /// never taller than it.
    @Test func theQuoteBarSitsInsideItsOwnWash() {
        let line = NSRect(x: 60, y: 240, width: 380, height: 20)
        for depth in 1...4 {
            let wash = MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: line, depth: depth)
            let bar = MarkdownDecorationGeometry.quoteBarRect(backgroundRect: wash, depth: depth)

            #expect(bar.minX >= wash.minX)
            #expect(bar.maxX <= wash.maxX)
            #expect(bar.minY >= wash.minY)
            #expect(bar.maxY <= wash.maxY)
        }
    }

    /// Nesting widens the wash leftwards while leaving the bar where it is.
    ///
    /// Both rects take the same per-level inset, and it cancels out on the bar — the wash's left
    /// edge moves out by one step and the bar's offset inside the wash moves in by the same step.
    /// That is deliberate: a nested quote's *line fragment* is already indented by the paragraph
    /// style, so the bar tracks the text it belongs to, and the extra width is the wash reaching
    /// back over the parent quote's gutter so the two read as nested rather than as two separate
    /// blocks. The right edge is anchored to the line either way.
    @Test func nestingWidensTheWashLeftwardsAndLeavesTheBarOnTheText() {
        let line = NSRect(x: 60, y: 240, width: 380, height: 20)
        let outer = MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: line, depth: 1)
        let inner = MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: line, depth: 2)

        #expect(inner.maxX == outer.maxX)
        #expect(outer.minX - inner.minX == MarkdownDecorationGeometry.quoteLevelStep)

        let outerBar = MarkdownDecorationGeometry.quoteBarRect(backgroundRect: outer, depth: 1)
        let innerBar = MarkdownDecorationGeometry.quoteBarRect(backgroundRect: inner, depth: 2)
        #expect(innerBar.minX == outerBar.minX)
        #expect(innerBar.width == outerBar.width)
    }

    /// The bar is positioned relative to the *line*, so an indented nested line carries it along.
    @Test func anIndentedNestedLineCarriesTheBarWithIt() {
        let outerLine = NSRect(x: 60, y: 240, width: 380, height: 20)
        let innerLine = NSRect(x: 84, y: 264, width: 356, height: 20)
        let outerBar = MarkdownDecorationGeometry.quoteBarRect(
            backgroundRect: MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: outerLine, depth: 1),
            depth: 1
        )
        let innerBar = MarkdownDecorationGeometry.quoteBarRect(
            backgroundRect: MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: innerLine, depth: 2),
            depth: 2
        )

        #expect(innerBar.minX - outerBar.minX == innerLine.minX - outerLine.minX)
    }

    /// The first level is the unindented one — a `> ` quote must not already be stepped in.
    @Test func theFirstQuoteLevelIsNotIndented() {
        #expect(MarkdownDecorationGeometry.quoteLevelInset(depth: 1) == 0)
        #expect(MarkdownDecorationGeometry.quoteLevelInset(depth: 0) == 0)
        #expect(
            MarkdownDecorationGeometry.quoteLevelInset(depth: 3)
                == 2 * MarkdownDecorationGeometry.quoteLevelStep
        )
    }

    /// An empty quote line can measure zero height mid-relayout; neither rect may invert, because
    /// a negative-height `NSBezierPath` fill draws upward over the line above.
    @Test func aDegenerateQuoteLineNeverInvertsEitherRect() {
        let line = NSRect(x: 60, y: 240, width: 0, height: 0)
        let wash = MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: line, depth: 1)
        let bar = MarkdownDecorationGeometry.quoteBarRect(backgroundRect: wash, depth: 1)

        #expect(wash.height >= 0)
        #expect(bar.height >= 0)
    }

    // MARK: - Dividers

    /// The rule stands in for a `---` line's hidden glyphs, so it is centred on the line rather
    /// than anchored to either edge.
    @Test func theDividerRuleIsCentredOnItsLine() {
        let line = NSRect(x: 40, y: 300, width: 200, height: 16)
        let rule = MarkdownDecorationGeometry.dividerRuleRect(lineRect: line)

        #expect(rule.midX == line.midX)
        #expect(abs(rule.midY - line.midY) <= 1)
    }

    /// Clamped at both ends: an ornament, not a border. A wide pane must not produce a full-bleed
    /// line, and a narrow one must still produce something visible.
    @Test func theDividerRuleIsClampedAtBothEnds() {
        let narrow = MarkdownDecorationGeometry.dividerRuleRect(
            lineRect: NSRect(x: 0, y: 0, width: 2, height: 16)
        )
        let wide = MarkdownDecorationGeometry.dividerRuleRect(
            lineRect: NSRect(x: 0, y: 0, width: 900, height: 16)
        )

        #expect(narrow.width == 160)
        #expect(wide.width == 280)
        #expect(narrow.height == 2)
        #expect(wide.height == 2)
    }

    // MARK: - Images

    /// The invariant partial redraw rests on. A dirty rect only contains a decoration if it also
    /// contains part of the line fragment that decoration hangs off, because the glyph range the
    /// draw pass works from is derived from the dirty rect via `glyphRange(forBoundingRect:in:)`.
    /// That holds only while the image is entirely inside the fragment `MarkdownStylist` reserved
    /// for it.
    @Test func aDrawnImageIsContainedByTheLineFragmentReservedForIt() {
        for height in [60.0, 180.0, 420.0] as [CGFloat] {
            let size = CGSize(width: 320, height: height)
            let line = NSRect(
                x: 24,
                y: 500,
                width: 520,
                height: MarkdownDecorationGeometry.imageLineHeight(for: size)
            )
            let image = MarkdownDecorationGeometry.imageRect(lineRect: line, imageSize: size)

            #expect(image.minY >= line.minY)
            #expect(image.maxY <= line.maxY)
            #expect(image.minX >= line.minX)
        }
    }

    /// The image is centred in the height reserved for it, so the padding above and below match.
    @Test func aDrawnImageIsCentredInItsReservedHeight() {
        let size = CGSize(width: 300, height: 200)
        let line = NSRect(x: 0, y: 0, width: 520, height: MarkdownDecorationGeometry.imageLineHeight(for: size))
        let image = MarkdownDecorationGeometry.imageRect(lineRect: line, imageSize: size)

        #expect(image.minY - line.minY == line.maxY - image.maxY)
    }

    /// `MarkdownStylist` reserves the line height from the fitted size, and the draw pass fits the
    /// image to a width it measures separately. If those two widths disagreed the reserved height
    /// would be wrong and the image would overflow — so they come from one helper, and this is the
    /// end-to-end check that they still agree.
    @Test func theReservedHeightMatchesTheWidthTheDrawPassWillFitTo() {
        let info = MarkdownImageLayoutInfo(
            id: UUID(),
            altText: "",
            image: nil,
            displayWidth: 900,
            pixelSize: CGSize(width: 1600, height: 900)
        )
        let contentWidth = MarkdownDecorationGeometry.imageContentWidth(
            viewWidth: 640,
            textContainerInsetWidth: 18
        )
        let fitted = info.fittedSize(maxWidth: contentWidth)

        // The requested display width exceeds the pane, so the fit clamps to the content width.
        #expect(fitted.width == contentWidth)

        let line = NSRect(x: 0, y: 0, width: 640, height: MarkdownDecorationGeometry.imageLineHeight(for: fitted))
        let image = MarkdownDecorationGeometry.imageRect(lineRect: line, imageSize: fitted)
        #expect(image.maxY <= line.maxY)
    }

    /// The content width subtracts both container insets, so a wider inset leaves less room. A
    /// degenerate pane still reports something positive rather than a negative width.
    @Test func theImageContentWidthShrinksWithTheInsetAndNeverGoesNegative() {
        let wide = MarkdownDecorationGeometry.imageContentWidth(viewWidth: 800, textContainerInsetWidth: 10)
        let padded = MarkdownDecorationGeometry.imageContentWidth(viewWidth: 800, textContainerInsetWidth: 40)

        #expect(padded < wide)
        #expect(wide - padded == 60)
        #expect(MarkdownDecorationGeometry.imageContentWidth(viewWidth: 4, textContainerInsetWidth: 10) > 0)
    }

    // MARK: - Task embed cards

    /// The same containment claim for the other decoration that moved onto the text view. The card
    /// hangs off a line whose height `MarkdownStylist` set to `paragraphLineHeight`.
    @Test func aTaskEmbedCardIsContainedByTheLineFragmentReservedForIt() {
        let task = MarkdownTaskEmbedRenderInfo(
            id: UUID(),
            title: "Write the release notes",
            statusRaw: TaskStatus.todo.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            sectionName: "",
            containerName: "Cadence",
            containerColorHex: Theme.blueHex,
            dueDate: "",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 0,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: false,
            isCancelled: false,
            isMissing: false,
            subtasks: []
        )
        let line = NSRect(x: 24, y: 300, width: 520, height: task.paragraphLineHeight)
        let card = MarkdownTaskEmbedDrawing.cardRect(
            forLineRect: line,
            textContainerWidth: 520,
            task: task
        )

        #expect(card.minY >= line.minY)
        #expect(card.maxY <= line.maxY)
        #expect(card.minY - line.minY == line.maxY - card.maxY)
    }
}
#endif
