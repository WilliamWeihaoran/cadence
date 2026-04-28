#if os(macOS)
import SwiftUI
import AppKit

final class CadenceLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        for visibleRange in visibleGlyphRanges(in: glyphsToShow) {
            super.drawGlyphs(forGlyphRange: visibleRange, at: origin)
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        for visibleRange in visibleGlyphRanges(in: glyphsToShow) {
            super.drawBackground(forGlyphRange: visibleRange, at: origin)
        }
        drawQuoteBlocks(forGlyphRange: glyphsToShow, at: origin)
        drawDividerRules(forGlyphRange: glyphsToShow, at: origin)
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

final class CadenceTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: viewPoint.y - textContainerInset.height
        )

        if let layoutManager, let textContainer {
            let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
            if glyphIndex < layoutManager.numberOfGlyphs {
                let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                let nsString = string as NSString
                let lineRange = nsString.lineRange(for: NSRange(location: characterIndex, length: 0))
                let lineStartCharacter = lineRange.length > 0 ? nsString.character(at: lineRange.location) : 0
                let clickedCharacter = characterIndex < nsString.length ? nsString.character(at: characterIndex) : 0
                let isCircle: (unichar) -> Bool = { character in
                    character == 0x25CB || character == 0x25CF
                }

                if isCircle(clickedCharacter) || (isCircle(lineStartCharacter) && characterIndex <= lineRange.location + 2) {
                    let targetIndex = isCircle(clickedCharacter) ? characterIndex : lineRange.location
                    let targetCharacter = nsString.character(at: targetIndex)
                    let replacement = targetCharacter == 0x25CB ? "●" : "○"
                    let range = NSRange(location: targetIndex, length: 1)
                    if shouldChangeText(in: range, replacementString: replacement) {
                        textStorage?.replaceCharacters(in: range, with: replacement)
                        didChangeText()
                        return
                    }
                }
            }
        }

        super.mouseDown(with: event)
        snapCaretAwayFromHiddenMarkdown(preferringForward: true)
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
}

final class MarkdownEditorCoordinator: NSObject, NSTextViewDelegate {
    private var parent: MarkdownEditorView
    private let slashCommandPicker = MarkdownSlashCommandPickerController()

    init(parent: MarkdownEditorView) {
        self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        applyInputTransforms(to: textView)
        updateSlashCommandPicker(for: textView)
        normalizeOrderedListMarkers(in: textView)
        parent.text = textView.string
        MarkdownStylist.apply(to: textView)
        if let cadenceTextView = textView as? CadenceTextView {
            cadenceTextView.snapCaretAwayFromHiddenMarkdown(preferringForward: true)
        }
        if let scrollView = textView.enclosingScrollView {
            MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        }
        textView.typingAttributes = MarkdownStylist.baseAttributes
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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
                DispatchQueue.main.async { [weak self, weak textView] in
                    if let textView {
                        self?.updateSlashCommandPicker(for: textView)
                    }
                }
            }
            if deleteBackwardToPlainTextListItem(in: textView) {
                return true
            }
            return deleteBackwardFromEmptyListItem(in: textView)
        }

        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        let rawLine = nsText.substring(with: NSRange(location: lineRange.location,
                                                     length: min(lineRange.length, nsText.length - lineRange.location)))
        let line = rawLine.trimmingCharacters(in: .newlines)

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

        if cursor >= 3 {
            let range = NSRange(location: cursor - 3, length: 3)
            let snippet = nsText.substring(with: range)
            if snippet == "[ ]", MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil {
                replaceText(in: textView, range: range, with: "○ ")
                textView.setSelectedRange(NSRange(location: range.location + 2, length: 0))
                return
            }
            if snippet == "[x]", MarkdownListSupport.indentationPrefix(in: nsText, replacingRange: range) != nil {
                replaceText(in: textView, range: range, with: "● ")
                textView.setSelectedRange(NSRange(location: range.location + 2, length: 0))
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

    private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
    }

    private func updateSlashCommandPicker(for textView: NSTextView) {
        slashCommandPicker.update(for: textView, context: currentSlashCommandContext(in: textView)) { [weak self] command, context in
            self?.applySlashCommand(command, context: context, in: textView)
        }
    }

    private func currentSlashCommandContext(in textView: NSTextView) -> MarkdownSlashCommandContext? {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return nil }

        let nsText = textView.string as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        let referenceLocation = max(0, min(nsText.length == 0 ? 0 : nsText.length - 1, max(0, safeCursor - 1)))
        let lineRange = nsText.lineRange(for: NSRange(location: referenceLocation, length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: safeCursor - lineRange.location)
        let prefix = nsText.substring(with: prefixRange)

        guard let regex = try? NSRegularExpression(pattern: #"^([ \t]*)/([A-Za-z0-9]*)$"#),
              let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else {
            return nil
        }

        let indentation = (prefix as NSString).substring(with: match.range(at: 1))
        let query = (prefix as NSString).substring(with: match.range(at: 2))
        return MarkdownSlashCommandContext(
            range: prefixRange,
            indentation: indentation,
            query: query,
            cursorLocation: safeCursor
        )
    }

    private func applySlashCommand(_ command: MarkdownSlashCommand, context: MarkdownSlashCommandContext, in textView: NSTextView) {
        let replacement = context.indentation + command.replacement.text
        replaceText(in: textView, range: context.range, with: replacement)
        textView.setSelectedRange(NSRange(location: context.range.location + context.indentation.count + command.replacement.caretOffset, length: 0))
        slashCommandPicker.close()
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
        let lineRange = text.lineRange(for: NSRange(location: max(0, safeCursor - 1), length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: safeCursor - lineRange.location)
        let prefix = text.substring(with: prefixRange)
        guard let regex = try? NSRegularExpression(pattern: #"^([ \t]*)/(h1|h2|h3|todo|done|quote|rule|link|task) $"#),
              let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else {
            return nil
        }

        let indentation = (prefix as NSString).substring(with: match.range(at: 1))
        let command = (prefix as NSString).substring(with: match.range(at: 2))
        let replacementRange = NSRange(location: lineRange.location, length: prefixRange.length)
        guard let commandConfig = MarkdownSlashCommand.all.first(where: { $0.id == command }) else { return nil }
        let replacement = indentation + commandConfig.replacement.text
        return (replacementRange, replacement, indentation.count + commandConfig.replacement.caretOffset)
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
