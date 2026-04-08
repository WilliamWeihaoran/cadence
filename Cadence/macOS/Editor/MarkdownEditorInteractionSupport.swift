#if os(macOS)
import SwiftUI
import AppKit

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
    }
}

final class MarkdownEditorCoordinator: NSObject, NSTextViewDelegate {
    private var parent: MarkdownEditorView

    init(parent: MarkdownEditorView) {
        self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        applyInputTransforms(to: textView)
        parent.text = textView.string
        MarkdownStylist.apply(to: textView)
        textView.typingAttributes = MarkdownStylist.baseAttributes
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            return adjustIndentation(in: textView, increase: true)
        }

        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return adjustIndentation(in: textView, increase: false)
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
        let targetRange = nsText.lineRange(for: selection)
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
            guard normalizedIndentWidth > 0,
                  let prefixMatch = MarkdownListSupport.listPrefixMatch(in: line) else { return line }

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

        let locationOffset = increase ? 4 : -min(4, selection.location - targetRange.location)
        let lengthDelta = (replacement as NSString).length - targetRange.length

        textView.textStorage?.replaceCharacters(in: targetRange, with: replacement)

        let newSelection = NSRange(
            location: max(targetRange.location, selection.location + locationOffset),
            length: max(0, selection.length + lengthDelta)
        )
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
    }

    private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
    }
}
#endif
