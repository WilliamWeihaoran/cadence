#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class CadenceLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        for visibleRange in visibleGlyphRanges(in: glyphsToShow) {
            super.drawGlyphs(forGlyphRange: visibleRange, at: origin)
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawCodeBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawHighlightBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawTableRows(forGlyphRange: glyphsToShow, at: origin)
        drawTaskEmbeds(forGlyphRange: glyphsToShow, at: origin)
        for visibleRange in visibleGlyphRanges(in: glyphsToShow) {
            super.drawBackground(forGlyphRange: visibleRange, at: origin)
        }
        drawQuoteBlocks(forGlyphRange: glyphsToShow, at: origin)
        drawChecklistBoxes(forGlyphRange: glyphsToShow, at: origin)
        drawDividerRules(forGlyphRange: glyphsToShow, at: origin)
        drawMarkdownImages(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Draws the box that stands in for a hidden `- [x] ` prefix.
    ///
    /// Same shape as the quote bar above: the prefix is styled hidden, so `drawGlyphs` skips it and
    /// this fills the gutter the paragraph style left. It cannot be an `.attachment` the way the iOS
    /// styler does it — AppKit only turns that attribute into a glyph on `NSAttachmentCharacter`.
    private func drawChecklistBoxes(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
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
    func checklistPrefixRange(containing location: Int) -> NSRange? {
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
    func checklistBoxRect(forPrefixCharacterRange range: NSRange, in textContainer: NSTextContainer) -> NSRect? {
        let prefixGlyphRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard prefixGlyphRange.length > 0 else { return nil }
        return MarkdownChecklistBoxDrawing.boxRect(
            prefixRect: boundingRect(forGlyphRange: prefixGlyphRange, in: textContainer)
        )
    }

    private func drawHighlightBackgrounds(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
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
                let highlightRect = rect
                    .offsetBy(dx: origin.x, dy: origin.y)
                    .insetBy(dx: -5, dy: -3)
                guard highlightRect.width > 0, highlightRect.height > 0 else { return }

                let radius = min(8, highlightRect.height / 2)
                let path = NSBezierPath(roundedRect: highlightRect, xRadius: radius, yRadius: radius)
                MarkdownStylist.highlightFillColor.withAlphaComponent(0.38).setFill()
                path.fill()
                MarkdownStylist.highlightBorderColor.withAlphaComponent(0.62).setStroke()
                path.lineWidth = 0.8
                path.stroke()
            }
        }
    }

    private func drawTableRows(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownTableRow, in: characterRange) { value, range, _ in
            guard let style = value as? MarkdownTableRowStyle else { return }
            let rowGlyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard rowGlyphRange.length > 0 else { return }

            let lineRect = self.boundingRect(forGlyphRange: rowGlyphRange, in: textContainer)
                .offsetBy(dx: origin.x, dy: origin.y)
            let rowRect = NSRect(
                x: origin.x + 8,
                y: lineRect.minY - 1,
                width: max(120, textContainer.containerSize.width - 16),
                height: max(12, lineRect.height + 3)
            )

            let fillColor: NSColor
            if style.isHeader {
                fillColor = MarkdownStylist.borderColor.withAlphaComponent(0.78)
            } else if style.isDelimiter {
                fillColor = MarkdownStylist.codeBorder.withAlphaComponent(0.58)
            } else {
                fillColor = (style.lineIndex % 2 == 0 ? MarkdownStylist.codeBackground : Theme.nsSurface).withAlphaComponent(0.72)
            }

            fillColor.setFill()
            NSBezierPath(roundedRect: rowRect, xRadius: style.isHeader ? 9 : 6, yRadius: style.isHeader ? 9 : 6).fill()

            MarkdownStylist.codeBorder.withAlphaComponent(style.isHeader ? 0.75 : 0.45).setStroke()
            let border = NSBezierPath()
            border.lineWidth = 0.7
            border.move(to: NSPoint(x: rowRect.minX + 8, y: rowRect.maxY))
            border.line(to: NSPoint(x: rowRect.maxX - 8, y: rowRect.maxY))
            border.stroke()
        }
    }

    private func drawCodeBackgrounds(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
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

    private func drawRoundedInlineCode(forGlyphRange glyphRange: NSRange, in textContainer: NSTextContainer, at origin: NSPoint) {
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
            let chipRect = glyphBounds
                .offsetBy(dx: origin.x, dy: origin.y)
                .insetBy(dx: -4, dy: -1)
            guard chipRect.width > 0, chipRect.height > 0 else {
                currentGlyph = NSMaxRange(segmentRange)
                continue
            }

            let radius = min(6, chipRect.height / 2)
            let path = NSBezierPath(roundedRect: chipRect, xRadius: radius, yRadius: radius)
            MarkdownStylist.codeBackground.withAlphaComponent(0.94).setFill()
            path.fill()

            MarkdownStylist.codeBorder.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 0.7
            path.stroke()

            currentGlyph = NSMaxRange(segmentRange)
        }
    }

    private func drawRoundedCodeBlock(forGlyphRange glyphRange: NSRange, in textContainer: NSTextContainer, at origin: NSPoint) {
        let firstGlyph = glyphRange.location
        let lastGlyph = max(glyphRange.location, NSMaxRange(glyphRange) - 1)
        guard firstGlyph < numberOfGlyphs else { return }

        var firstLineRange = NSRange(location: 0, length: 0)
        var lastLineRange = NSRange(location: 0, length: 0)
        let firstLine = lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: &firstLineRange)
        let lastLine = lineFragmentRect(forGlyphAt: min(lastGlyph, numberOfGlyphs - 1), effectiveRange: &lastLineRange)
        guard firstLine.width > 0, lastLine.width > 0 else { return }

        let minY = min(firstLine.minY, lastLine.minY)
        let maxY = max(firstLine.maxY, lastLine.maxY)
        let blockRect = NSRect(
            x: firstLine.minX + origin.x + 8,
            y: minY + origin.y + 2,
            width: max(80, textContainer.containerSize.width - 16),
            height: max(18, maxY - minY - 4)
        )

        let path = NSBezierPath(roundedRect: blockRect, xRadius: 10, yRadius: 10)
        MarkdownStylist.codeBackground.withAlphaComponent(0.94).setFill()
        path.fill()

        MarkdownStylist.codeBorder.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    private func drawQuoteBlocks(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownQuoteDepth, in: characterRange) { value, range, _ in
            guard let depth = value as? Int, depth > 0 else { return }
            let quoteGlyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard quoteGlyphRange.length > 0 else { return }

            let lineRect = self.boundingRect(forGlyphRange: quoteGlyphRange, in: textContainer).offsetBy(dx: origin.x, dy: origin.y)
            let levelInset = CGFloat(max(depth - 1, 0)) * 12
            let backgroundRect = NSRect(
                x: lineRect.minX - 14 - levelInset,
                y: lineRect.minY + 1,
                width: lineRect.width + 26 + levelInset,
                height: max(0, lineRect.height - 2)
            )
            let barRect = NSRect(
                x: backgroundRect.minX + 5 + levelInset,
                y: backgroundRect.minY + 2,
                width: 4,
                height: max(0, backgroundRect.height - 4)
            )

            MarkdownStylist.codeBackground.withAlphaComponent(0.68).setFill()
            NSBezierPath(roundedRect: backgroundRect, xRadius: 7, yRadius: 7).fill()

            MarkdownStylist.blueColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawDividerRules(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownDivider, in: characterRange) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let dividerGlyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard dividerGlyphRange.length > 0 else { return }

            let lineRect = self.boundingRect(forGlyphRange: dividerGlyphRange, in: textContainer).offsetBy(dx: origin.x, dy: origin.y)
            let ruleWidth = max(160, min(280, lineRect.width + 140))
            let ruleRect = NSRect(
                x: lineRect.midX - (ruleWidth / 2),
                y: lineRect.midY - 1,
                width: ruleWidth,
                height: 2
            )
            MarkdownStylist.ruleColor.setFill()
            ruleRect.fill()
        }
    }

    private func drawMarkdownImages(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage,
              let textContainer = textContainers.first,
              let textView = textContainer.textView as? CadenceTextView
        else { return }

        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownImage, in: characterRange) { value, range, _ in
            guard let info = value as? MarkdownImageLayoutInfo else { return }
            guard range.location < textStorage.length else { return }

            let glyphIndex = self.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < self.numberOfGlyphs else { return }

            let lineRect = self.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
            let contentWidth = max(1, textView.bounds.width - (textView.textContainerInset.width * 2) - 24)
            let imageSize = info.fittedSize(maxWidth: contentWidth)
            let imageRect = NSRect(
                x: lineRect.minX + 8,
                y: lineRect.minY + 9,
                width: imageSize.width,
                height: imageSize.height
            )

            textView.markdownImageRects[info.id] = imageRect

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

            if textView.selectedMarkdownImageID == info.id {
                MarkdownStylist.blueColor.setStroke()
                let selectionPath = NSBezierPath(roundedRect: imageRect.insetBy(dx: -2, dy: -2), xRadius: 10, yRadius: 10)
                selectionPath.lineWidth = 2
                selectionPath.stroke()
            }

            let handleRect = textView.resizeHandleRect(for: imageRect)
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

    private func drawTaskEmbeds(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let textStorage,
              let textContainer = textContainers.first,
              let textView = textContainer.textView as? CadenceTextView
        else { return }

        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: characterRange) { value, range, _ in
            guard let embed = value as? MarkdownTaskEmbedLayoutInfo,
                  range.location < textStorage.length else { return }

            let glyphIndex = self.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < self.numberOfGlyphs else { return }

            let lineRect = self.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
            let cardRect = MarkdownTaskEmbedDrawing.cardRect(
                forLineRect: lineRect,
                textContainerWidth: textContainer.containerSize.width,
                task: embed.task
            )
            let checkboxRect = MarkdownTaskEmbedDrawing.checkboxRect(in: cardRect)
            textView.markdownTaskEmbedRects[embed.task.id] = MarkdownTaskEmbedHitRects(
                card: cardRect,
                checkbox: checkboxRect.insetBy(dx: -6, dy: -6)
            )
            let hoveredTarget = textView.hoveredMarkdownTaskEmbed?.id == embed.task.id
                ? textView.hoveredMarkdownTaskEmbed?.target
                : nil
            MarkdownTaskEmbedDrawing.drawCard(
                task: embed.task,
                cardRect: cardRect,
                checkboxRect: checkboxRect,
                hoveredTarget: hoveredTarget
            )
        }
    }

    private func visibleGlyphRanges(in glyphRange: NSRange) -> [NSRange] {
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

    private func subtract(_ excludedRanges: [NSRange], from fullRange: NSRange) -> [NSRange] {
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

final class CadenceTextView: NSTextView, NSTextFieldDelegate {
    var markdownImageAssets: [UUID: MarkdownImageRenderAsset] = [:]
    var markdownImageAssetVersions: [UUID: Date] = [:]
    var markdownImageRects: [UUID: NSRect] = [:]
    var markdownTaskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:]
    var markdownTaskEmbedRects: [UUID: MarkdownTaskEmbedHitRects] = [:]
    var hoveredMarkdownTaskEmbed: MarkdownTaskEmbedHover?
    var selectedMarkdownImageID: UUID?
    var referenceSuggestions: [MarkdownReferenceSuggestion] = []
    var tagSuggestions: [MarkdownTagSuggestion] = []
    var onOpenMarkdownReference: ((MarkdownReferenceTarget) -> Void)?
    var onCreateMarkdownTag: ((String) -> MarkdownTagSuggestion?)?
    var onCreateEmbeddedMarkdownTask: ((String) -> MarkdownReferenceSuggestion?)?
    var onToggleEmbeddedMarkdownTask: ((UUID) -> Void)?
    var onToggleEmbeddedMarkdownSubtask: ((UUID, UUID) -> Void)?
    var onRenameEmbeddedMarkdownTask: ((UUID, String) -> Void)?
    var onOpenEmbeddedMarkdownTask: ((UUID) -> Void)?
    var onEditEmbeddedMarkdownTask: ((UUID, MarkdownTaskEmbedField) -> Void)?
    var onHoverEmbeddedMarkdownTask: ((UUID, Bool) -> Void)?
    var onCreateMarkdownImages: (([NSImage], [URL]) -> [MarkdownImageAsset])?
    var onResizeMarkdownImage: ((UUID, CGFloat) -> Void)?

    private var resizingImageID: UUID?
    private var resizeStartX: CGFloat = 0
    private var resizeStartWidth: CGFloat = 0
    private var trackingAreaForHover: NSTrackingArea?
    private var pendingTaskEmbedMouseDown: (id: UUID, target: MarkdownTaskEmbedHitTarget, point: NSPoint, event: NSEvent)?
    private var draggingTaskEmbedID: UUID?
    private var inlineTaskTitleEditor: NSTextField?
    private var inlineTaskTitleTaskID: UUID?
    private var pendingInlineTaskTitleEditID: UUID?
    private var isEndingInlineTaskTitleEdit = false
    private let taskEmbedDragThreshold: CGFloat = 4

    var hasPendingInlineTaskTitleEdit: Bool {
        pendingInlineTaskTitleEditID != nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if MarkdownKeyboardShortcutSupport.handle(event, in: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func performMarkdownFormatCommand(_ command: MarkdownFormatCommand) {
        _ = MarkdownKeyboardShortcutSupport.apply(command, in: self)
    }

    override func paste(_ sender: Any?) {
        if insertImages(from: NSPasteboard.general) {
            return
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasImagePayload(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaForHover {
            removeTrackingArea(trackingAreaForHover)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaForHover = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredTaskEmbed(at: convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        clearHoveredTaskEmbed()
        super.mouseExited(with: event)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if insertImages(from: sender.draggingPasteboard) {
            return true
        }
        return super.performDragOperation(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let inlineTaskTitleEditor,
           !inlineTaskTitleEditor.frame.insetBy(dx: -4, dy: -4).contains(viewPoint) {
            endInlineTaskTitleEdit(commit: true)
        }

        if let hit = imageResizeHit(at: viewPoint) {
            resizingImageID = hit.id
            selectedMarkdownImageID = nil
            resizeStartX = viewPoint.x
            resizeStartWidth = hit.rect.width
            return
        }
        if let hit = imageHit(at: viewPoint) {
            selectedMarkdownImageID = hit.id
            if let range = markdownImageRange(for: hit.id) {
                setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
            }
            needsDisplay = true
            return
        }
        selectedMarkdownImageID = nil

        if let taskHit = taskEmbedHit(at: viewPoint) {
            pendingTaskEmbedMouseDown = (taskHit.id, taskHit.target, viewPoint, event)
            return
        }

        if let hit = checklistMarkerHit(at: viewPoint) {
            if shouldChangeText(in: hit.stateRange, replacementString: hit.replacement) {
                textStorage?.replaceCharacters(in: hit.stateRange, with: hit.replacement)
                didChangeText()
                return
            }
        }

        if let reference = markdownReferenceHit(at: viewPoint) {
            onOpenMarkdownReference?(reference)
            return
        }

        super.mouseDown(with: event)
        snapCaretAwayFromHiddenMarkdown(preferringForward: true)
    }

    override func mouseDragged(with event: NSEvent) {
        if let pendingTaskEmbedMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            let distance = hypot(point.x - pendingTaskEmbedMouseDown.point.x, point.y - pendingTaskEmbedMouseDown.point.y)
            if distance >= taskEmbedDragThreshold,
               beginTaskEmbedDrag(id: pendingTaskEmbedMouseDown.id, event: pendingTaskEmbedMouseDown.event) {
                self.pendingTaskEmbedMouseDown = nil
            }
            return
        }

        guard let resizingImageID else {
            super.mouseDragged(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let newWidth = resizeStartWidth + (point.x - resizeStartX)
        onResizeMarkdownImage?(resizingImageID, newWidth)
        if let current = markdownImageAssets[resizingImageID] {
            let clamped = min(
                max(newWidth, MarkdownImageAssetService.minDisplayWidth),
                MarkdownImageAssetService.maxDisplayWidth
            )
            markdownImageAssets[resizingImageID] = MarkdownImageRenderAsset(
                id: current.id,
                image: current.image,
                displayWidth: clamped,
                pixelSize: current.pixelSize
            )
        }
        if let scrollView = enclosingScrollView {
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                MarkdownStylist.apply(to: self)
                MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
            }
        } else {
            MarkdownStylist.apply(to: self)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if resizingImageID != nil {
            resizingImageID = nil
            return
        }
        if let pendingTaskEmbedMouseDown {
            performTaskEmbedClick(pendingTaskEmbedMouseDown)
            self.pendingTaskEmbedMouseDown = nil
            return
        }
        super.mouseUp(with: event)
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggingTaskEmbedID = nil
    }

    func snapCaretAwayFromHiddenMarkdown(preferringForward: Bool) {
        clampSelectionOutOfHiddenFrontmatter()
        let selection = selectedRange()
        guard selection.length == 0 else { return }
        let snapped = MarkdownHiddenRangeSupport.snappedCaretLocation(
            selection.location,
            in: textStorage,
            preferringForward: preferringForward
        )
        if snapped != selection.location {
            setSelectedRange(NSRange(location: snapped, length: 0))
        }
    }

    /// Pushes any selection that reaches into the hidden frontmatter block down to the first
    /// character of the body.
    ///
    /// The block renders at zero height, so no position inside it is reachable by eye. Anything
    /// that lands there — a click above the first visible line, Cmd+Up, Home on the first line —
    /// gets moved out. For a *ranged* selection only the leading edge moves, which is what keeps
    /// Cmd+A then typing from silently deleting the YAML: the replacement starts at the body.
    func clampSelectionOutOfHiddenFrontmatter() {
        guard let textStorage else { return }
        let bodyStart = MarkdownHiddenRangeSupport.bodyStartLocation(in: textStorage)
        guard bodyStart > 0 else { return }
        let selection = selectedRange()
        guard selection.location < bodyStart else { return }
        let end = max(NSMaxRange(selection), bodyStart)
        setSelectedRange(NSRange(location: bodyStart, length: min(end, textStorage.length) - bodyStart))
    }

    override func selectAll(_ sender: Any?) {
        super.selectAll(sender)
        clampSelectionOutOfHiddenFrontmatter()
    }

    /// `true` when the caret is parked on the first body character of a note whose frontmatter is
    /// hidden — i.e. the only thing behind it is invisible YAML.
    func isCaretAtHiddenFrontmatterBoundary() -> Bool {
        guard let textStorage else { return false }
        let bodyStart = MarkdownHiddenRangeSupport.bodyStartLocation(in: textStorage)
        guard bodyStart > 0 else { return false }
        let selection = selectedRange()
        return selection.length == 0 && selection.location <= bodyStart
    }

    /// Rewrites the title inside every `[[task:UUID|Title]]` reference to one task.
    ///
    /// Which runs to rewrite, and what a title is allowed to look like once it is inside a
    /// reference, are `MarkdownTaskEmbedParser`'s — a platform-free decision the test target can
    /// actually run, and the same one iOS's inline rename asks. This method is only the
    /// `NSTextStorage` mutation half of it.
    func replaceEmbeddedTaskReferenceTitle(id: UUID, title: String) {
        guard let textStorage else { return }
        let displayTitle = MarkdownTaskEmbedParser.sanitizedReferenceTitle(
            title,
            fallback: MarkdownTaskEmbedRenderInfo.untitledTaskTitle
        )
        let current = string as NSString
        var didReplace = false
        for titleRange in MarkdownTaskEmbedParser.referenceTitleRanges(of: id, in: string).reversed() {
            guard current.substring(with: titleRange) != displayTitle,
                  shouldChangeText(in: titleRange, replacementString: displayTitle) else { continue }
            textStorage.replaceCharacters(in: titleRange, with: displayTitle)
            didReplace = true
        }
        guard didReplace else { return }
        didChangeText()
    }

    func deleteMarkdownImageForCommand(backward: Bool) -> Bool {
        if let selectedMarkdownImageID,
           let range = markdownImageRange(for: selectedMarkdownImageID) {
            deleteMarkdownImage(in: range)
            return true
        }

        let selection = selectedRange()
        if selection.length > 0,
           let range = markdownImageRange(intersecting: selection) {
            deleteMarkdownImage(in: NSUnionRange(selection, range))
            return true
        }

        guard selection.length == 0 else { return false }
        let probeLocation = backward ? selection.location - 1 : selection.location
        guard let range = markdownImageRange(containingOrAdjacentTo: probeLocation) else { return false }
        deleteMarkdownImage(in: range)
        return true
    }

    func deleteEmbeddedMarkdownTaskForCommand(backward: Bool) -> Bool {
        let selection = selectedRange()
        if selection.length > 0,
           let range = markdownTaskEmbedRange(intersecting: selection) {
            deleteEmbeddedMarkdownTask(in: NSUnionRange(selection, range))
            return true
        }

        guard selection.length == 0 else { return false }
        let probeLocation = backward ? selection.location - 1 : selection.location
        guard let range = markdownTaskEmbedRange(containingOrAdjacentTo: probeLocation) else { return false }
        deleteEmbeddedMarkdownTask(in: range)
        return true
    }

    func resizeHandleRect(for imageRect: NSRect) -> NSRect {
        NSRect(x: imageRect.maxX - 22, y: imageRect.maxY - 22, width: 18, height: 18)
    }

    func insertMarkdownImages(_ assets: [MarkdownImageAsset]) {
        guard !assets.isEmpty else { return }
        let markdown = assets.map { MarkdownImageAssetService.markdown(for: $0) }.joined(separator: "\n\n")
        let selection = selectedRange()
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(markdown, in: string, selection: selection)
        guard shouldChangeText(in: selection, replacementString: insertion) else { return }
        textStorage?.replaceCharacters(in: selection, with: insertion)
        let location = selection.location + (insertion as NSString).length
        setSelectedRange(NSRange(location: location, length: 0))
        didChangeText()
    }

    func insertMarkdownReference(_ markdown: String) {
        let insertion = inlinePaddedInsertion(markdown)
        let selection = selectedRange()
        guard shouldChangeText(in: selection, replacementString: insertion) else { return }
        textStorage?.replaceCharacters(in: selection, with: insertion)
        let location = selection.location + (insertion as NSString).length
        setSelectedRange(NSRange(location: location, length: 0))
        typingAttributes = MarkdownStylist.baseAttributes
        didChangeText()
    }

    func chooseMarkdownImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self,
                  response == .OK,
                  let assets = self.onCreateMarkdownImages?([], panel.urls),
                  !assets.isEmpty else { return }
            self.insertMarkdownImages(assets)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func imageResizeHit(at point: NSPoint) -> (id: UUID, rect: NSRect)? {
        for (id, rect) in markdownImageRects where resizeHandleRect(for: rect).contains(point) {
            return (id, rect)
        }
        return nil
    }

    private func imageHit(at point: NSPoint) -> (id: UUID, rect: NSRect)? {
        for (id, rect) in markdownImageRects where rect.contains(point) {
            return (id, rect)
        }
        return nil
    }

    private func performTaskEmbedClick(_ pending: (id: UUID, target: MarkdownTaskEmbedHitTarget, point: NSPoint, event: NSEvent)) {
        switch pending.target {
        case .checkbox:
            onToggleEmbeddedMarkdownTask?(pending.id)
        case .subtaskCheckbox(let subtaskID):
            onToggleEmbeddedMarkdownSubtask?(pending.id, subtaskID)
        case .subtaskText:
            onOpenEmbeddedMarkdownTask?(pending.id)
        case .field(let field):
            if field == .title {
                beginInlineTaskTitleEdit(id: pending.id)
            } else {
                onEditEmbeddedMarkdownTask?(pending.id, field)
            }
        case .card:
            onOpenEmbeddedMarkdownTask?(pending.id)
        }
    }

    fileprivate func beginInlineTaskTitleEdit(id: UUID, retryIfNeeded: Bool = true) {
        endInlineTaskTitleEdit(commit: true)
        guard let task = markdownTaskEmbeds[id],
              let titleRect = taskEmbedTitleRect(id: id, task: task) else {
            guard retryIfNeeded else { return }
            DispatchQueue.main.async { [weak self] in
                self?.beginInlineTaskTitleEdit(id: id, retryIfNeeded: false)
            }
            return
        }

        let editorFrame = titleRect.insetBy(dx: -4, dy: -2)
        let editor = NSTextField(frame: editorFrame)
        editor.stringValue = task.title == MarkdownTaskEmbedRenderInfo.untitledTaskTitle ? "" : task.title
        editor.placeholderString = MarkdownTaskEmbedRenderInfo.untitledTaskTitle
        editor.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        editor.textColor = MarkdownStylist.textColor
        editor.backgroundColor = MarkdownStylist.codeBackground
        editor.isBordered = false
        editor.focusRingType = .none
        editor.delegate = self
        editor.target = self
        editor.action = #selector(commitInlineTaskTitleEditor)
        editor.lineBreakMode = .byTruncatingTail
        editor.cell?.sendsActionOnEndEditing = false
        addSubview(editor)
        inlineTaskTitleEditor = editor
        inlineTaskTitleTaskID = id
        window?.makeFirstResponder(editor)
        editor.selectText(nil)
    }

    fileprivate func queueInlineTaskTitleEdit(id: UUID) {
        pendingInlineTaskTitleEditID = id
    }

    fileprivate func performPendingInlineTaskTitleEditIfNeeded() {
        guard let pendingInlineTaskTitleEditID else { return }
        self.pendingInlineTaskTitleEditID = nil
        beginInlineTaskTitleEdit(id: pendingInlineTaskTitleEditID)
    }

    @objc private func commitInlineTaskTitleEditor() {
        endInlineTaskTitleEdit(commit: true)
    }

    private func endInlineTaskTitleEdit(commit: Bool) {
        guard !isEndingInlineTaskTitleEdit,
              let editor = inlineTaskTitleEditor,
              let taskID = inlineTaskTitleTaskID else { return }
        isEndingInlineTaskTitleEdit = true
        let rawTitle = TaskTitleSupport.normalized(editor.stringValue)
        let referenceTitle = TaskTitleSupport.priorityShortcut(in: rawTitle)?.title ?? rawTitle
        editor.delegate = nil
        editor.removeFromSuperview()
        inlineTaskTitleEditor = nil
        inlineTaskTitleTaskID = nil
        if commit {
            onRenameEmbeddedMarkdownTask?(taskID, rawTitle)
            replaceEmbeddedTaskReferenceTitle(id: taskID, title: referenceTitle)
        }
        isEndingInlineTaskTitleEdit = false
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              field === inlineTaskTitleEditor else { return }
        endInlineTaskTitleEdit(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField,
              field === inlineTaskTitleEditor else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            endInlineTaskTitleEdit(commit: true)
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endInlineTaskTitleEdit(commit: false)
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func updateHoveredTaskEmbed(at point: NSPoint) {
        let hit = taskEmbedHit(at: point)
        let next = hit.map { MarkdownTaskEmbedHover(id: $0.id, target: $0.target) }
        guard next != hoveredMarkdownTaskEmbed else { return }
        let didChangeID = next?.id != hoveredMarkdownTaskEmbed?.id
        if didChangeID, let hoveredMarkdownTaskEmbed {
            onHoverEmbeddedMarkdownTask?(hoveredMarkdownTaskEmbed.id, false)
        }
        hoveredMarkdownTaskEmbed = next
        if let next {
            if didChangeID {
                onHoverEmbeddedMarkdownTask?(next.id, true)
            }
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
        needsDisplay = true
    }

    private func clearHoveredTaskEmbed() {
        guard let hoveredMarkdownTaskEmbed else { return }
        onHoverEmbeddedMarkdownTask?(hoveredMarkdownTaskEmbed.id, false)
        self.hoveredMarkdownTaskEmbed = nil
        pendingTaskEmbedMouseDown = nil
        NSCursor.iBeam.set()
        needsDisplay = true
    }

    private func beginTaskEmbedDrag(id: UUID, event: NSEvent) -> Bool {
        guard let rects = markdownTaskEmbedRects[id] else { return false }
        draggingTaskEmbedID = id
        let item = NSPasteboardItem()
        item.setString(TaskDragPayload.string(for: id), forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(rects.card, contents: taskEmbedDragPreview(for: id, rect: rects.card))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        return true
    }

    private func taskEmbedDragPreview(for id: UUID, rect: NSRect) -> NSImage {
        let image = NSImage(size: rect.size)
        image.lockFocus()
        MarkdownStylist.codeBackground.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: rect.size), xRadius: 11, yRadius: 11).fill()
        MarkdownStylist.blueColor.withAlphaComponent(0.48).setStroke()
        let border = NSBezierPath(roundedRect: NSRect(origin: .zero, size: rect.size).insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        border.lineWidth = 1
        border.stroke()

        let title = markdownTaskEmbeds[id]?.title ?? "Task"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: MarkdownStylist.textColor
        ]
        (title as NSString).draw(in: NSRect(x: 16, y: 10, width: max(20, rect.width - 32), height: 20), withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    private func taskEmbedHit(at point: NSPoint) -> (id: UUID, target: MarkdownTaskEmbedHitTarget)? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        var result: (id: UUID, target: MarkdownTaskEmbedHitTarget)?
        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard let embed = value as? MarkdownTaskEmbedLayoutInfo,
                  range.location < textStorage.length else { return }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let cardRect = MarkdownTaskEmbedDrawing.cardRect(
                forLineRect: lineRect,
                textContainerWidth: textContainer.containerSize.width,
                task: embed.task
            )
            let checkboxRect = MarkdownTaskEmbedDrawing.checkboxRect(in: cardRect).insetBy(dx: -6, dy: -6)
            if checkboxRect.contains(point) {
                result = (embed.task.id, .checkbox)
                stop.pointee = true
            } else if let subtaskHit = MarkdownTaskEmbedDrawing.subtaskHit(at: point, task: embed.task, cardRect: cardRect) {
                switch subtaskHit {
                case .checkbox(let subtaskID):
                    result = (embed.task.id, .subtaskCheckbox(subtaskID))
                case .openInspector:
                    result = (embed.task.id, .subtaskText)
                }
                stop.pointee = true
            } else if let field = MarkdownTaskEmbedDrawing.fieldHit(at: point, task: embed.task, cardRect: cardRect) {
                result = (embed.task.id, .field(field))
                stop.pointee = true
            } else if cardRect.contains(point) {
                result = (embed.task.id, .card)
                stop.pointee = true
            }
        }
        return result
    }

    private func taskEmbedTitleRect(id: UUID, task: MarkdownTaskEmbedRenderInfo) -> NSRect? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        var result: NSRect?
        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard let embed = value as? MarkdownTaskEmbedLayoutInfo,
                  embed.task.id == id,
                  range.location < textStorage.length else { return }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let cardRect = MarkdownTaskEmbedDrawing.cardRect(
                forLineRect: lineRect,
                textContainerWidth: textContainer.containerSize.width,
                task: task
            )
            result = MarkdownTaskEmbedDrawing.titleRect(task: task, cardRect: cardRect)
            stop.pointee = true
        }
        return result
    }

    /// The checklist box under `point`, if any, together with the one-character edit that flips it.
    ///
    /// Both spellings toggle through `MarkdownChecklistSupport`, which already answers for each; only
    /// *where the box is* differs. A legacy `○` / `✓` is a real glyph, so its own bounding rect is the
    /// target. A GitHub `- [x] ` prefix is hidden and drawn, so the target is the rect the layout
    /// manager drew — asking the hidden run for its bounds would give a sliver at the wrong place.
    private func checklistMarkerHit(at point: NSPoint) -> (stateRange: NSRange, replacement: String)? {
        guard let layoutManager = layoutManager as? CadenceLayoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let nsString = string as NSString
        guard characterIndex < nsString.length else { return nil }

        let lineRange = nsString.lineRange(for: NSRange(location: characterIndex, length: 0))
        let line = nsString.substring(with: NSRange(location: lineRange.location, length: min(lineRange.length, nsString.length - lineRange.location)))
            .trimmingCharacters(in: .newlines)
        guard let checklist = MarkdownChecklistSupport.lineInfo(in: line),
              let toggle = MarkdownChecklistSupport.toggledState(in: line) else {
            return nil
        }

        let stateRange = NSRange(location: lineRange.location + toggle.stateRange.location, length: toggle.stateRange.length)
        guard NSMaxRange(stateRange) <= nsString.length else { return nil }

        let boxRect: NSRect?
        switch checklist.syntax {
        case .legacy:
            let markerRange = NSRange(location: lineRange.location + checklist.stateRange.location, length: checklist.stateRange.length)
            let markerGlyphRange = layoutManager.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
            boxRect = markerGlyphRange.length > 0
                ? layoutManager.boundingRect(forGlyphRange: markerGlyphRange, in: textContainer)
                : nil
        case .github:
            let prefixRange = NSRange(location: lineRange.location + checklist.markerRange.location, length: checklist.markerRange.length)
            boxRect = layoutManager.checklistBoxRect(forPrefixCharacterRange: prefixRange, in: textContainer)
        }

        guard let boxRect else { return nil }
        let target = boxRect
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            .insetBy(dx: -6, dy: -5)
        guard target.contains(point) else { return nil }
        return (stateRange, toggle.replacement)
    }

    private func markdownImageRange(for id: UUID) -> NSRange? {
        guard let textStorage else { return nil }
        var result: NSRange?
        textStorage.enumerateAttribute(.cadenceMarkdownImage, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard let info = value as? MarkdownImageLayoutInfo, info.id == id else { return }
            result = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: range, in: string)
            stop.pointee = true
        }
        return result
    }

    private func markdownImageRange(intersecting selection: NSRange) -> NSRange? {
        guard let textStorage else { return nil }
        var result: NSRange?
        textStorage.enumerateAttribute(.cadenceMarkdownImage, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard value is MarkdownImageLayoutInfo,
                  NSIntersectionRange(range, selection).length > 0 else { return }
            result = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: range, in: string)
            stop.pointee = true
        }
        return result
    }

    private func markdownImageRange(containingOrAdjacentTo location: Int) -> NSRange? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let clamped = min(max(location, 0), textStorage.length - 1)
        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        if textStorage.attribute(.cadenceMarkdownImage, at: clamped, effectiveRange: &effectiveRange) is MarkdownImageLayoutInfo,
           effectiveRange.location != NSNotFound {
            return MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: effectiveRange, in: string)
        }
        return nil
    }

    private func markdownTaskEmbedRange(intersecting selection: NSRange) -> NSRange? {
        guard let textStorage else { return nil }
        var result: NSRange?
        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard value is MarkdownTaskEmbedLayoutInfo,
                  NSIntersectionRange(range, selection).length > 0 else { return }
            result = MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: range, in: string)
            stop.pointee = true
        }
        return result
    }

    private func markdownTaskEmbedRange(containingOrAdjacentTo location: Int) -> NSRange? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let candidates = [location, location - 1, location + 1]
        for candidate in candidates {
            guard candidate >= 0, candidate < textStorage.length else { continue }
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            if textStorage.attribute(.cadenceMarkdownTaskEmbed, at: candidate, effectiveRange: &effectiveRange) is MarkdownTaskEmbedLayoutInfo,
               effectiveRange.location != NSNotFound {
                return MarkdownRenderedBlockDeletionSupport.expandedDeletionRange(for: effectiveRange, in: string)
            }
        }
        return nil
    }

    private func markdownReferenceHit(at point: NSPoint) -> MarkdownReferenceTarget? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.cadenceMarkdownReference, at: characterIndex, effectiveRange: nil) as? MarkdownReferenceTarget
    }

    private func deleteMarkdownImage(in rawRange: NSRange) {
        let range = NSIntersectionRange(rawRange, NSRange(location: 0, length: (string as NSString).length))
        guard range.length > 0,
              shouldChangeText(in: range, replacementString: "") else { return }
        selectedMarkdownImageID = nil
        textStorage?.replaceCharacters(in: range, with: "")
        setSelectedRange(NSRange(location: range.location, length: 0))
        typingAttributes = MarkdownStylist.baseAttributes
        didChangeText()
    }

    private func deleteEmbeddedMarkdownTask(in rawRange: NSRange) {
        let range = NSIntersectionRange(rawRange, NSRange(location: 0, length: (string as NSString).length))
        guard range.length > 0,
              shouldChangeText(in: range, replacementString: "") else { return }
        markdownTaskEmbedRects.removeAll()
        textStorage?.replaceCharacters(in: range, with: "")
        setSelectedRange(NSRange(location: range.location, length: 0))
        typingAttributes = MarkdownStylist.baseAttributes
        didChangeText()
    }

    private func insertImages(from pasteboard: NSPasteboard) -> Bool {
        let urls = MarkdownImageAssetService.imageFileURLs(from: pasteboard)
        let images = urls.isEmpty ? MarkdownImageAssetService.images(from: pasteboard) : []
        guard !urls.isEmpty || !images.isEmpty,
              let assets = onCreateMarkdownImages?(images, urls),
              !assets.isEmpty
        else { return false }
        insertMarkdownImages(assets)
        return true
    }

    private func hasImagePayload(_ pasteboard: NSPasteboard) -> Bool {
        !MarkdownImageAssetService.imageFileURLs(from: pasteboard).isEmpty ||
            !MarkdownImageAssetService.images(from: pasteboard).isEmpty
    }

    private func inlinePaddedInsertion(_ markdown: String) -> String {
        let nsText = string as NSString
        let selection = selectedRange()
        let needsLeadingSpace: Bool
        if selection.location == 0 {
            needsLeadingSpace = false
        } else {
            let previous = nsText.substring(with: NSRange(location: max(0, selection.location - 1), length: 1))
            needsLeadingSpace = !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let needsTrailingSpace: Bool
        if NSMaxRange(selection) >= nsText.length {
            needsTrailingSpace = false
        } else {
            let next = nsText.substring(with: NSRange(location: NSMaxRange(selection), length: 1))
            needsTrailingSpace = !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return (needsLeadingSpace ? " " : "") + markdown + (needsTrailingSpace ? " " : "")
    }
}

final class MarkdownEditorCoordinator: NSObject, NSTextViewDelegate {
    private var parent: MarkdownEditorView
    private let slashCommandPicker = MarkdownSlashCommandPickerController()
    private let referencePicker = MarkdownReferencePickerController()
    private let tagPicker = MarkdownTagPickerController()
    private weak var reportedTextView: CadenceTextView?
    private weak var pendingSlashCommandTextView: NSTextView?
    private weak var pendingReferenceTextView: NSTextView?
    private weak var pendingTagTextView: NSTextView?
    private var isApplyingEditorMutations = false
    private var slashCommandUpdateIsScheduled = false
    private var referenceUpdateIsScheduled = false
    private var tagUpdateIsScheduled = false

    init(parent: MarkdownEditorView) {
        self.parent = parent
    }

    func update(parent: MarkdownEditorView) {
        self.parent = parent
    }

    func notifyTextViewIfNeeded(_ textView: CadenceTextView, onChange: @escaping (CadenceTextView) -> Void) {
        guard reportedTextView !== textView else { return }
        reportedTextView = textView
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView, self.reportedTextView === textView else { return }
            onChange(textView)
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }

        // Transforms and normalization now close their edits with `didChangeText()`, which posts
        // this same notification back. The nested pass would only redo work the rest of this one
        // is about to do with the final text, so it is skipped rather than allowed to recurse.
        guard !isApplyingEditorMutations else { return }
        isApplyingEditorMutations = true
        applyInputTransforms(to: textView)
        normalizeMarkdownListPrefixes(in: textView)
        normalizeOrderedListMarkers(in: textView)
        isApplyingEditorMutations = false

        parent.text = textView.string
        applyStyling(to: textView, in: textView.enclosingScrollView)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        scheduleSlashCommandPickerUpdate(for: textView)
        scheduleReferencePickerUpdate(for: textView)
        scheduleTagPickerUpdate(for: textView)
    }

    /// Catches every way the caret can reach the hidden frontmatter block that does not route
    /// through `doCommandBy` — clicking above the first visible line, Cmd+Up, Home, page-up,
    /// find-and-select. Deliberately frontmatter-only: it must not re-introduce the
    /// snap-on-every-selection-change behaviour that used to eject carets resting at the leading
    /// edge of an inline marker.
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? CadenceTextView else { return }
        textView.clampSelectionOutOfHiddenFrontmatter()
    }

    func textDidBeginEditing(_ notification: Notification) {
        parent.onEditingChanged(true)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
            parent.onEditingChanged(false)
            return
        }
        applyStyling(to: textView, in: textView.enclosingScrollView)
        parent.onEditingChanged(false)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if let handled = handleTagPickerCommand(commandSelector, in: textView) { return handled }
        if let handled = handleReferencePickerCommand(commandSelector, in: textView) { return handled }
        if let handled = handleSlashCommandPickerCommand(commandSelector, in: textView) { return handled }
        if let handled = handleCaretMovementCommand(commandSelector, in: textView) { return handled }
        if let handled = handleIndentationCommand(commandSelector, in: textView) { return handled }
        if let handled = handleDeletionCommand(commandSelector, in: textView) { return handled }
        return handleNewlineCommand(commandSelector, in: textView)
    }
}

