#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The markdown editor's decoration layer: everything drawn behind the glyphs that is not itself
/// a glyph — code slabs, `==highlight==` washes, table bands, quote bars, checklist circles and
/// `---` rules.
///
/// **Isolation.** `NSLayoutManager` is nonisolated in AppKit, but the project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this subclass and every member of it would be
/// main-actor isolated by default — and a main-actor override of a nonisolated declaration is an
/// error in Swift 6 language mode. Every override here, `drawBackground(forGlyphRange:at:)`
/// included, is therefore `nonisolated`, matching what it overrides.
///
/// `drawBackground` was the last macOS Swift 6 error in the app, and it was a refactor rather than
/// an annotation. The standard remedy — nonisolated override plus a checked
/// `MainActor.assumeIsolated` hop — does not compile: Swift 6 region isolation rejects capturing
/// the task-isolated, non-`Sendable` `self` in a main-actor closure, and that holds for
/// `[weak self]`, for a local copy, for `@unchecked Sendable` on the class, and for a single
/// closure with no later use of `self`. What made the annotation possible instead was splitting
/// the eight decoration passes by what they actually depend on:
///
/// - Six need only `MarkdownStylist`'s colour constants and pure rect arithmetic. They went
///   `nonisolated` with no behaviour change once `Theme` and the stylist's palette constants were
///   `nonisolated` too — every `MarkdownStylist` colour is `= Theme.ns*`, so a nonisolated
///   constant could not initialize until `Theme` was. Their measurements now live in
///   `MarkdownDecorationGeometry`, where the test target can run them.
/// - `drawTaskEmbeds` and `drawMarkdownImages` read and write `CadenceTextView`'s hit-rect and
///   hover caches, and `CadenceTextView` is main-actor isolated by AppKit because `NSTextView` is.
///   Those two moved onto the view — see `MarkdownEditorTextViewDecorations.swift`, which also
///   records why the hook they run from is `drawBackground(in:)` and not `draw(_:)`.
///
/// Do not reach for `nonisolated(unsafe)` or `@preconcurrency import AppKit` to widen this, and do
/// not move the view's caches into a nonisolated holder to make the two moved passes fit back in
/// here: that compiles, changes no z-order, and removes the diagnostic without removing the
/// hazard. If this method really could run off-main, touching `NSTextView` state would be a
/// genuine race, and Swift is being consistent.
final class CadenceLayoutManager: NSLayoutManager {
    nonisolated override init() {
        super.init()
    }

