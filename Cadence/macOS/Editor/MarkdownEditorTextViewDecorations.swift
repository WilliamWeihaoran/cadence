#if os(macOS)
import AppKit

/// The two markdown decorations that could not stay on `CadenceLayoutManager`.
///
/// Six of the editor's eight decoration passes need only colour constants and rect arithmetic, so
/// they are `nonisolated` members of `CadenceLayoutManager` and match the nonisolated
/// `NSLayoutManager` members they override. These two do not: each one *writes* a hit-rect cache on
/// `CadenceTextView` (`markdownTaskEmbedRects`, `markdownImageRects`) so that clicking a card,
/// a checkbox or a resize handle measures the same rectangle that was drawn, and reads the view's
/// hover and selection state to decide how to draw. `CadenceTextView` is main-actor isolated
/// because `NSTextView` is, so the passes have to run somewhere main-actor. Here.
///
/// **Why `drawBackground(in:)` and not the end of `draw(_:)`.** AppKit gives the view exactly two
/// hooks around the layout manager's work: `drawBackground(in:)` before it, and returning from
/// `super.draw(_:)` after all of it. There is no main-actor hook *between* the background pass and
/// the glyph pass, so moving these two out of `drawBackground(forGlyphRange:at:)` necessarily
/// changes their z-order — the only question was which way, and the three questions that kept this
/// refactor unlanded were all about that. Measured on macOS 26 they come out the same either way,
/// for a reason worth recording: **the selection highlight and the insertion point are not painted
/// inside the view's `draw(_:)` at all.** A full-view `cacheDisplay` with
/// `shouldDrawInsertionPoint == true` is pixel-identical to one with the caret off, and moving
/// these passes to after `super.draw(_:)` changes no pixel of a selection spanning the embed card.
/// Both are composited above everything the view draws, so nothing in this file can occlude either.
///
/// `drawBackground(in:)` is still the right hook rather than an arbitrary one: it is the ordering
/// these passes already had relative to the glyph pass, and it stays correct if AppKit ever goes
/// back to drawing the selection inside `draw(_:)`. Running after `super.draw(_:)` would be correct
/// only for as long as the current compositing holds.
///
/// Two observed behaviours the tests pin down, because they look like bugs and are not: a selection
/// spanning an embed card washes the card out completely, and the same selection leaves a
/// standalone image untouched. Both follow from how the lines are hidden. An embed line goes
/// through `MarkdownStylist.hide`, which collapses its glyphs to a 0.1pt font, so the selection
/// rect for the line's trailing newline starts at the left margin and spans the whole container —
/// over the card. An image line only carries `.cadenceMarkdownHidden` and keeps its glyphs at full
/// size, so that same newline rect starts past the reference text and lands to the right of the
/// drawn image. Neither depends on where these passes run: every offscreen render of these
/// scenarios is byte-identical to the same render taken before the move.
///
/// **Why the glyph range is derived rather than received.** The layout manager was handed the
/// range it had to draw; the view is handed a dirty rect. `glyphRange(forBoundingRect:in:)` returns
/// every glyph whose line fragment intersects that rect, and both decorations are contained by
/// their own line fragment — `MarkdownStylist` reserves `cardHeight + 12` for an embed line and
/// `imageHeight + 18` for an image line, and the card and image are drawn 6pt and 9pt down from the
/// fragment's top edge. A dirty rect that touches any part of a decoration therefore always
/// contains part of the fragment that decoration belongs to, so a partial redraw cannot clip one
/// in half.
extension CadenceTextView {
    /// Runs from `drawBackground(in:)`, i.e. before the layout manager draws text backgrounds or
    /// glyphs.
    func drawMarkdownDecorations(in rect: NSRect) {
        guard let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let boundingRect = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: boundingRect, in: textContainer)
        guard glyphRange.length > 0 else { return }

