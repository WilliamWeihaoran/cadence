#if os(macOS)
import AppKit

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

enum MarkdownKeyboardShortcutSupport {
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
#endif
