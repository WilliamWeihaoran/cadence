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
        drawDividerRules(forGlyphRange: glyphsToShow, at: origin)
        drawMarkdownImages(forGlyphRange: glyphsToShow, at: origin)
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
                fillColor = NSColor(hex: "#24304a").withAlphaComponent(0.78)
            } else if style.isDelimiter {
                fillColor = NSColor(hex: "#38405c").withAlphaComponent(0.58)
            } else {
                fillColor = (style.lineIndex % 2 == 0 ? NSColor(hex: "#171d2a") : NSColor(hex: "#141923")).withAlphaComponent(0.72)
            }

            fillColor.setFill()
            NSBezierPath(roundedRect: rowRect, xRadius: style.isHeader ? 9 : 6, yRadius: style.isHeader ? 9 : 6).fill()

            NSColor(hex: "#3b4668").withAlphaComponent(style.isHeader ? 0.75 : 0.45).setStroke()
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
        let selectedRange = NSRange(location: NSNotFound, length: 0)
        enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: selectedRange, in: textContainer) { rect, _ in
            let chipRect = rect
                .offsetBy(dx: origin.x, dy: origin.y)
                .insetBy(dx: -5, dy: -2)
            guard chipRect.width > 0, chipRect.height > 0 else { return }

            let radius = min(7, chipRect.height / 2)
            let path = NSBezierPath(roundedRect: chipRect, xRadius: radius, yRadius: radius)
            MarkdownStylist.codeBackground.withAlphaComponent(0.94).setFill()
            path.fill()

            MarkdownStylist.codeBorder.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 0.7
            path.stroke()
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

            NSColor(hex: "#13243d").withAlphaComponent(0.68).setFill()
            NSBezierPath(roundedRect: backgroundRect, xRadius: 7, yRadius: 7).fill()

            NSColor(hex: "#4a9eff").withAlphaComponent(0.85).setFill()
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
            NSColor(hex: "#50597a").setFill()
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

            NSColor(hex: "#151a24").setFill()
            NSBezierPath(roundedRect: imageRect.insetBy(dx: -1, dy: -1), xRadius: 9, yRadius: 9).fill()

            if let image = info.image {
                image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                NSColor(hex: "#1d2534").setFill()
                NSBezierPath(roundedRect: imageRect, xRadius: 8, yRadius: 8).fill()
                let label = "Missing image"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: MarkdownStylist.dimColor
                ]
                label.draw(at: NSPoint(x: imageRect.minX + 14, y: imageRect.midY - 8), withAttributes: attrs)
            }

            if textView.selectedMarkdownImageID == info.id {
                NSColor(hex: "#4a9eff").setStroke()
                let selectionPath = NSBezierPath(roundedRect: imageRect.insetBy(dx: -2, dy: -2), xRadius: 10, yRadius: 10)
                selectionPath.lineWidth = 2
                selectionPath.stroke()
            }

            let handleRect = textView.resizeHandleRect(for: imageRect)
            NSColor(hex: "#0f1117").withAlphaComponent(0.86).setFill()
            NSBezierPath(roundedRect: handleRect, xRadius: 5, yRadius: 5).fill()
            NSColor(hex: "#4a9eff").setStroke()
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
            MarkdownTaskEmbedDrawing.drawCard(
                task: embed.task,
                cardRect: cardRect,
                checkboxRect: checkboxRect,
                isHovered: textView.hoveredMarkdownTaskEmbedID == embed.task.id
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

private enum MarkdownTaskEmbedDrawing {
    private struct Chip {
        let label: String
        let color: NSColor
        let field: MarkdownTaskEmbedField
    }

    private struct ChipRect {
        let field: MarkdownTaskEmbedField
        let rect: NSRect
    }

    static func cardRect(
        forLineRect lineRect: NSRect,
        textContainerWidth: CGFloat,
        task: MarkdownTaskEmbedRenderInfo
    ) -> NSRect {
        NSRect(
            x: lineRect.minX + 8,
            y: lineRect.minY + 6,
            width: max(160, textContainerWidth - 16),
            height: task.cardHeight
        )
    }

    static func checkboxRect(in cardRect: NSRect) -> NSRect {
        NSRect(x: cardRect.minX + 15, y: cardRect.midY - 9, width: 18, height: 18)
    }

    static func fieldHit(at point: NSPoint, task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect) -> MarkdownTaskEmbedField? {
        let layout = fieldRects(task: task, cardRect: cardRect)
        if layout.title.insetBy(dx: -3, dy: -3).contains(point) {
            return .title
        }
        return layout.chips.first(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(point) })?.field
    }

    static func subtaskHit(
        at point: NSPoint,
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect
    ) -> MarkdownTaskEmbedSubtaskHitTarget? {
        MarkdownTaskEmbedSubtaskHitTesting.hit(at: point, in: subtaskRects(task: task, cardRect: cardRect))
    }

    static func drawCard(task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect, checkboxRect: NSRect, isHovered: Bool) {
        let radius: CGFloat = 11
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
        (isHovered ? NSColor(hex: "#182236") : NSColor(hex: "#141b26"))
            .withAlphaComponent(0.98)
            .setFill()
        cardPath.fill()

        (isHovered ? MarkdownStylist.blueColor : NSColor(hex: "#33435f"))
            .withAlphaComponent(isHovered ? 0.58 : 0.82)
            .setStroke()
        cardPath.lineWidth = isHovered ? 1.35 : 0.9
        cardPath.stroke()

        if isHovered {
            let glowPath = NSBezierPath(roundedRect: cardRect.insetBy(dx: -1, dy: -1), xRadius: radius + 1, yRadius: radius + 1)
            MarkdownStylist.blueColor.withAlphaComponent(0.13).setStroke()
            glowPath.lineWidth = 3
            glowPath.stroke()
        }

        let stripRect = NSRect(x: cardRect.minX, y: cardRect.minY + 5, width: 4, height: cardRect.height - 10)
        let stripColor = task.isMissing ? MarkdownStylist.dimColor : priorityColor(task.priorityRaw, fallback: task.containerColorHex)
        stripColor.withAlphaComponent(task.isMissing ? 0.48 : 0.9).setFill()
        NSBezierPath(roundedRect: stripRect, xRadius: 2, yRadius: 2).fill()

        drawCheckbox(task: task, rect: checkboxRect)

        let layout = fieldRects(task: task, cardRect: cardRect)
        drawTitle(task: task, in: layout.title)
        let chips = displayChips(for: task)
        for chipRect in layout.chips {
            guard let chip = chips.first(where: { $0.field == chipRect.field }) else { continue }
            drawChip(label: chip.label, color: chip.color, rect: chipRect.rect)
        }
        drawSubtasks(task: task, cardRect: cardRect)
    }

    private static func drawCheckbox(task: MarkdownTaskEmbedRenderInfo, rect: NSRect) {
        let path = NSBezierPath(ovalIn: rect)
        let done = task.isDone
        if task.isMissing {
            NSColor(hex: "#101620").withAlphaComponent(0.76).setFill()
            path.fill()
            MarkdownStylist.dimColor.withAlphaComponent(0.38).setStroke()
        } else if done {
            MarkdownStylist.greenColor.withAlphaComponent(0.95).setFill()
            path.fill()
            MarkdownStylist.greenColor.setStroke()
        } else {
            NSColor(hex: "#101620").withAlphaComponent(0.94).setFill()
            path.fill()
            MarkdownStylist.dimColor.withAlphaComponent(0.75).setStroke()
        }
        path.lineWidth = 1.4
        path.stroke()

        guard done else { return }
        NSColor(hex: "#0f1117").setStroke()
        let check = NSBezierPath()
        check.lineWidth = 2
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: rect.minX + 4.6, y: rect.midY + 0.8))
        check.line(to: NSPoint(x: rect.minX + 8, y: rect.maxY - 5))
        check.line(to: NSPoint(x: rect.maxX - 4.8, y: rect.minY + 5))
        check.stroke()
    }

    private static func drawTitle(task: MarkdownTaskEmbedRenderInfo, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleColor: NSColor = task.isDone || task.isCancelled || task.isMissing ? MarkdownStylist.dimColor : MarkdownStylist.textColor
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: titleColor,
            .paragraphStyle: paragraph
        ]
        if task.isDone || task.isCancelled {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        (task.title as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func fieldRects(
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect
    ) -> (title: NSRect, chips: [ChipRect]) {
        let contentMinX = checkboxRect(in: cardRect).maxX + 12
        let contentMaxX = cardRect.maxX - 12
        let titleRect = NSRect(
            x: contentMinX,
            y: cardRect.minY + 10,
            width: max(60, contentMaxX - contentMinX),
            height: 19
        )

        var chipRects: [ChipRect] = []
        var x = contentMinX
        let y = cardRect.minY + 38
        for chip in displayChips(for: task) {
            let width = min(max(42, chip.label.size(withAttributes: chipAttributes).width + 18), 128)
            guard x + width <= contentMaxX else { break }
            let rect = NSRect(x: x, y: y, width: width, height: 20)
            chipRects.append(ChipRect(field: chip.field, rect: rect))
            x = rect.maxX + 6
        }
        return (titleRect, chipRects)
    }

    private static func displayChips(for task: MarkdownTaskEmbedRenderInfo) -> [Chip] {
        if task.isMissing {
            return [Chip(label: "Missing", color: NSColor(hex: "#ff6b6b"), field: .status)]
        }

        let statusColor: NSColor
        switch TaskStatus(rawValue: task.statusRaw) ?? .todo {
        case .todo:
            statusColor = MarkdownStylist.dimColor
        case .inProgress:
            statusColor = MarkdownStylist.blueColor
        case .done:
            statusColor = MarkdownStylist.greenColor
        case .cancelled:
            statusColor = MarkdownStylist.dimColor
        }

        var chips: [Chip] = [
            Chip(label: statusLabel(task.statusRaw), color: statusColor, field: .status),
            Chip(label: priorityLabel(task.priorityRaw), color: priorityColor(task.priorityRaw, fallback: task.containerColorHex), field: .priority)
        ]

        let container = task.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        chips.append(Chip(
            label: container.isEmpty ? "Inbox" : container,
            color: container.isEmpty ? MarkdownStylist.dimColor : NSColor(hex: task.containerColorHex),
            field: .container
        ))

        let section = task.sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !section.isEmpty, section.caseInsensitiveCompare(TaskSectionDefaults.defaultName) != .orderedSame {
            chips.append(Chip(label: section, color: MarkdownStylist.dimColor, field: .section))
        }

        chips.append(Chip(label: scheduledLabel(for: task), color: MarkdownStylist.highlightFillColor, field: .scheduledDate))
        chips.append(Chip(label: dueLabel(for: task), color: NSColor(hex: "#ff6b6b"), field: .dueDate))
        chips.append(Chip(label: estimateLabel(for: task), color: MarkdownStylist.blueColor, field: .estimate))

        if let recurrence = TaskRecurrenceRule(rawValue: task.recurrenceRaw), recurrence != .none {
            chips.append(Chip(label: recurrence.shortLabel, color: MarkdownStylist.greenColor, field: .recurrence))
        }
        return chips
    }

    private static func drawChip(label: String, color: NSColor, rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        color.withAlphaComponent(0.13).setFill()
        path.fill()
        color.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 0.7
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        var attrs = chipAttributes
        attrs[.paragraphStyle] = paragraph
        (label as NSString).draw(in: rect.insetBy(dx: 6, dy: 3), withAttributes: attrs)
    }

    private static func drawSubtasks(task: MarkdownTaskEmbedRenderInfo, cardRect: NSRect) {
        guard task.hasSubtasks else { return }
        let rects = subtaskRects(task: task, cardRect: cardRect)
        guard !rects.isEmpty else { return }

        let separatorY = cardRect.minY + 64
        NSColor(hex: "#33435f").withAlphaComponent(0.42).setStroke()
        let separator = NSBezierPath()
        separator.lineWidth = 0.6
        separator.move(to: NSPoint(x: cardRect.minX + 15, y: separatorY))
        separator.line(to: NSPoint(x: cardRect.maxX - 12, y: separatorY))
        separator.stroke()

        let progressRect = NSRect(x: cardRect.minX + 15, y: cardRect.minY + 70, width: 36, height: 18)
        drawProgressChip(label: "\(task.completedSubtaskCount)/\(task.subtaskTotalCount)", rect: progressRect)

        for subtask in task.visibleSubtasks {
            guard let rect = rects.first(where: { $0.subtaskID == subtask.id }) else { continue }
            drawSubtask(subtask, checkboxRect: rect.checkbox ?? .zero, textRect: rect.text)
        }

        if task.hiddenSubtaskCount > 0, let overflowRect = rects.first(where: { $0.subtaskID == nil }) {
            drawOverflowChip(count: task.hiddenSubtaskCount, rect: overflowRect.full)
        }
    }

    private static func subtaskRects(
        task: MarkdownTaskEmbedRenderInfo,
        cardRect: NSRect
    ) -> [MarkdownTaskEmbedSubtaskHitRect] {
        guard task.hasSubtasks else { return [] }
        let contentMinX = cardRect.minX + 59
        let contentMaxX = cardRect.maxX - 12
        let rowY = cardRect.minY + 70
        let rowHeight: CGFloat = 18
        var x = contentMinX
        var rects: [MarkdownTaskEmbedSubtaskHitRect] = []

        for subtask in task.visibleSubtasks {
            let title = subtask.title.isEmpty ? "Untitled subtask" : subtask.title
            let titleWidth = title.size(withAttributes: subtaskAttributes(done: subtask.isDone)).width
            let width = min(max(58, titleWidth + 28), 150)
            guard x + width <= contentMaxX else { break }

            let full = NSRect(x: x, y: rowY, width: width, height: rowHeight)
            let checkbox = NSRect(x: full.minX + 3, y: full.midY - 5, width: 10, height: 10)
            let text = NSRect(x: checkbox.maxX + 5, y: full.minY + 1, width: max(16, full.width - 21), height: rowHeight - 2)
            rects.append(.subtask(id: subtask.id, checkbox: checkbox, text: text, full: full))
            x = full.maxX + 6
        }

        if task.hiddenSubtaskCount > 0 {
            let label = "+\(task.hiddenSubtaskCount) more"
            let width = min(max(48, label.size(withAttributes: subtaskMetaAttributes).width + 16), 84)
            if x + width <= contentMaxX {
                let full = NSRect(x: x, y: rowY, width: width, height: rowHeight)
                rects.append(.overflow(text: full.insetBy(dx: 6, dy: 2), full: full))
            }
        }

        return rects
    }

    private static func drawProgressChip(label: String, rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        MarkdownStylist.blueColor.withAlphaComponent(0.12).setFill()
        path.fill()
        MarkdownStylist.blueColor.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 0.7
        path.stroke()
        (label as NSString).draw(in: rect.insetBy(dx: 5, dy: 3), withAttributes: subtaskMetaAttributes)
    }

    private static func drawOverflowChip(count: Int, rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor(hex: "#263248").withAlphaComponent(0.72).setFill()
        path.fill()
        NSColor(hex: "#4f607e").withAlphaComponent(0.52).setStroke()
        path.lineWidth = 0.7
        path.stroke()
        ("+\(count) more" as NSString).draw(in: rect.insetBy(dx: 6, dy: 3), withAttributes: subtaskMetaAttributes)
    }

    private static func drawSubtask(
        _ subtask: MarkdownTaskEmbedSubtaskRenderInfo,
        checkboxRect: NSRect,
        textRect: NSRect
    ) {
        let checkboxPath = NSBezierPath(ovalIn: checkboxRect)
        if subtask.isDone {
            MarkdownStylist.greenColor.withAlphaComponent(0.88).setFill()
            checkboxPath.fill()
            MarkdownStylist.greenColor.withAlphaComponent(0.9).setStroke()
        } else {
            NSColor(hex: "#101620").withAlphaComponent(0.84).setFill()
            checkboxPath.fill()
            MarkdownStylist.dimColor.withAlphaComponent(0.62).setStroke()
        }
        checkboxPath.lineWidth = 1
        checkboxPath.stroke()

        if subtask.isDone {
            NSColor(hex: "#0f1117").setStroke()
            let check = NSBezierPath()
            check.lineWidth = 1.35
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: checkboxRect.minX + 2.4, y: checkboxRect.midY + 0.4))
            check.line(to: NSPoint(x: checkboxRect.minX + 4.7, y: checkboxRect.maxY - 3))
            check.line(to: NSPoint(x: checkboxRect.maxX - 2.2, y: checkboxRect.minY + 3))
            check.stroke()
        }

        let title = subtask.title.isEmpty ? "Untitled subtask" : subtask.title
        (title as NSString).draw(in: textRect, withAttributes: subtaskAttributes(done: subtask.isDone))
    }

    private static let chipAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: MarkdownStylist.dimColor
    ]

    private static let subtaskMetaAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
        .foregroundColor: MarkdownStylist.dimColor
    ]

    private static func subtaskAttributes(done: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: done ? MarkdownStylist.dimColor.withAlphaComponent(0.72) : MarkdownStylist.textColor.withAlphaComponent(0.86),
            .paragraphStyle: paragraph
        ]
        if done {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    private static func priorityColor(_ raw: String, fallback: String) -> NSColor {
        switch TaskPriority(rawValue: raw) ?? .none {
        case .high:
            return NSColor(hex: "#ff6b6b")
        case .medium:
            return MarkdownStylist.highlightFillColor
        case .low:
            return MarkdownStylist.blueColor
        case .none:
            return NSColor(hex: fallback)
        }
    }

    private static func statusLabel(_ raw: String) -> String {
        switch TaskStatus(rawValue: raw) ?? .todo {
        case .todo:
            return "Todo"
        case .inProgress:
            return "In progress"
        case .done:
            return "Done"
        case .cancelled:
            return "Cancelled"
        }
    }

    private static func priorityLabel(_ raw: String) -> String {
        let priority = TaskPriority(rawValue: raw) ?? .none
        return priority == .none ? "No priority" : priority.label
    }

    private static func scheduledLabel(for task: MarkdownTaskEmbedRenderInfo) -> String {
        guard !task.scheduledDate.isEmpty else { return "No do date" }
        let date = DateFormatters.relativeDate(from: task.scheduledDate)
        guard task.scheduledStartMin >= 0 else { return "Do \(date)" }
        return "\(date) \(TimeFormatters.timeString(from: task.scheduledStartMin))"
    }

    private static func dueLabel(for task: MarkdownTaskEmbedRenderInfo) -> String {
        task.dueDate.isEmpty ? "No due date" : "Due \(DateFormatters.relativeDate(from: task.dueDate))"
    }

    private static func estimateLabel(for task: MarkdownTaskEmbedRenderInfo) -> String {
        if task.actualMinutes > 0 {
            return TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
        }
        return task.estimatedMinutes > 0 ? durationLabel(task.estimatedMinutes) : "No estimate"
    }

    private static func durationLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "-" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return String(format: "%.1fh", Double(minutes) / 60.0)
    }
}