// MARK: - Command Routing

extension MarkdownEditorCoordinator {
    private func handleTagPickerCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        guard tagPicker.isShown else { return nil }
        if tagPicker.isShown {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                tagPicker.moveSelection(delta: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                tagPicker.moveSelection(delta: 1)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                tagPicker.close()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return tagPicker.applyHighlighted { [weak self] choice, context in
                    self?.applyTagCompletion(choice, context: context, in: textView)
                }
            }
        }
        return nil
    }

    private func handleReferencePickerCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        guard referencePicker.isShown else { return nil }
        if referencePicker.isShown {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                referencePicker.moveSelection(delta: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                referencePicker.moveSelection(delta: 1)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                referencePicker.close()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return referencePicker.applyHighlighted { [weak self] suggestion, context in
                    self?.applyReferenceSuggestion(suggestion, context: context, in: textView)
                }
            }
        }
        return nil
    }

    private func handleSlashCommandPickerCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        guard slashCommandPicker.isShown else { return nil }
        if slashCommandPicker.isShown {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                slashCommandPicker.moveSelection(delta: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                slashCommandPicker.moveSelection(delta: 1)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                slashCommandPicker.close()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return slashCommandPicker.applyHighlighted { [weak self] command, context in
                    self?.applySlashCommand(command, context: context, in: textView)
                }
            }
        }
        return nil
    }

    private func handleCaretMovementCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        if commandSelector == #selector(NSResponder.moveLeft(_:)) {
            return moveCaret(in: textView, forward: false, extendSelection: false)
        }

        if commandSelector == #selector(NSResponder.moveRight(_:)) {
            return moveCaret(in: textView, forward: true, extendSelection: false)
        }

        if commandSelector == #selector(NSResponder.moveLeftAndModifySelection(_:)) {
            return moveCaret(in: textView, forward: false, extendSelection: true)
        }

        if commandSelector == #selector(NSResponder.moveRightAndModifySelection(_:)) {
            return moveCaret(in: textView, forward: true, extendSelection: true)
        }
        return nil
    }

    private func handleIndentationCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return adjustIndentation(in: textView, increase: true)
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return adjustIndentation(in: textView, increase: false)
        }
        return nil
    }

    private func handleDeletionCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool? {
        if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            // At the top of the body there is nothing behind the caret but the hidden frontmatter
            // block. Swallow the keystroke instead of letting it chew invisible characters — the
            // user would see nothing happen while the block quietly came apart.
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.isCaretAtHiddenFrontmatterBoundary() {
                return true
            }
            if slashCommandPicker.isShown {
                scheduleSlashCommandPickerUpdate(for: textView)
            }
            if tagPicker.isShown {
                scheduleTagPickerUpdate(for: textView)
            }
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteMarkdownImageForCommand(backward: true) {
                return true
            }
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteEmbeddedMarkdownTaskForCommand(backward: true) {
                return true
            }
            return deleteBackwardFromListPrefix(in: textView)
        }

        if commandSelector == #selector(NSResponder.deleteForward(_:)) {
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteMarkdownImageForCommand(backward: false) {
                return true
            }
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteEmbeddedMarkdownTaskForCommand(backward: false) {
                return true
            }
            return false
        }
        return nil
    }

    private func handleNewlineCommand(_ commandSelector: Selector, in textView: NSTextView) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        let rawLine = nsText.substring(with: NSRange(location: lineRange.location,
                                                     length: min(lineRange.length, nsText.length - lineRange.location)))
        let line = rawLine.trimmingCharacters(in: .newlines)

        if createEmbeddedTaskIfNeeded(in: textView, lineRange: lineRange, line: line) {
            return true
        }

        guard let mutation = MarkdownLineBreakSupport.mutation(in: textView.string, selection: selection) else { return false }
        guard textView.shouldChangeText(in: mutation.replacementRange, replacementString: mutation.replacement) else { return false }
        textView.textStorage?.replaceCharacters(in: mutation.replacementRange, with: mutation.replacement)
        textView.setSelectedRange(mutation.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }
}