    nonisolated required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    nonisolated override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        for visibleRange in visibleGlyphRanges(in: glyphsToShow) {
            super.drawGlyphs(forGlyphRange: visibleRange, at: origin)
        }
    }

    /// `super` is called in the middle, not first, and the split is deliberate: the passes above it
    /// are washes that text backgrounds may sit on top of, the passes below it are marks that must
    /// stay on top. The task-embed card and the standalone image used to bracket this call too —
    /// the card above it, the image below — and both now draw from
    /// `CadenceTextView.drawBackground(in:)`, which runs before this method.
    nonisolated override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawCodeBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawHighlightBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawTableRows(forGlyphRange: glyphsToShow, at: origin)
        for visibleRange in visibleGlyphRanges(in: glyphsToShow) {
            super.drawBackground(forGlyphRange: visibleRange, at: origin)
        }
        drawQuoteBlocks(forGlyphRange: glyphsToShow, at: origin)
        drawChecklistBoxes(forGlyphRange: glyphsToShow, at: origin)
        drawDividerRules(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Draws the box that stands in for a hidden `- [x] ` prefix.
    ///
    /// Same shape as the quote bar above: the prefix is styled hidden, so `drawGlyphs` skips it and
    /// this fills the gutter the paragraph style left. It cannot be an `.attachment` the way the iOS
    /// styler does it — AppKit only turns that attribute into a glyph on `NSAttachmentCharacter`.
    nonisolated private func drawChecklistBoxes(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownChecklistBox, in: characterRange) { value, range, _ in
            guard let isDone = value as? Bool,
                  let prefixRange = self.checklistPrefixRange(containing: range.location),
                  let boxRect = self.checklistBoxRect(forPrefixCharacterRange: prefixRange, in: textContainer) else {
                return
            }
            MarkdownChecklistBoxDrawing.draw(in: boxRect.offsetBy(dx: origin.x, dy: origin.y), isDone: isDone)
        }
    }

    /// The whole prefix run at `location`, not the slice clipped to the range being drawn: the box is
    /// positioned from the prefix's leading edge, so measuring a partial run would move it.
    nonisolated func checklistPrefixRange(containing location: Int) -> NSRange? {
        guard let textStorage, location >= 0, location < textStorage.length else { return nil }
        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        let isBox = textStorage.attribute(
            .cadenceMarkdownChecklistBox,
            at: location,
            longestEffectiveRange: &effectiveRange,
            in: NSRange(location: 0, length: textStorage.length)
        ) is Bool
        guard isBox, effectiveRange.location != NSNotFound, effectiveRange.length > 0 else { return nil }
        return effectiveRange
    }

    /// Container-space box rect for a hidden checklist prefix. Shared by the draw pass and the click
    /// hit test, because the box is not a glyph and nothing else would keep the two agreeing.
    nonisolated func checklistBoxRect(forPrefixCharacterRange range: NSRange, in textContainer: NSTextContainer) -> NSRect? {
        let prefixGlyphRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard prefixGlyphRange.length > 0 else { return nil }
        return MarkdownChecklistBoxDrawing.boxRect(
            prefixRect: boundingRect(forGlyphRange: prefixGlyphRange, in: textContainer)
        )
    }

    nonisolated private func drawHighlightBackgrounds(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownHighlight, in: characterRange) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let highlightedRange = NSIntersectionRange(range, characterRange)
            guard highlightedRange.length > 0 else { return }
            let highlightedGlyphRange = self.glyphRange(forCharacterRange: highlightedRange, actualCharacterRange: nil)
            guard highlightedGlyphRange.length > 0 else { return }

            let selectedRange = NSRange(location: NSNotFound, length: 0)
            self.enumerateEnclosingRects(forGlyphRange: highlightedGlyphRange, withinSelectedGlyphRange: selectedRange, in: textContainer) { rect, _ in
                let highlightRect = MarkdownDecorationGeometry.highlightRect(enclosingRect: rect, origin: origin)
                guard highlightRect.width > 0, highlightRect.height > 0 else { return }

                let radius = MarkdownDecorationGeometry.highlightCornerRadius(for: highlightRect)
                let path = NSBezierPath(roundedRect: highlightRect, xRadius: radius, yRadius: radius)
                MarkdownStylist.highlightFillColor.withAlphaComponent(0.38).setFill()
                path.fill()
                MarkdownStylist.highlightBorderColor.withAlphaComponent(0.62).setStroke()
                path.lineWidth = 0.8
                path.stroke()
            }
        }
    }

    nonisolated private func drawTableRows(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownTableRow, in: characterRange) { value, range, _ in
            guard let style = value as? MarkdownTableRowStyle else { return }
            let rowGlyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard rowGlyphRange.length > 0 else { return }

            let lineRect = self.boundingRect(forGlyphRange: rowGlyphRange, in: textContainer)
                .offsetBy(dx: origin.x, dy: origin.y)
            let rowRect = MarkdownDecorationGeometry.tableRowRect(
                lineRect: lineRect,
                origin: origin,
                containerWidth: textContainer.containerSize.width
            )

            let fillColor: NSColor
            if style.isHeader {
                fillColor = MarkdownStylist.borderColor.withAlphaComponent(0.78)
            } else if style.isDelimiter {
                fillColor = MarkdownStylist.codeBorder.withAlphaComponent(0.58)
            } else {
                fillColor = (style.lineIndex % 2 == 0 ? MarkdownStylist.codeBackground : Theme.nsSurface).withAlphaComponent(0.72)
            }

            let cornerRadius = MarkdownDecorationGeometry.tableRowCornerRadius(isHeader: style.isHeader)
            fillColor.setFill()
            NSBezierPath(roundedRect: rowRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

            MarkdownStylist.codeBorder.withAlphaComponent(style.isHeader ? 0.75 : 0.45).setStroke()
            let topBorder = MarkdownDecorationGeometry.tableRowTopBorder(in: rowRect)
            let border = NSBezierPath()
            border.lineWidth = 0.7
            border.move(to: topBorder.start)
            border.line(to: topBorder.end)
            border.stroke()
        }
    }

    nonisolated private func drawCodeBackgrounds(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownCodeBlock, in: characterRange) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let blockCharacterRange = NSIntersectionRange(range, characterRange)
            guard blockCharacterRange.length > 0 else { return }
            let blockGlyphRange = self.glyphRange(forCharacterRange: blockCharacterRange, actualCharacterRange: nil)
            guard blockGlyphRange.length > 0 else { return }
            drawRoundedCodeBlock(forGlyphRange: blockGlyphRange, in: textContainer, at: origin)
        }

        textStorage.enumerateAttribute(.cadenceMarkdownInlineCode, in: characterRange) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let inlineCharacterRange = NSIntersectionRange(range, characterRange)
            guard inlineCharacterRange.length > 0 else { return }
            let inlineGlyphRange = self.glyphRange(forCharacterRange: inlineCharacterRange, actualCharacterRange: nil)
            guard inlineGlyphRange.length > 0 else { return }
            drawRoundedInlineCode(forGlyphRange: inlineGlyphRange, in: textContainer, at: origin)
        }
    }

    nonisolated private func drawRoundedInlineCode(forGlyphRange glyphRange: NSRange, in textContainer: NSTextContainer, at origin: NSPoint) {
        guard glyphRange.length > 0 else { return }

        var currentGlyph = glyphRange.location
        let glyphRangeEnd = NSMaxRange(glyphRange)

        while currentGlyph < glyphRangeEnd, currentGlyph < numberOfGlyphs {
            var lineGlyphRange = NSRange(location: 0, length: 0)
            _ = lineFragmentRect(forGlyphAt: currentGlyph, effectiveRange: &lineGlyphRange)
            let segmentRange = NSIntersectionRange(glyphRange, lineGlyphRange)

            guard segmentRange.length > 0 else {
                currentGlyph += 1
                continue
            }

            let glyphBounds = boundingRect(forGlyphRange: segmentRange, in: textContainer)
            let chipRect = MarkdownDecorationGeometry.inlineCodeChipRect(glyphBounds: glyphBounds, origin: origin)
            guard chipRect.width > 0, chipRect.height > 0 else {
                currentGlyph = NSMaxRange(segmentRange)
                continue
            }

            let radius = MarkdownDecorationGeometry.inlineCodeCornerRadius(for: chipRect)
            let path = NSBezierPath(roundedRect: chipRect, xRadius: radius, yRadius: radius)
            MarkdownStylist.codeBackground.withAlphaComponent(0.94).setFill()
            path.fill()

            MarkdownStylist.codeBorder.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 0.7
            path.stroke()

            currentGlyph = NSMaxRange(segmentRange)
        }
    }

    nonisolated private func drawRoundedCodeBlock(forGlyphRange glyphRange: NSRange, in textContainer: NSTextContainer, at origin: NSPoint) {
        let firstGlyph = glyphRange.location
        let lastGlyph = max(glyphRange.location, NSMaxRange(glyphRange) - 1)
        guard firstGlyph < numberOfGlyphs else { return }

        var firstLineRange = NSRange(location: 0, length: 0)
        var lastLineRange = NSRange(location: 0, length: 0)
        let firstLine = lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: &firstLineRange)
        let lastLine = lineFragmentRect(forGlyphAt: min(lastGlyph, numberOfGlyphs - 1), effectiveRange: &lastLineRange)
        guard firstLine.width > 0, lastLine.width > 0 else { return }

        let blockRect = MarkdownDecorationGeometry.codeBlockRect(
            firstLineRect: firstLine,
            lastLineRect: lastLine,
            origin: origin,
            containerWidth: textContainer.containerSize.width
        )

        let path = NSBezierPath(roundedRect: blockRect, xRadius: Theme.radiusControl, yRadius: Theme.radiusControl)
        MarkdownStylist.codeBackground.withAlphaComponent(0.94).setFill()
        path.fill()

        MarkdownStylist.codeBorder.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    nonisolated private func drawQuoteBlocks(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownQuoteDepth, in: characterRange) { value, range, _ in
            guard let depth = value as? Int, depth > 0 else { return }
            let quoteGlyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard quoteGlyphRange.length > 0 else { return }

            let lineRect = self.boundingRect(forGlyphRange: quoteGlyphRange, in: textContainer).offsetBy(dx: origin.x, dy: origin.y)
            let backgroundRect = MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: lineRect, depth: depth)
            let barRect = MarkdownDecorationGeometry.quoteBarRect(backgroundRect: backgroundRect, depth: depth)

            MarkdownStylist.codeBackground.withAlphaComponent(0.68).setFill()
            NSBezierPath(roundedRect: backgroundRect, xRadius: Theme.radiusControlCompact, yRadius: Theme.radiusControlCompact).fill()

            MarkdownStylist.blueColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()
        }
    }

    nonisolated private func drawDividerRules(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownDivider, in: characterRange) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let dividerGlyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard dividerGlyphRange.length > 0 else { return }

            let lineRect = self.boundingRect(forGlyphRange: dividerGlyphRange, in: textContainer).offsetBy(dx: origin.x, dy: origin.y)
            let ruleRect = MarkdownDecorationGeometry.dividerRuleRect(lineRect: lineRect)
            MarkdownStylist.ruleColor.setFill()
            ruleRect.fill()
        }
    }

    /// Pure range arithmetic over `textStorage`, touching no main-actor state, so both drawing
    /// entry points can call it without hopping first.
    nonisolated private func visibleGlyphRanges(in glyphRange: NSRange) -> [NSRange] {
        guard let textStorage, glyphRange.length > 0 else { return [glyphRange] }

        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return [glyphRange] }

        var hiddenGlyphRanges: [NSRange] = []
        textStorage.enumerateAttribute(.cadenceMarkdownHidden, in: characterRange) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let hiddenGlyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let clipped = NSIntersectionRange(hiddenGlyphRange, glyphRange)
            if clipped.length > 0 {
                hiddenGlyphRanges.append(clipped)
            }
        }

        guard !hiddenGlyphRanges.isEmpty else { return [glyphRange] }
        return subtract(hiddenGlyphRanges.sorted { $0.location < $1.location }, from: glyphRange)
    }

    nonisolated private func subtract(_ excludedRanges: [NSRange], from fullRange: NSRange) -> [NSRange] {
        var visibleRanges: [NSRange] = []
        var cursor = fullRange.location
        let fullEnd = NSMaxRange(fullRange)

        for excluded in excludedRanges {
            let excludedStart = max(excluded.location, cursor)
            let excludedEnd = min(NSMaxRange(excluded), fullEnd)
            if excludedStart > cursor {
                visibleRanges.append(NSRange(location: cursor, length: excludedStart - cursor))
            }
            cursor = max(cursor, excludedEnd)
        }

        if cursor < fullEnd {
            visibleRanges.append(NSRange(location: cursor, length: fullEnd - cursor))
        }

        return visibleRanges.filter { $0.length > 0 }
    }
}
#endif