        drawMarkdownTaskEmbeds(
            forGlyphRange: glyphRange,
            at: origin,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
        drawMarkdownImages(
            forGlyphRange: glyphRange,
            at: origin,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
    }

    private func drawMarkdownTaskEmbeds(
        forGlyphRange glyphRange: NSRange,
        at origin: NSPoint,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        guard let textStorage else { return }
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: characterRange) { value, range, _ in
            guard let embed = value as? MarkdownTaskEmbedLayoutInfo,
                  range.location < textStorage.length else { return }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }

            let lineRect = layoutManager
                .lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                .offsetBy(dx: origin.x, dy: origin.y)
            let cardRect = MarkdownTaskEmbedDrawing.cardRect(
                forLineRect: lineRect,
                textContainerWidth: textContainer.containerSize.width,
                task: embed.task
            )
            let checkboxRect = MarkdownTaskEmbedDrawing.checkboxRect(in: cardRect)
            self.markdownTaskEmbedRects[embed.task.id] = MarkdownTaskEmbedHitRects(
                card: cardRect,
                checkbox: checkboxRect.insetBy(dx: -6, dy: -6)
            )
            let hoveredTarget = self.hoveredMarkdownTaskEmbed?.id == embed.task.id
                ? self.hoveredMarkdownTaskEmbed?.target
                : nil
            MarkdownTaskEmbedDrawing.drawCard(
                task: embed.task,
                cardRect: cardRect,
                checkboxRect: checkboxRect,
                hoveredTarget: hoveredTarget
            )
        }
    }

    private func drawMarkdownImages(
        forGlyphRange glyphRange: NSRange,
        at origin: NSPoint,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        guard let textStorage else { return }
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownImage, in: characterRange) { value, range, _ in
            guard let info = value as? MarkdownImageLayoutInfo else { return }
            guard range.location < textStorage.length else { return }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }

            let lineRect = layoutManager
                .lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                .offsetBy(dx: origin.x, dy: origin.y)
            let contentWidth = MarkdownDecorationGeometry.imageContentWidth(
                viewWidth: self.bounds.width,
                textContainerInsetWidth: self.textContainerInset.width
            )
            let imageSize = info.fittedSize(maxWidth: contentWidth)
            let imageRect = MarkdownDecorationGeometry.imageRect(lineRect: lineRect, imageSize: imageSize)

            self.markdownImageRects[info.id] = imageRect

            Theme.nsSurface.setFill()
            NSBezierPath(roundedRect: imageRect.insetBy(dx: -1, dy: -1), xRadius: 9, yRadius: 9).fill()

            if let image = info.image {
                image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                MarkdownStylist.highlightSurface.setFill()
                NSBezierPath(roundedRect: imageRect, xRadius: 8, yRadius: 8).fill()
                let label = "Missing image"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: MarkdownStylist.dimColor
                ]
                label.draw(at: NSPoint(x: imageRect.minX + 14, y: imageRect.midY - 8), withAttributes: attrs)
            }

            if self.selectedMarkdownImageID == info.id {
                MarkdownStylist.blueColor.setStroke()
                let selectionPath = NSBezierPath(roundedRect: imageRect.insetBy(dx: -2, dy: -2), xRadius: 10, yRadius: 10)
                selectionPath.lineWidth = 2
                selectionPath.stroke()
            }

            let handleRect = self.resizeHandleRect(for: imageRect)
            Theme.nsBg.withAlphaComponent(0.86).setFill()
            NSBezierPath(roundedRect: handleRect, xRadius: 5, yRadius: 5).fill()
            MarkdownStylist.blueColor.setStroke()
            let handle = NSBezierPath()
            handle.lineWidth = 1.4
            handle.move(to: NSPoint(x: handleRect.minX + 4, y: handleRect.maxY - 5))
            handle.line(to: NSPoint(x: handleRect.maxX - 5, y: handleRect.minY + 4))
            handle.move(to: NSPoint(x: handleRect.minX + 8, y: handleRect.maxY - 5))
            handle.line(to: NSPoint(x: handleRect.maxX - 5, y: handleRect.minY + 8))
            handle.stroke()
        }
    }
}
#endif