enum MarkdownFormatCommand: Hashable {
    case bold
    case italic
    case inlineCode
    case strikethrough
    case highlight
    case link
    case heading(Int)
    case orderedList
    case unorderedList
    case todoList
    case quote
    case codeBlock
    case divider
    case noteLink
    case taskReference
}

final class CadenceTextView: NSTextView {
    var markdownImageAssets: [UUID: MarkdownImageRenderAsset] = [:]
    var markdownImageRects: [UUID: NSRect] = [:]
    var markdownTaskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:]
    var markdownTaskEmbedRects: [UUID: MarkdownTaskEmbedHitRects] = [:]
    var hoveredMarkdownTaskEmbedID: UUID?
    var selectedMarkdownImageID: UUID?
    var referenceSuggestions: [MarkdownReferenceSuggestion] = []
    var onOpenMarkdownReference: ((MarkdownReferenceTarget) -> Void)?
    var onCreateEmbeddedMarkdownTask: ((String) -> MarkdownReferenceSuggestion?)?
    var onToggleEmbeddedMarkdownTask: ((UUID) -> Void)?
    var onToggleEmbeddedMarkdownSubtask: ((UUID, UUID) -> Void)?
    var onOpenEmbeddedMarkdownTask: ((UUID) -> Void)?
    var onEditEmbeddedMarkdownTask: ((UUID, MarkdownTaskEmbedField) -> Void)?
    var onHoverEmbeddedMarkdownTask: ((UUID, Bool) -> Void)?
    var onCreateMarkdownImages: (([NSImage], [URL]) -> [MarkdownImageAsset])?
    var onResizeMarkdownImage: ((UUID, CGFloat) -> Void)?

    private var resizingImageID: UUID?
    private var resizeStartX: CGFloat = 0
    private var resizeStartWidth: CGFloat = 0
    private var trackingAreaForHover: NSTrackingArea?
    private var pendingTaskEmbedMouseDown: (id: UUID, target: TaskEmbedHitTarget, point: NSPoint, event: NSEvent)?
    private var draggingTaskEmbedID: UUID?
    private let taskEmbedDragThreshold: CGFloat = 4

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

        if let targetIndex = legacyChecklistMarkerHit(at: viewPoint) {
            let nsString = string as NSString
            guard targetIndex < nsString.length else { return }
            let targetCharacter = nsString.character(at: targetIndex)
            let replacement = targetCharacter == 0x25CB ? "●" : "○"
            let range = NSRange(location: targetIndex, length: 1)
            if shouldChangeText(in: range, replacementString: replacement) {
                textStorage?.replaceCharacters(in: range, with: replacement)
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

    func replaceEmbeddedTaskReferenceTitle(id: UUID, title: String) {
        guard let textStorage else { return }
        let sanitized = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = sanitized.isEmpty ? MarkdownTaskEmbedRenderInfo.untitledTaskTitle : sanitized
        let escapedID = NSRegularExpression.escapedPattern(for: id.uuidString)
        guard let regex = try? NSRegularExpression(pattern: #"\[\[task:\#(escapedID)\|([^\]\n]+)\]\]"#) else { return }

        let current = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: current.length))
        guard !matches.isEmpty else { return }
        var didReplace = false
        for match in matches.reversed() where match.numberOfRanges > 1 {
            let titleRange = match.range(at: 1)
            guard titleRange.location != NSNotFound,
                  current.substring(with: titleRange) != displayTitle,
                  shouldChangeText(in: titleRange, replacementString: displayTitle) else { continue }
            textStorage.replaceCharacters(in: titleRange, with: displayTitle)
            didReplace = true
        }
        guard didReplace else { return }
        didChangeText()
        MarkdownStylist.apply(to: self)
        needsDisplay = true
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
        let insertion = paddedInsertion(markdown)
        let selection = selectedRange()
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

    private func performTaskEmbedClick(_ pending: (id: UUID, target: TaskEmbedHitTarget, point: NSPoint, event: NSEvent)) {
        switch pending.target {
        case .checkbox:
            onToggleEmbeddedMarkdownTask?(pending.id)
        case .subtaskCheckbox(let subtaskID):
            onToggleEmbeddedMarkdownSubtask?(pending.id, subtaskID)
        case .subtaskText:
            onOpenEmbeddedMarkdownTask?(pending.id)
        case .field(let field):
            onEditEmbeddedMarkdownTask?(pending.id, field)
        case .card:
            onOpenEmbeddedMarkdownTask?(pending.id)
        }
    }

    private func updateHoveredTaskEmbed(at point: NSPoint) {
        let nextID = taskEmbedHit(at: point)?.id
        guard nextID != hoveredMarkdownTaskEmbedID else { return }
        if let hoveredMarkdownTaskEmbedID {
            onHoverEmbeddedMarkdownTask?(hoveredMarkdownTaskEmbedID, false)
        }
        hoveredMarkdownTaskEmbedID = nextID
        if let nextID {
            onHoverEmbeddedMarkdownTask?(nextID, true)
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
        needsDisplay = true
    }

    private func clearHoveredTaskEmbed() {
        guard let hoveredMarkdownTaskEmbedID else { return }
        onHoverEmbeddedMarkdownTask?(hoveredMarkdownTaskEmbedID, false)
        self.hoveredMarkdownTaskEmbedID = nil
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
        NSColor(hex: "#182236").withAlphaComponent(0.96).setFill()
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

    private enum TaskEmbedHitTarget {
        case checkbox
        case subtaskCheckbox(UUID)
        case subtaskText
        case field(MarkdownTaskEmbedField)
        case card
    }

    private func taskEmbedHit(at point: NSPoint) -> (id: UUID, target: TaskEmbedHitTarget)? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        var result: (id: UUID, target: TaskEmbedHitTarget)?
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

    private func legacyChecklistMarkerHit(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
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
        guard let markerRange = MarkdownTaskEmbedParser.legacyChecklistMarkerRange(in: line, lineStart: lineRange.location) else {
            return nil
        }

        let markerGlyphRange = layoutManager.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
        guard markerGlyphRange.length > 0 else { return nil }
        let markerRect = layoutManager.boundingRect(forGlyphRange: markerGlyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            .insetBy(dx: -6, dy: -5)
        return markerRect.contains(point) ? markerRange.location : nil
    }

    private func markdownImageRange(for id: UUID) -> NSRange? {
        guard let textStorage else { return nil }
        var result: NSRange?
        textStorage.enumerateAttribute(.cadenceMarkdownImage, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard let info = value as? MarkdownImageLayoutInfo, info.id == id else { return }
            result = expandedMarkdownImageDeletionRange(from: range)
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
            result = expandedMarkdownImageDeletionRange(from: range)
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
            return expandedMarkdownImageDeletionRange(from: effectiveRange)
        }
        return nil
    }

    private func markdownTaskEmbedRange(intersecting selection: NSRange) -> NSRange? {
        guard let textStorage else { return nil }
        var result: NSRange?
        textStorage.enumerateAttribute(.cadenceMarkdownTaskEmbed, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, stop in
            guard value is MarkdownTaskEmbedLayoutInfo,
                  NSIntersectionRange(range, selection).length > 0 else { return }
            result = expandedMarkdownTaskEmbedDeletionRange(from: range)
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
                return expandedMarkdownTaskEmbedDeletionRange(from: effectiveRange)
            }
        }
        return nil
    }

    private func markdownReferenceHit(at point: NSPoint) -> MarkdownReferenceTarget? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.cadenceMarkdownReference, at: characterIndex, effectiveRange: nil) as? MarkdownReferenceTarget
    }

    private func expandedMarkdownImageDeletionRange(from range: NSRange) -> NSRange {
        let nsText = string as NSString
        var deletionRange = NSIntersectionRange(range, NSRange(location: 0, length: nsText.length))
        guard deletionRange.length > 0 else { return deletionRange }

        let after = NSMaxRange(deletionRange)
        if after < nsText.length, nsText.substring(with: NSRange(location: after, length: 1)) == "\n" {
            deletionRange.length += 1
        } else if deletionRange.location > 0,
                  nsText.substring(with: NSRange(location: deletionRange.location - 1, length: 1)) == "\n" {
            deletionRange.location -= 1
            deletionRange.length += 1
        }

        return deletionRange
    }

    private func expandedMarkdownTaskEmbedDeletionRange(from range: NSRange) -> NSRange {
        let nsText = string as NSString
        var deletionRange = NSIntersectionRange(range, NSRange(location: 0, length: nsText.length))
        guard deletionRange.length > 0 else { return deletionRange }

        let after = NSMaxRange(deletionRange)
        if after < nsText.length, nsText.substring(with: NSRange(location: after, length: 1)) == "\n" {
            deletionRange.length += 1
        } else if deletionRange.location > 0,
                  nsText.substring(with: NSRange(location: deletionRange.location - 1, length: 1)) == "\n" {
            deletionRange.location -= 1
            deletionRange.length += 1
        }

        return deletionRange
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

    private func paddedInsertion(_ markdown: String) -> String {
        let nsText = string as NSString
        let selection = selectedRange()
        let needsLeadingBreak: Bool
        if selection.location == 0 {
            needsLeadingBreak = false
        } else {
            let previous = nsText.substring(with: NSRange(location: max(0, selection.location - 1), length: 1))
            needsLeadingBreak = previous != "\n"
        }

        let needsTrailingBreak: Bool
        if NSMaxRange(selection) >= nsText.length {
            needsTrailingBreak = false
        } else {
            let next = nsText.substring(with: NSRange(location: NSMaxRange(selection), length: 1))
            needsTrailingBreak = next != "\n"
        }

        return (needsLeadingBreak ? "\n\n" : "") + markdown + (needsTrailingBreak ? "\n\n" : "\n")
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

private enum MarkdownKeyboardShortcutSupport {
    static func apply(_ command: MarkdownFormatCommand, in textView: NSTextView) -> Bool {
        switch command {
        case .bold:
            return toggleInlineMarker("**", in: textView)
        case .italic:
            return toggleInlineMarker("*", in: textView)
        case .inlineCode:
            return toggleInlineMarker("`", in: textView)
        case .strikethrough:
            return toggleInlineMarker("~~", in: textView)
        case .highlight:
            return toggleInlineMarker("==", in: textView)
        case .link:
            return insertLink(in: textView)
        case .heading(let level):
            return toggleHeading(level: level, in: textView)
        case .orderedList:
            return toggleOrderedList(in: textView)
        case .unorderedList:
            return toggleUnorderedList(in: textView)
        case .todoList:
            return toggleTodoList(in: textView)
        case .quote:
            return toggleQuote(in: textView)
        case .codeBlock:
            return insertCodeBlock(in: textView)
        case .divider:
            return insertBlock("---", in: textView)
        case .noteLink:
            return insertSnippet("[[]]", caretOffset: 2, in: textView)
        case .taskReference:
            return insertSnippet("[[task:]]", caretOffset: 7, in: textView)
        }
    }

    static func handle(_ event: NSEvent, in textView: NSTextView) -> Bool {
        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1 else { return false }

        var flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        flags.remove(.capsLock)

        switch (characters, flags) {
        case ("b", [.command]):
            return apply(.bold, in: textView)
        case ("i", [.command]):
            return apply(.italic, in: textView)
        case ("e", [.command]):
            return apply(.inlineCode, in: textView)
        case ("k", [.command]):
            return apply(.link, in: textView)
        case ("x", [.command, .shift]):
            return apply(.strikethrough, in: textView)
        case ("0", [.command, .option]):
            return rewriteSelectedLines(in: textView) { line, _ in
                removeHeadingPrefix(from: line)
            }
        case ("1", [.command, .option]),
             ("2", [.command, .option]),
             ("3", [.command, .option]),
             ("4", [.command, .option]),
             ("5", [.command, .option]),
             ("6", [.command, .option]):
            guard let level = Int(characters) else { return false }
            return apply(.heading(level), in: textView)
        case ("7", [.command, .shift]):
            return apply(.orderedList, in: textView)
        case ("8", [.command, .shift]):
            return apply(.unorderedList, in: textView)
        case ("9", [.command, .shift]):
            return apply(.quote, in: textView)
        default:
            return false
        }
    }

    private static func toggleInlineMarker(_ marker: String, in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        let nsText = textView.string as NSString
        let markerLength = (marker as NSString).length

        if selection.length == 0,
           selection.location >= markerLength,
           selection.location + markerLength <= nsText.length,
           hasMarkerPair(marker, openLocation: selection.location - markerLength, closeLocation: selection.location, in: nsText) {
            let unwrapRange = NSRange(location: selection.location - markerLength, length: markerLength * 2)
            return replaceText(in: textView, range: unwrapRange, with: "", selection: NSRange(location: unwrapRange.location, length: 0))
        }

        if selection.length > 0 {
            let selectedText = nsText.substring(with: selection)
            if isSelfWrapped(selectedText, marker: marker),
               (selectedText as NSString).length > markerLength * 2 {
                let innerRange = NSRange(location: markerLength, length: (selectedText as NSString).length - markerLength * 2)
                let replacement = (selectedText as NSString).substring(with: innerRange)
                return replaceText(
                    in: textView,
                    range: selection,
                    with: replacement,
                    selection: NSRange(location: selection.location, length: (replacement as NSString).length)
                )
            }

            if selection.location >= markerLength,
               NSMaxRange(selection) + markerLength <= nsText.length,
               hasMarkerPair(marker, openLocation: selection.location - markerLength, closeLocation: NSMaxRange(selection), in: nsText) {
                let replacementRange = NSRange(location: selection.location - markerLength, length: selection.length + markerLength * 2)
                return replaceText(
                    in: textView,
                    range: replacementRange,
                    with: selectedText,
                    selection: NSRange(location: replacementRange.location, length: selection.length)
                )
            }

            let replacement = marker + selectedText + marker
            return replaceText(
                in: textView,
                range: selection,
                with: replacement,
                selection: NSRange(location: selection.location + markerLength, length: selection.length)
            )
        }

        let replacement = marker + marker
        return replaceText(
            in: textView,
            range: selection,
            with: replacement,
            selection: NSRange(location: selection.location + markerLength, length: 0)
        )
    }

    private static func isSelfWrapped(_ text: String, marker: String) -> Bool {
        guard text.hasPrefix(marker), text.hasSuffix(marker) else { return false }
        if marker == "*" {
            return !text.hasPrefix("**") && !text.hasSuffix("**")
        }
        return true
    }

    private static func hasMarkerPair(_ marker: String, openLocation: Int, closeLocation: Int, in text: NSString) -> Bool {
        let markerLength = (marker as NSString).length
        guard openLocation >= 0,
              closeLocation >= 0,
              openLocation + markerLength <= text.length,
              closeLocation + markerLength <= text.length,
              text.substring(with: NSRange(location: openLocation, length: markerLength)) == marker,
              text.substring(with: NSRange(location: closeLocation, length: markerLength)) == marker else {
            return false
        }

        guard marker == "*" else { return true }
        if openLocation > 0,
           text.substring(with: NSRange(location: openLocation - 1, length: 1)) == "*" {
            return false
        }
        if closeLocation + markerLength < text.length,
           text.substring(with: NSRange(location: closeLocation + markerLength, length: 1)) == "*" {
            return false
        }
        return true
    }

    private static func insertLink(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        let nsText = textView.string as NSString

        if selection.length > 0 {
            let selectedText = nsText.substring(with: selection)
            let replacement = "[\(selectedText)](url)"
            let urlLocation = selection.location + (selectedText as NSString).length + 3
            return replaceText(
                in: textView,
                range: selection,
                with: replacement,
                selection: NSRange(location: urlLocation, length: 3)
            )
        }

        let replacement = "[text](url)"
        return replaceText(
            in: textView,
            range: selection,
            with: replacement,
            selection: NSRange(location: selection.location + 1, length: 4)
        )
    }

    private static func toggleHeading(level: Int, in textView: NSTextView) -> Bool {
        let prefix = String(repeating: "#", count: max(1, min(level, 6))) + " "
        return rewriteSelectedLines(in: textView) { line, _ in
            let heading = headingPrefix(in: line)
            let content = heading.map { String(line.dropFirst($0.prefixLength)) } ?? line.trimmingCharacters(in: .whitespaces)
            if heading?.level == level {
                return content
            }
            return prefix + content
        }
    }

    private static func toggleOrderedList(in textView: NSTextView) -> Bool {
        rewriteSelectedLines(in: textView) { line, _ in
            guard !line.isEmpty else { return "1. " }
            if let match = MarkdownListSupport.listPrefixMatch(in: line) {
                if match.kind == .ordered {
                    return String(line.dropFirst(match.prefix.count))
                }
                let content = String(line.dropFirst(match.prefix.count))
                let marker = MarkdownListSupport.orderedMarker(forIndentation: match.indentation)
                return match.indentation + marker + " " + content
            }

            let indentation = leadingWhitespace(in: line)
            let content = String(line.dropFirst(indentation.count))
            let marker = MarkdownListSupport.orderedMarker(forIndentation: indentation)
            return indentation + marker + " " + content
        }
    }

    private static func toggleUnorderedList(in textView: NSTextView) -> Bool {
        rewriteSelectedLines(in: textView) { line, _ in
            guard !line.isEmpty else { return "• " }
            if let match = MarkdownListSupport.listPrefixMatch(in: line) {
                switch match.kind {
                case .bullet, .dash, .plus:
                    return String(line.dropFirst(match.prefix.count))
                case .ordered, .todo, .done:
                    let content = String(line.dropFirst(match.prefix.count))
                    return match.indentation + "• " + content
                }
            }

            let indentation = leadingWhitespace(in: line)
            let content = String(line.dropFirst(indentation.count))
            return indentation + "• " + content
        }
    }

    private static func toggleTodoList(in textView: NSTextView) -> Bool {
        rewriteSelectedLines(in: textView) { line, _ in
            guard !line.isEmpty else { return "[ ] " }
            if let match = MarkdownListSupport.listPrefixMatch(in: line) {
                switch match.kind {
                case .todo, .done:
                    return String(line.dropFirst(match.prefix.count))
                case .ordered, .bullet, .dash, .plus:
                    let content = String(line.dropFirst(match.prefix.count))
                    return match.indentation + "[ ] " + content
                }
            }

            let indentation = leadingWhitespace(in: line)
            let content = String(line.dropFirst(indentation.count))
            return indentation + "[ ] " + content
        }
    }

    private static func toggleQuote(in textView: NSTextView) -> Bool {
        rewriteSelectedLines(in: textView) { line, _ in
            let indentation = leadingWhitespace(in: line)
            let content = String(line.dropFirst(indentation.count))
            if content.hasPrefix("> ") {
                return indentation + String(content.dropFirst(2))
            }
            if content == ">" {
                return indentation
            }
            return indentation + "> " + content
        }
    }

    private static func insertCodeBlock(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        let nsText = textView.string as NSString
        if selection.length > 0 {
            let selectedText = nsText.substring(with: selection).trimmingCharacters(in: .newlines)
            let replacement = "```\n\(selectedText)\n```"
            return replaceText(
                in: textView,
                range: selection,
                with: replacement,
                selection: NSRange(location: selection.location + 4, length: (selectedText as NSString).length)
            )
        }
        return insertSnippet("```\n\n```", caretOffset: 4, in: textView)
    }

    private static func insertBlock(_ block: String, in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        let nsText = textView.string as NSString
        let needsLeadingBreak = selection.location > 0 &&
            nsText.substring(with: NSRange(location: max(0, selection.location - 1), length: 1)) != "\n"
        let needsTrailingBreak = NSMaxRange(selection) < nsText.length &&
            nsText.substring(with: NSRange(location: NSMaxRange(selection), length: 1)) != "\n"
        let replacement = (needsLeadingBreak ? "\n\n" : "") + block + (needsTrailingBreak ? "\n\n" : "\n")
        let caret = selection.location + (replacement as NSString).length
        return replaceText(
            in: textView,
            range: selection,
            with: replacement,
            selection: NSRange(location: caret, length: 0)
        )
    }

    private static func insertSnippet(_ snippet: String, caretOffset: Int, in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        return replaceText(
            in: textView,
            range: selection,
            with: snippet,
            selection: NSRange(location: selection.location + caretOffset, length: 0)
        )
    }

    private static func rewriteSelectedLines(
        in textView: NSTextView,
        transform: (String, Int) -> String
    ) -> Bool {
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        let targetRange = effectiveLineRange(for: selection, in: nsText)
        let original = nsText.substring(with: targetRange)
        let originalLines = original.components(separatedBy: "\n")
        let skipsTrailingEmptyLine = original.hasSuffix("\n")
        let transformedLines = originalLines.enumerated().map { index, line in
            if skipsTrailingEmptyLine && index == originalLines.count - 1 {
                return line
            }
            return transform(line, index)
        }
        let replacement = transformedLines.joined(separator: "\n")
        guard replacement != original else { return true }

        let selectionRange: NSRange
        if selection.length == 0,
           let originalFirstLine = originalLines.first,
           let replacementFirstLine = transformedLines.first {
            let originalOffset = max(0, selection.location - targetRange.location)
            let originalPrefixLength = markupPrefixLength(in: originalFirstLine)
            let replacementPrefixLength = markupPrefixLength(in: replacementFirstLine)
            let adjustedOffset: Int
            if originalOffset <= originalPrefixLength {
                adjustedOffset = replacementPrefixLength
            } else {
                adjustedOffset = originalOffset + replacementPrefixLength - originalPrefixLength
            }
            selectionRange = NSRange(
                location: targetRange.location + max(0, min((replacement as NSString).length, adjustedOffset)),
                length: 0
            )
        } else {
            selectionRange = NSRange(location: targetRange.location, length: (replacement as NSString).length)
        }

        return replaceText(in: textView, range: targetRange, with: replacement, selection: selectionRange)
    }

    private static func replaceText(
        in textView: NSTextView,
        range: NSRange,
        with replacement: String,
        selection: NSRange
    ) -> Bool {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return true }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.setSelectedRange(selection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private static func effectiveLineRange(for selection: NSRange, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }

        let startLocation = min(max(selection.location, 0), text.length - 1)
        let startLine = text.lineRange(for: NSRange(location: startLocation, length: 0))
        guard selection.length > 0 else { return startLine }

        let rawEnd = NSMaxRange(selection)
        let endLocation: Int
        if rawEnd > selection.location,
           rawEnd <= text.length,
           text.character(at: rawEnd - 1) == 10 {
            endLocation = max(selection.location, rawEnd - 1)
        } else {
            endLocation = min(max(selection.location, rawEnd), text.length - 1)
        }

        let endLine = text.lineRange(for: NSRange(location: endLocation, length: 0))
        return NSUnionRange(startLine, endLine)
    }

    private static func leadingWhitespace(in line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func removeHeadingPrefix(from line: String) -> String {
        guard let heading = headingPrefix(in: line) else { return line }
        return String(line.dropFirst(heading.prefixLength))
    }

    private static func headingPrefix(in line: String) -> (level: Int, prefixLength: Int)? {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^#{1,6}\s+"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        let prefix = nsLine.substring(with: match.range)
        return (prefix.filter { $0 == "#" }.count, match.range.length)
    }

    private static func quotePrefixLength(in line: String) -> Int {
        let indentation = leadingWhitespace(in: line)
        let content = String(line.dropFirst(indentation.count))
        if content.hasPrefix("> ") {
            return indentation.count + 2
        }
        if content == ">" {
            return indentation.count + 1
        }
        return 0
    }

    private static func markupPrefixLength(in line: String) -> Int {
        if let heading = headingPrefix(in: line) {
            return heading.prefixLength
        }
        if let match = MarkdownListSupport.listPrefixMatch(in: line) {
            return match.prefix.count
        }
        return quotePrefixLength(in: line)
    }
}

final class MarkdownEditorCoordinator: NSObject, NSTextViewDelegate {
    private var parent: MarkdownEditorView
    private let slashCommandPicker = MarkdownSlashCommandPickerController()
    private let referencePicker = MarkdownReferencePickerController()
    private weak var pendingSlashCommandTextView: NSTextView?
    private weak var pendingReferenceTextView: NSTextView?
    private var slashCommandUpdateIsScheduled = false
    private var referenceUpdateIsScheduled = false

    init(parent: MarkdownEditorView) {
        self.parent = parent
    }

    func update(parent: MarkdownEditorView) {
        self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let scrollView = textView.enclosingScrollView
        applyInputTransforms(to: textView)
        normalizeMarkdownListPrefixes(in: textView)
        normalizeOrderedListMarkers(in: textView)
        parent.text = textView.string
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
        textView.typingAttributes = MarkdownStylist.baseAttributes
        scheduleSlashCommandPickerUpdate(for: textView)
        scheduleReferencePickerUpdate(for: textView)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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

        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return adjustIndentation(in: textView, increase: true)
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return adjustIndentation(in: textView, increase: false)
        }

        if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            if slashCommandPicker.isShown {
                scheduleSlashCommandPickerUpdate(for: textView)
            }
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteMarkdownImageForCommand(backward: true) {
                return true
            }
            if let cadenceTextView = textView as? CadenceTextView,
               cadenceTextView.deleteEmbeddedMarkdownTaskForCommand(backward: true) {
                return true
            }
            if deleteBackwardToPlainTextListItem(in: textView) {
                return true
            }
            return deleteBackwardFromEmptyListItem(in: textView)
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

        guard let prefixMatch = MarkdownListSupport.listPrefixMatch(in: line) else { return false }

        let contentAfterPrefix = String(line.dropFirst(prefixMatch.prefix.count)).trimmingCharacters(in: .whitespaces)
        if contentAfterPrefix.isEmpty {
            let deleteRange = NSRange(location: lineRange.location,
                                      length: min(lineRange.length, nsText.length - lineRange.location))
            guard textView.shouldChangeText(in: deleteRange, replacementString: "\n") else { return false }
            textView.textStorage?.replaceCharacters(in: deleteRange, with: "\n")
            textView.setSelectedRange(NSRange(location: lineRange.location + 1, length: 0))
            textView.typingAttributes = MarkdownStylist.baseAttributes
            textView.didChangeText()
            return true
        }

        let continuedPrefix: String
        switch prefixMatch.kind {
        case .ordered:
            continuedPrefix = prefixMatch.indentation + MarkdownListSupport.nextOrderedMarker(after: prefixMatch.marker) + " "
        case .todo, .done:
            continuedPrefix = prefixMatch.indentation + "○ "
        default:
            continuedPrefix = prefixMatch.prefix
        }

        let insertedString = "\n" + continuedPrefix
        guard textView.shouldChangeText(in: selection, replacementString: insertedString) else { return false }
        textView.textStorage?.replaceCharacters(in: selection, with: insertedString)
        let newPosition = selection.location + (insertedString as NSString).length
        textView.setSelectedRange(NSRange(location: newPosition, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private func adjustIndentation(in textView: NSTextView, increase: Bool) -> Bool {
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        let isCaretOnlySelection = selection.length == 0
        let targetRange = effectiveLineRange(for: selection, in: nsText)
        let original = nsText.substring(with: targetRange)
        let lines = original.components(separatedBy: "\n")

        var changed = false
        let updatedLines = lines.map { line -> String in
            if increase {
                guard let prefixMatch = MarkdownListSupport.listPrefixMatch(in: line) else { return line }
                changed = true
                let indentedLine = String(repeating: " ", count: 4) + line
                return MarkdownListSupport.remapOrderedMarkerIfNeeded(in: indentedLine, originalMatch: prefixMatch)
            }

            let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
            let normalizedIndentWidth = indentation.reduce(into: 0) { width, character in
                width += character == "\t" ? 4 : 1
            }
            guard let prefixMatch = MarkdownListSupport.listPrefixMatch(in: line) else { return line }

            if normalizedIndentWidth == 0 {
                changed = true
                return String(line.dropFirst(prefixMatch.prefix.count))
            }

            let charactersToDrop: Int
            if indentation.first == "\t" {
                charactersToDrop = 1
            } else {
                charactersToDrop = min(4, indentation.count)
            }

            changed = true
            let outdentedLine = String(line.dropFirst(charactersToDrop))
            return MarkdownListSupport.remapOrderedMarkerIfNeeded(in: outdentedLine, originalMatch: prefixMatch)
        }

        guard changed else { return false }

        let replacement = updatedLines.joined(separator: "\n")
        guard textView.shouldChangeText(in: targetRange, replacementString: replacement) else { return true }
        let replacementLength = (replacement as NSString).length
        let locationOffset = increase ? 4 : -min(4, selection.location - targetRange.location)
        let lengthDelta = replacementLength - targetRange.length

        textView.textStorage?.replaceCharacters(in: targetRange, with: replacement)

        let newSelection: NSRange
        if isCaretOnlySelection {
            let originalCaretOffset = max(0, selection.location - targetRange.location)
            let adjustedCaretOffset: Int
            let originalContentLine = String(original.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
            let replacementContentLine = String(replacement.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")

            if !originalContentLine.isEmpty,
               let originalPrefixMatch = MarkdownListSupport.listPrefixMatch(in: originalContentLine),
               let updatedPrefixMatch = MarkdownListSupport.listPrefixMatch(in: replacementContentLine) {
                let originalPrefixLength = originalPrefixMatch.prefix.count
                let updatedPrefixLength = updatedPrefixMatch.prefix.count
                if originalCaretOffset <= originalPrefixLength {
                    adjustedCaretOffset = updatedPrefixLength
                } else {
                    adjustedCaretOffset = min(
                        replacementLength,
                        max(updatedPrefixLength, originalCaretOffset + (replacementLength - targetRange.length))
                    )
                }
            } else {
                adjustedCaretOffset = max(0, min(replacementLength, originalCaretOffset + locationOffset))
            }
            newSelection = NSRange(location: targetRange.location + adjustedCaretOffset, length: 0)
        } else {
            newSelection = NSRange(
                location: max(targetRange.location, selection.location + locationOffset),
                length: max(0, selection.length + lengthDelta)
            )
        }
        textView.setSelectedRange(newSelection)
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private func applyInputTransforms(to textView: NSTextView) {
        let nsText = textView.string as NSString
        let cursor = textView.selectedRange().location
        guard cursor > 0 else { return }

        if cursor >= 2 {
            let range = NSRange(location: cursor - 2, length: 2)
            let snippet = nsText.substring(with: range)
            if snippet == "* ", MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil {
                return replaceText(in: textView, range: range, with: "• ")
            }
            if snippet == "- ", MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil {
                return replaceText(in: textView, range: range, with: "– ")
            }
            if snippet == "+ ", MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil {
                return replaceText(in: textView, range: range, with: "+ ")
            }
        }

        if cursor >= 4 {
            let range = NSRange(location: cursor - 4, length: 4)
            let snippet = nsText.substring(with: range)
            if snippet == "[ ] ", MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil {
                replaceText(in: textView, range: range, with: "○ ")
                textView.setSelectedRange(NSRange(location: range.location + 2, length: 0))
                return
            }
            if snippet.lowercased() == "[x] ", MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil {
                replaceText(in: textView, range: range, with: "● ")
                textView.setSelectedRange(NSRange(location: range.location + 2, length: 0))
                return
            }
            if snippet == "( ) ",
               MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil,
               createUntitledEmbeddedTask(fromTriggerRange: range, in: textView) {
                return
            }
        }

        if cursor >= 3 {
            let range = NSRange(location: cursor - 3, length: 3)
            let snippet = nsText.substring(with: range)
            if snippet == "[] ", MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil {
                replaceText(in: textView, range: range, with: "○ ")
                textView.setSelectedRange(NSRange(location: range.location + 2, length: 0))
                return
            }
            if snippet == "() ",
               MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil,
               createUntitledEmbeddedTask(fromTriggerRange: range, in: textView) {
                return
            }
            if snippet == "1. ", let indentation = MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) {
                let marker = MarkdownListSupport.orderedMarker(forIndentation: indentation)
                replaceText(in: textView, range: range, with: marker + " ")
                textView.setSelectedRange(NSRange(location: range.location + marker.count + 1, length: 0))
                return
            }
        }

        if let orderedInput = typedOrderedPrefixMatch(in: nsText, cursor: cursor) {
            let level = MarkdownListSupport.orderedLevel(forIndentation: orderedInput.indentation)
            let typedIndex = MarkdownListSupport.orderedIndex(for: orderedInput.marker) ?? 1
            let normalizedMarker = MarkdownStylist.orderedMarker(for: level, index: typedIndex)
            let replacement = orderedInput.indentation + normalizedMarker + " "
            replaceText(in: textView, range: orderedInput.range, with: replacement)
            textView.setSelectedRange(NSRange(location: orderedInput.range.location + replacement.count, length: 0))
            return
        }

        if let slashCommand = typedSlashCommandMatch(in: nsText, cursor: cursor) {
            replaceText(in: textView, range: slashCommand.range, with: slashCommand.replacement)
            let caretLocation = slashCommand.range.location + slashCommand.caretOffset
            textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
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
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        cadenceTextView.onEditEmbeddedMarkdownTask?(suggestion.targetID, .title)
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

    private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
    }

    private func normalizeMarkdownListPrefixes(in textView: NSTextView) {
        let originalText = textView.string
        let normalizedText = MarkdownListSupport.normalizedMarkdownListPrefixes(in: originalText)
        guard normalizedText != originalText else { return }

        let selection = textView.selectedRange()
        let lengthDelta = (normalizedText as NSString).length - (originalText as NSString).length
        textView.string = normalizedText
        let normalizedLength = (normalizedText as NSString).length
        let adjustedLocation = min(max(0, selection.location + lengthDelta), normalizedLength)
        let adjustedLength = min(selection.length, max(0, normalizedLength - adjustedLocation))
        textView.setSelectedRange(NSRange(location: adjustedLocation, length: adjustedLength))
    }

    private func updateSlashCommandPicker(for textView: NSTextView) {
        slashCommandPicker.update(for: textView, context: currentSlashCommandContext(in: textView)) { [weak self] command, context in
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
        }
        referencePicker.update(
            for: textView,
            context: context,
            suggestions: parent.referenceSuggestions
        ) { [weak self] suggestion, context in
            self?.applyReferenceSuggestion(suggestion, context: context, in: textView)
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
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return nil }

        let nsText = textView.string as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        guard let token = MarkdownSlashCommandTokenSupport.token(in: nsText, cursor: safeCursor, requiresTrailingSpace: false) else { return nil }
        return MarkdownSlashCommandContext(
            range: token.range,
            indentation: token.indentation,
            query: token.query,
            cursorLocation: safeCursor
        )
    }

    private func applySlashCommand(_ command: MarkdownSlashCommand, context: MarkdownSlashCommandContext, in textView: NSTextView) {
        switch command.action {
        case let .insertText(_, text, caretOffset):
            let replacement = context.indentation + text
            guard textView.shouldChangeText(in: context.range, replacementString: replacement) else {
                slashCommandPicker.close()
                return
            }
            textView.textStorage?.replaceCharacters(in: context.range, with: replacement)
            textView.setSelectedRange(NSRange(location: context.range.location + context.indentation.count + caretOffset, length: 0))
            textView.typingAttributes = MarkdownStylist.baseAttributes
            textView.didChangeText()
        case .chooseImage:
            guard textView.shouldChangeText(in: context.range, replacementString: context.indentation) else {
                slashCommandPicker.close()
                return
            }
            textView.textStorage?.replaceCharacters(in: context.range, with: context.indentation)
            textView.setSelectedRange(NSRange(location: context.range.location + context.indentation.count, length: 0))
            textView.typingAttributes = MarkdownStylist.baseAttributes
            textView.didChangeText()
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
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return nil }
        let nsText = textView.string as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, safeCursor - 1), length: 0))
        guard safeCursor >= lineRange.location else { return nil }

        let prefixRange = NSRange(location: lineRange.location, length: safeCursor - lineRange.location)
        let prefix = nsText.substring(with: prefixRange)
        let nsPrefix = prefix as NSString
        let openRange = nsPrefix.range(of: "[[", options: .backwards)
        guard openRange.location != NSNotFound else { return nil }

        let tokenStart = NSMaxRange(openRange)
        let token = nsPrefix.substring(with: NSRange(location: tokenStart, length: max(0, nsPrefix.length - tokenStart)))
        guard token.count <= 80,
              !token.contains("["),
              !token.contains("]"),
              !token.contains("\n") else { return nil }

        let kind: MarkdownReferenceKind
        let query: String
        if token.lowercased().hasPrefix("task:") {
            kind = .task
            query = String(token.dropFirst(5))
        } else if token.lowercased().hasPrefix("note:") {
            kind = .note
            query = String(token.dropFirst(5))
        } else {
            kind = .note
            query = token
        }

        return MarkdownReferenceCompletionContext(
            range: NSRange(location: lineRange.location + openRange.location, length: safeCursor - lineRange.location - openRange.location),
            kind: kind,
            query: query,
            cursorLocation: safeCursor
        )
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

    private func typedOrderedPrefixMatch(in text: NSString, cursor: Int) -> (range: NSRange, indentation: String, marker: String)? {
        let safeCursor = min(max(cursor, 0), text.length)
        let lineRange = text.lineRange(for: NSRange(location: max(0, safeCursor - 1), length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: safeCursor - lineRange.location)
        let prefix = text.substring(with: prefixRange)
        guard let regex = try? NSRegularExpression(pattern: #"^([ \t]*)(\d+\.) $"#),
              let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else {
            return nil
        }

        let indentation = (prefix as NSString).substring(with: match.range(at: 1))
        let marker = (prefix as NSString).substring(with: match.range(at: 2))
        let replacementRange = NSRange(location: lineRange.location, length: prefixRange.length)
        return (replacementRange, indentation, marker)
    }

    private func typedSlashCommandMatch(in text: NSString, cursor: Int) -> (range: NSRange, replacement: String, caretOffset: Int)? {
        let safeCursor = min(max(cursor, 0), text.length)
        guard let token = MarkdownSlashCommandTokenSupport.token(in: text, cursor: safeCursor, requiresTrailingSpace: true) else { return nil }
        let command = token.query
        guard let commandConfig = MarkdownSlashCommand.all.first(where: { $0.id == command }) else { return nil }
        guard case let .insertText(_, text, caretOffset) = commandConfig.action else { return nil }
        let replacement = token.indentation + text
        return (token.range, replacement, token.indentation.count + caretOffset)
    }

    private func effectiveLineRange(for selection: NSRange, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }

        let startLocation = min(max(selection.location, 0), text.length - 1)
        let startLine = text.lineRange(for: NSRange(location: startLocation, length: 0))

        if selection.length == 0 {
            return startLine
        }

        let rawEnd = NSMaxRange(selection)
        let endLocation: Int
        if rawEnd > selection.location,
           rawEnd <= text.length,
           text.character(at: rawEnd - 1) == 10 {
            endLocation = max(selection.location, rawEnd - 1)
        } else {
            endLocation = min(max(selection.location, rawEnd), text.length - 1)
        }

        let endLine = text.lineRange(for: NSRange(location: endLocation, length: 0))
        return NSUnionRange(startLine, endLine)
    }

    private func deleteBackwardToPlainTextListItem(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }

        let nsText = textView.string as NSString
        guard nsText.length > 0 else { return false }

        let caretLocation = min(selection.location, max(nsText.length - 1, 0))
        let lineRange = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))
        let rawLine = nsText.substring(with: NSRange(location: lineRange.location, length: min(lineRange.length, nsText.length - lineRange.location)))
        let line = rawLine.trimmingCharacters(in: .newlines)
        guard let prefixMatch = MarkdownListSupport.listPrefixMatch(in: line) else { return false }

        let prefixEnd = lineRange.location + prefixMatch.prefix.count
        guard selection.location == prefixEnd else { return false }

        let deleteRange = NSRange(location: lineRange.location, length: prefixMatch.prefix.count)
        guard textView.shouldChangeText(in: deleteRange, replacementString: "") else { return true }
        textView.textStorage?.replaceCharacters(in: deleteRange, with: "")
        textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private func deleteBackwardFromEmptyListItem(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }

        let nsText = textView.string as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        let rawLine = nsText.substring(with: NSRange(location: lineRange.location, length: min(lineRange.length, nsText.length - lineRange.location)))
        let line = rawLine.trimmingCharacters(in: .newlines)
        guard let prefixMatch = MarkdownListSupport.listPrefixMatch(in: line) else { return false }

        let contentAfterPrefix = String(line.dropFirst(prefixMatch.prefix.count)).trimmingCharacters(in: .whitespaces)
        guard contentAfterPrefix.isEmpty else { return false }

        let prefixLocation = lineRange.location
        let prefixLength = min(prefixMatch.prefix.count, max(0, selection.location - prefixLocation))
        guard prefixLength > 0 else { return false }

        let deleteRange = NSRange(location: prefixLocation, length: prefixLength)
        guard textView.shouldChangeText(in: deleteRange, replacementString: "") else { return true }
        textView.textStorage?.replaceCharacters(in: deleteRange, with: "")
        textView.setSelectedRange(NSRange(location: prefixLocation, length: 0))
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.didChangeText()
        return true
    }

    private func normalizeOrderedListMarkers(in textView: NSTextView) {
        let originalText = textView.string
        let nsText = originalText as NSString
        let lines = originalText.components(separatedBy: "\n")
        guard !lines.isEmpty else { return }

        var rebuiltLines: [String] = []
        var counters: [Int: Int] = [:]
        var previousOrderedLevel: Int? = nil

        for line in lines {
            guard let match = MarkdownListSupport.listPrefixMatch(in: line),
                  match.kind == .ordered else {
                rebuiltLines.append(line)
                counters.removeAll()
                previousOrderedLevel = nil
                continue
            }

            let level = MarkdownListSupport.orderedLevel(forIndentation: match.indentation)
            let nextIndex: Int
            if let previousOrderedLevel {
                if level > previousOrderedLevel {
                    nextIndex = 1
                } else {
                    nextIndex = (counters[level] ?? 0) + 1
                }
            } else {
                nextIndex = 1
            }

            counters = counters.filter { $0.key <= level }
            counters[level] = nextIndex
            previousOrderedLevel = level

            let expectedMarker = MarkdownStylist.orderedMarker(for: level, index: nextIndex)
            if match.marker == expectedMarker {
                rebuiltLines.append(line)
                continue
            }

            let indentationCount = match.indentation.count
            let markerStart = line.index(line.startIndex, offsetBy: indentationCount)
            let markerEnd = line.index(markerStart, offsetBy: match.marker.count)
            let updated = String(line[..<markerStart]) + expectedMarker + String(line[markerEnd...])
            rebuiltLines.append(updated)
        }

        let rebuiltText = rebuiltLines.joined(separator: "\n")
        guard rebuiltText != originalText else { return }

        let selection = textView.selectedRange()
        let adjustedLocation = adjustedSelectionOffset(in: nsText, original: originalText, updated: rebuiltText, cursorLocation: selection.location)
        textView.string = rebuiltText
        textView.setSelectedRange(NSRange(location: adjustedLocation, length: selection.length))
    }

    private func adjustedSelectionOffset(in originalText: NSString, original: String, updated: String, cursorLocation: Int) -> Int {
        var runningOriginal = 0
        var runningUpdated = 0
        let originalLines = original.components(separatedBy: "\n")
        let updatedLines = updated.components(separatedBy: "\n")

        for (originalLine, updatedLine) in zip(originalLines, updatedLines) {
            let originalLength = (originalLine as NSString).length
            let updatedLength = (updatedLine as NSString).length
            if cursorLocation <= runningOriginal + originalLength {
                let offsetWithinLine = cursorLocation - runningOriginal
                let delta = updatedLength - originalLength
                return max(0, runningUpdated + min(updatedLength, max(0, offsetWithinLine + delta)))
            }
            runningOriginal += originalLength + 1
            runningUpdated += updatedLength + 1
        }

        return min((updated as NSString).length, cursorLocation)
    }
}
#endif