// MARK: - Caret & Indentation

extension MarkdownEditorCoordinator {
    private func moveCaret(in textView: NSTextView, forward: Bool, extendSelection: Bool) -> Bool {
        let selection = textView.selectedRange()
        let storage = textView.textStorage

        if extendSelection {
            let anchor = forward ? selection.location : selection.location + selection.length
            let movingEdge = forward ? selection.location + selection.length : selection.location
            let next = MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: movingEdge, movingForward: forward, in: storage)
            let newLocation = min(anchor, next)
            let newLength = abs(next - anchor)
            textView.setSelectedRange(NSRange(location: newLocation, length: newLength))
            return true
        }

        let baseLocation = selection.length > 0 ? (forward ? selection.location + selection.length : selection.location) : selection.location
        let next = MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: baseLocation, movingForward: forward, in: storage)
        textView.setSelectedRange(NSRange(location: next, length: 0))
        return true
    }

    private func adjustIndentation(in textView: NSTextView, increase: Bool) -> Bool {
        guard let result = MarkdownListSupport.adjustedListIndentation(
            in: textView.string,
            selection: textView.selectedRange(),
            increase: increase
        ) else { return false }

        guard textView.shouldChangeText(in: result.replacementRange, replacementString: result.replacement) else { return true }
        textView.textStorage?.replaceCharacters(in: result.replacementRange, with: result.replacement)
        textView.setSelectedRange(result.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private func deleteBackwardFromListPrefix(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        guard let mutation = MarkdownBackspaceSupport.listPrefixMutation(in: textView.string, selection: selection) else {
            return false
        }

        guard textView.shouldChangeText(in: mutation.replacementRange, replacementString: mutation.replacement) else { return true }
        textView.textStorage?.replaceCharacters(in: mutation.replacementRange, with: mutation.replacement)
        textView.setSelectedRange(mutation.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }
}

// MARK: - Input Transforms & Embedded Tasks

extension MarkdownEditorCoordinator {
    private func applyInputTransforms(to textView: NSTextView) {
        let nsText = textView.string as NSString
        let cursor = textView.selectedRange().location
        guard cursor > 0 else { return }

        if cursor >= 4 {
            let range = NSRange(location: cursor - 4, length: 4)
            let snippet = nsText.substring(with: range)
            if snippet == "( ) ",
               MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil,
               createUntitledEmbeddedTask(fromTriggerRange: range, in: textView) {
                return
            }
        }

        if cursor >= 3 {
            let range = NSRange(location: cursor - 3, length: 3)
            let snippet = nsText.substring(with: range)
            if snippet == "() ",
               MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil,
               createUntitledEmbeddedTask(fromTriggerRange: range, in: textView) {
                return
            }
        }

        if let mutation = MarkdownTypingTransformSupport.mutation(in: textView.string, cursor: cursor) {
            replaceText(
                in: textView,
                range: mutation.replacementRange,
                with: mutation.replacement,
                selection: mutation.selection
            )
            return
        }
    }

    private func createUntitledEmbeddedTask(fromTriggerRange range: NSRange, in textView: NSTextView) -> Bool {
        guard let cadenceTextView = textView as? CadenceTextView,
              let suggestion = cadenceTextView.onCreateEmbeddedMarkdownTask?(MarkdownTaskEmbedRenderInfo.untitledTaskTitle),
              suggestion.kind == .task,
              MarkdownTaskEmbedParser.standaloneTaskReference(in: suggestion.markdown) != nil else {
            return false
        }

        guard textView.shouldChangeText(in: range, replacementString: suggestion.markdown) else {
            return true
        }
        textView.textStorage?.replaceCharacters(in: range, with: suggestion.markdown)
        if let titleRange = MarkdownTaskEmbedParser.referenceTitleRange(in: suggestion.markdown, lineStart: range.location) {
            textView.setSelectedRange(titleRange)
        } else {
            textView.setSelectedRange(NSRange(location: range.location + (suggestion.markdown as NSString).length, length: 0))
        }
        cadenceTextView.queueInlineTaskTitleEdit(id: suggestion.targetID)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private func createEmbeddedTaskIfNeeded(in textView: NSTextView, lineRange: NSRange, line: String) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0,
              selection.location >= lineRange.location + (line as NSString).length,
              let cadenceTextView = textView as? CadenceTextView,
              let title = MarkdownTaskEmbedParser.draftTitle(in: line),
              let suggestion = cadenceTextView.onCreateEmbeddedMarkdownTask?(title),
              suggestion.kind == .task,
              MarkdownTaskEmbedParser.standaloneTaskReference(in: suggestion.markdown) != nil else {
            return false
        }

        let contentRange = NSRange(location: lineRange.location, length: (line as NSString).length)
        let replacement = suggestion.markdown + "\n"
        guard textView.shouldChangeText(in: contentRange, replacementString: replacement) else { return true }
        textView.textStorage?.replaceCharacters(in: contentRange, with: replacement)
        textView.setSelectedRange(NSRange(location: contentRange.location + (replacement as NSString).length, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    /// `shouldChangeText` opens an undo group and text-checking state that `didChangeText` is
    /// contractually required to close — leaving it open here left the typing-transform hot path
    /// accumulating unclosed groups.
    private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String, selection: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.setSelectedRange(selection)
        textView.didChangeText()
    }
}

// MARK: - Styling

extension MarkdownEditorCoordinator {
    private func applyStyling(to textView: NSTextView, in scrollView: NSScrollView?) {
        if let scrollView {
            MarkdownEditorScrollSupport.preservingScrollPosition(in: scrollView) {
                MarkdownStylist.apply(to: textView)
            }
        } else {
            MarkdownStylist.apply(to: textView)
        }

        if let cadenceTextView = textView as? CadenceTextView {
            cadenceTextView.snapCaretAwayFromHiddenMarkdown(preferringForward: true)
        }
        if let scrollView {
            MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        }
        if let cadenceTextView = textView as? CadenceTextView {
            cadenceTextView.performPendingInlineTaskTitleEditIfNeeded()
        }
    }
}

// MARK: - List Normalization

extension MarkdownEditorCoordinator {
    private func normalizeMarkdownListPrefixes(in textView: NSTextView) {
        apply(
            MarkdownListSupport.normalizedMarkdownListPrefixes(in: textView.string, selection: textView.selectedRange()),
            to: textView
        )
    }

    private func normalizeOrderedListMarkers(in textView: NSTextView) {
        apply(
            MarkdownListSupport.normalizedOrderedListMarkers(in: textView.string, selection: textView.selectedRange()),
            to: textView
        )
    }

    /// Applies a whole-document normalization through the AppKit text-mutation contract.
    ///
    /// Both normalizers run from `textDidChange` — *after* NSTextView has closed the undo group
    /// for the keystroke that triggered them. Assigning `textView.string` there rewrites text the
    /// registered undo record already describes by offset, so Cmd+Z would replay that record
    /// against text that had since shifted underneath it. Going through
    /// `shouldChangeText` / `replaceCharacters` / `didChangeText` registers the rewrite as its own
    /// undoable edit instead.
    private func apply(_ result: MarkdownListNormalizationResult, to textView: NSTextView) {
        let originalText = textView.string
        guard result.text != originalText else { return }

        let fullRange = NSRange(location: 0, length: (originalText as NSString).length)
        guard textView.shouldChangeText(in: fullRange, replacementString: result.text) else { return }
        textView.textStorage?.replaceCharacters(in: fullRange, with: result.text)
        textView.setSelectedRange(result.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
    }
}

// MARK: - Pickers

extension MarkdownEditorCoordinator {
    private func updateSlashCommandPicker(for textView: NSTextView) {
        slashCommandPicker.update(
            for: textView,
            context: currentSlashCommandContext(in: textView),
            commands: parent.slashCommands
        ) { [weak self] command, context in
            self?.applySlashCommand(command, context: context, in: textView)
        }
    }

    private func scheduleSlashCommandPickerUpdate(for textView: NSTextView) {
        pendingSlashCommandTextView = textView
        guard !slashCommandUpdateIsScheduled else { return }
        slashCommandUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            slashCommandUpdateIsScheduled = false
            guard let textView = pendingSlashCommandTextView else {
                slashCommandPicker.close()
                return
            }
            pendingSlashCommandTextView = nil
            updateSlashCommandPicker(for: textView)
        }
    }

    private func updateReferencePicker(for textView: NSTextView) {
        let context = currentReferenceCompletionContext(in: textView)
        if context != nil {
            slashCommandPicker.close()
            tagPicker.close()
        }
        referencePicker.update(
            for: textView,
            context: context,
            suggestions: parent.referenceSuggestions
        ) { [weak self] suggestion, context in
            self?.applyReferenceSuggestion(suggestion, context: context, in: textView)
        }
    }

    private func updateTagPicker(for textView: NSTextView) {
        let context = currentTagCompletionContext(in: textView)
        if context != nil {
            slashCommandPicker.close()
            referencePicker.close()
        }
        tagPicker.update(
            for: textView,
            context: context,
            suggestions: parent.tagSuggestions
        ) { [weak self] choice, context in
            self?.applyTagCompletion(choice, context: context, in: textView)
        }
    }

    private func scheduleTagPickerUpdate(for textView: NSTextView) {
        pendingTagTextView = textView
        guard !tagUpdateIsScheduled else { return }
        tagUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            tagUpdateIsScheduled = false
            guard let textView = pendingTagTextView else {
                tagPicker.close()
                return
            }
            pendingTagTextView = nil
            updateTagPicker(for: textView)
        }
    }

    private func scheduleReferencePickerUpdate(for textView: NSTextView) {
        pendingReferenceTextView = textView
        guard !referenceUpdateIsScheduled else { return }
        referenceUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            referenceUpdateIsScheduled = false
            guard let textView = pendingReferenceTextView else {
                referencePicker.close()
                return
            }
            pendingReferenceTextView = nil
            updateReferencePicker(for: textView)
        }
    }

    private func currentSlashCommandContext(in textView: NSTextView) -> MarkdownSlashCommandContext? {
        MarkdownSlashCommandTokenSupport.context(in: textView.string, selection: textView.selectedRange())
    }

    private func applySlashCommand(_ command: MarkdownSlashCommand, context: MarkdownSlashCommandContext, in textView: NSTextView) {
        let mutation = MarkdownSlashCommandMutationSupport.mutation(for: command, context: context)
        guard textView.shouldChangeText(in: mutation.replacementRange, replacementString: mutation.replacement) else {
            slashCommandPicker.close()
            return
        }

        textView.textStorage?.replaceCharacters(in: mutation.replacementRange, with: mutation.replacement)
        textView.setSelectedRange(mutation.selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()

        if mutation.followUp == .chooseImage {
            DispatchQueue.main.async { [parent] in
                if let cadenceTextView = textView as? CadenceTextView {
                    cadenceTextView.chooseMarkdownImages()
                } else {
                    parent.onChooseImages()
                }
            }
        }
        slashCommandPicker.close()
    }

    private func currentReferenceCompletionContext(in textView: NSTextView) -> MarkdownReferenceCompletionContext? {
        MarkdownReferenceCompletionSupport.context(in: textView.string, selection: textView.selectedRange())
    }

    private func applyReferenceSuggestion(_ suggestion: MarkdownReferenceSuggestion, context: MarkdownReferenceCompletionContext, in textView: NSTextView) {
        guard textView.shouldChangeText(in: context.range, replacementString: suggestion.markdown) else {
            referencePicker.close()
            return
        }
        textView.textStorage?.replaceCharacters(in: context.range, with: suggestion.markdown)
        textView.setSelectedRange(NSRange(location: context.range.location + (suggestion.markdown as NSString).length, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        referencePicker.close()
    }

    private func currentTagCompletionContext(in textView: NSTextView) -> MarkdownTagCompletionContext? {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return nil }
        let nsText = textView.string as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        return MarkdownTagCompletionTokenSupport.token(in: nsText, cursor: safeCursor)
    }

    private func applyTagCompletion(_ choice: MarkdownTagPickerChoice, context: MarkdownTagCompletionContext, in textView: NSTextView) {
        let suggestion: MarkdownTagSuggestion
        switch choice {
        case .existing(let existing):
            if existing.isArchived, let restored = parent.onCreateTag(existing.name) {
                suggestion = restored
            } else {
                suggestion = existing
            }
        case .create(let name):
            guard let created = parent.onCreateTag(name) else {
                tagPicker.close()
                return
            }
            suggestion = created
        }

        let replacement = "#\(suggestion.slug)"
        guard textView.shouldChangeText(in: context.range, replacementString: replacement) else {
            tagPicker.close()
            return
        }
        textView.textStorage?.replaceCharacters(in: context.range, with: replacement)
        textView.setSelectedRange(NSRange(location: context.range.location + (replacement as NSString).length, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        tagPicker.close()
    }
}
#endif
