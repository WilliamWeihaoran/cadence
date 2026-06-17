import Foundation

enum MarkdownFormatCommand: Hashable {
    case bold
    case italic
    case inlineCode
    case strikethrough
    case highlight
    case link
    case paragraph
    case heading(Int)
    case orderedList
    case unorderedList
    case todoList
    case quote
    case codeBlock
    case divider
    case noteLink
    case taskReference
    case insertMarkdown(String)
    case replaceMarkdown(location: Int, length: Int, markdown: String)
    case replaceMarkdownWithCaret(location: Int, length: Int, markdown: String, caretOffset: Int)
}

struct MarkdownFormatMutation {
    let text: String
    let selection: NSRange
    let replacementRange: NSRange
    let replacement: String
}

enum MarkdownFormatCommandSupport {
    static func apply(
        _ command: MarkdownFormatCommand,
        text: String,
        selection: NSRange
    ) -> MarkdownFormatMutation {
        switch command {
        case .bold:
            return toggleInlineMarker("**", text: text, selection: selection)
        case .italic:
            return toggleInlineMarker("*", text: text, selection: selection)
        case .inlineCode:
            return toggleInlineMarker("`", text: text, selection: selection)
        case .strikethrough:
            return toggleInlineMarker("~~", text: text, selection: selection)
        case .highlight:
            return toggleInlineMarker("==", text: text, selection: selection)
        case .link:
            return insertLink(text: text, selection: selection)
        case .paragraph:
            return rewriteSelectedLines(text: text, selection: selection) { line, _ in
                removeBlockPrefix(from: line)
            }
        case .heading(let level):
            return rewriteSelectedLines(text: text, selection: selection) { line, _ in
                toggleHeading(level: level, in: line)
            }
        case .orderedList:
            return rewriteSelectedLines(text: text, selection: selection) { line, _ in
                toggleList(kind: .ordered, in: line)
            }
        case .unorderedList:
            return rewriteSelectedLines(text: text, selection: selection) { line, _ in
                toggleList(kind: .unordered, in: line)
            }
        case .todoList:
            return rewriteSelectedLines(text: text, selection: selection) { line, _ in
                toggleList(kind: .todo, in: line)
            }
        case .quote:
            return rewriteSelectedLines(text: text, selection: selection) { line, _ in
                toggleQuote(in: line)
            }
        case .codeBlock:
            return insertBlock("```\n\(selectedText(in: text, selection: selection))\n```", text: text, selection: selection, innerOffset: 4)
        case .divider:
            return insertBlock("---", text: text, selection: selection)
        case .noteLink:
            return insertSnippet("[[]]", caretOffset: 2, text: text, selection: selection)
        case .taskReference:
            return insertSnippet("[[task:]]", caretOffset: 7, text: text, selection: selection)
        case .insertMarkdown(let markdown):
            return insertSnippet(markdown, caretOffset: (markdown as NSString).length, text: text, selection: selection)
        case .replaceMarkdown(let location, let length, let markdown):
            return insertSnippet(
                markdown,
                caretOffset: (markdown as NSString).length,
                text: text,
                selection: NSRange(location: location, length: length)
            )
        case .replaceMarkdownWithCaret(let location, let length, let markdown, let caretOffset):
            return insertSnippet(
                markdown,
                caretOffset: caretOffset,
                text: text,
                selection: NSRange(location: location, length: length)
            )
        }
    }

    private static func toggleInlineMarker(
        _ marker: String,
        text: String,
        selection: NSRange
    ) -> MarkdownFormatMutation {
        let nsText = text as NSString
        let safeSelection = clamped(selection, length: nsText.length)
        let markerLength = (marker as NSString).length

        if safeSelection.length == 0,
           safeSelection.location >= markerLength,
           safeSelection.location + markerLength <= nsText.length,
           hasMarkerPair(marker, openLocation: safeSelection.location - markerLength, closeLocation: safeSelection.location, in: nsText) {
            return replacing(
                text: text,
                range: NSRange(location: safeSelection.location - markerLength, length: markerLength * 2),
                with: "",
                selectionOffset: 0,
                selectionLength: 0
            )
        }

        if safeSelection.length > 0 {
            let selected = nsText.substring(with: safeSelection)
            if isSelfWrapped(selected, marker: marker), (selected as NSString).length > markerLength * 2 {
                let inner = (selected as NSString).substring(
                    with: NSRange(location: markerLength, length: (selected as NSString).length - markerLength * 2)
                )
                return replacing(text: text, range: safeSelection, with: inner, selectionOffset: 0, selectionLength: (inner as NSString).length)
            }

            if safeSelection.location >= markerLength,
               NSMaxRange(safeSelection) + markerLength <= nsText.length,
               hasMarkerPair(marker, openLocation: safeSelection.location - markerLength, closeLocation: NSMaxRange(safeSelection), in: nsText) {
                return replacing(
                    text: text,
                    range: NSRange(location: safeSelection.location - markerLength, length: safeSelection.length + markerLength * 2),
                    with: selected,
                    selectionOffset: 0,
                    selectionLength: safeSelection.length
                )
            }

            let replacement = marker + selected + marker
            return replacing(
                text: text,
                range: safeSelection,
                with: replacement,
                selectionOffset: markerLength,
                selectionLength: safeSelection.length
            )
        }

        let replacement = marker + marker
        return replacing(text: text, range: safeSelection, with: replacement, selectionOffset: markerLength, selectionLength: 0)
    }

    private static func isSelfWrapped(_ text: String, marker: String) -> Bool {
        guard text.hasPrefix(marker), text.hasSuffix(marker) else { return false }
        guard marker == "*" else { return true }
        return !text.hasPrefix("**") && !text.hasSuffix("**")
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

    private static func insertLink(text: String, selection: NSRange) -> MarkdownFormatMutation {
        let selected = selectedText(in: text, selection: selection)
        let label = selected.isEmpty ? "text" : selected
        let replacement = "[\(label)](url)"
        let urlLocation = (replacement as NSString).length - 4
        return replacing(
            text: text,
            range: clamped(selection, length: (text as NSString).length),
            with: replacement,
            selectionOffset: urlLocation,
            selectionLength: 3
        )
    }

    private static func insertSnippet(
        _ snippet: String,
        caretOffset: Int,
        text: String,
        selection: NSRange
    ) -> MarkdownFormatMutation {
        replacing(
            text: text,
            range: clamped(selection, length: (text as NSString).length),
            with: snippet,
            selectionOffset: caretOffset,
            selectionLength: 0
        )
    }

    private static func insertBlock(
        _ block: String,
        text: String,
        selection: NSRange,
        innerOffset: Int? = nil
    ) -> MarkdownFormatMutation {
        let nsText = text as NSString
        let safeSelection = clamped(selection, length: nsText.length)
        let needsLeadingBreak = safeSelection.location > 0 && !nsText.substring(to: safeSelection.location).hasSuffix("\n")
        let needsTrailingBreak = NSMaxRange(safeSelection) < nsText.length && !nsText.substring(from: NSMaxRange(safeSelection)).hasPrefix("\n")
        let replacement = "\(needsLeadingBreak ? "\n" : "")\(block)\(needsTrailingBreak ? "\n" : "")"
        let caretOffset = innerOffset.map { (needsLeadingBreak ? 1 : 0) + $0 } ?? (replacement as NSString).length

        return replacing(
            text: text,
            range: safeSelection,
            with: replacement,
            selectionOffset: caretOffset,
            selectionLength: 0
        )
    }

    private static func rewriteSelectedLines(
        text: String,
        selection: NSRange,
        transform: (String, Int) -> String
    ) -> MarkdownFormatMutation {
        let nsText = text as NSString
        let safeSelection = clamped(selection, length: nsText.length)
        let lineRange = effectiveLineRange(for: safeSelection, in: nsText)
        let selectedLines = nsText.substring(with: lineRange)
        let hasTrailingNewline = selectedLines.hasSuffix("\n")
        let rawLines = selectedLines.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let editableLines = hasTrailingNewline ? Array(rawLines.dropLast()) : rawLines
        let replacementBody = editableLines.enumerated().map { index, line in
            transform(line, index)
        }
        .joined(separator: "\n")
        let replacement = replacementBody + (hasTrailingNewline ? "\n" : "")
        let selectionOffset: Int
        let selectionLength: Int
        if safeSelection.length == 0,
           let originalFirstLine = editableLines.first,
           let replacementFirstLine = replacementBody.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).first {
            let originalOffset = max(0, safeSelection.location - lineRange.location)
            let originalPrefixLength = markupPrefixLength(in: originalFirstLine)
            let replacementPrefixLength = markupPrefixLength(in: replacementFirstLine)
            let adjustedOffset: Int
            if originalOffset <= originalPrefixLength {
                adjustedOffset = replacementPrefixLength
            } else {
                adjustedOffset = originalOffset + replacementPrefixLength - originalPrefixLength
            }
            selectionOffset = max(0, min((replacement as NSString).length, adjustedOffset))
            selectionLength = 0
        } else {
            selectionOffset = 0
            selectionLength = (replacement as NSString).length
        }

        return replacing(
            text: text,
            range: lineRange,
            with: replacement,
            selectionOffset: selectionOffset,
            selectionLength: selectionLength
        )
    }

    private static func selectedText(in text: String, selection: NSRange) -> String {
        let nsText = text as NSString
        let safeSelection = clamped(selection, length: nsText.length)
        guard safeSelection.length > 0 else { return "" }
        return nsText.substring(with: safeSelection)
    }

    private static func replacing(
        text: String,
        range: NSRange,
        with replacement: String,
        selectionOffset: Int,
        selectionLength: Int
    ) -> MarkdownFormatMutation {
        let nsText = text as NSString
        let safeRange = clamped(range, length: nsText.length)
        let updated = nsText.replacingCharacters(in: safeRange, with: replacement)
        let nextSelection = NSRange(
            location: safeRange.location + selectionOffset,
            length: min(selectionLength, max(0, (updated as NSString).length - safeRange.location - selectionOffset))
        )
        return MarkdownFormatMutation(
            text: updated,
            selection: nextSelection,
            replacementRange: safeRange,
            replacement: replacement
        )
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let rangeEnd = min(max(location, NSMaxRange(range)), length)
        return NSRange(location: location, length: max(0, rangeEnd - location))
    }

    private static func toggleHeading(level: Int, in line: String) -> String {
        let clampedLevel = min(max(level, 1), 6)
        let prefix = String(repeating: "#", count: clampedLevel) + " "
        guard let heading = headingPrefix(in: line) else {
            return prefix + line.trimmingCharacters(in: .whitespaces)
        }

        let content = String(line.dropFirst(heading.prefixLength))
        if heading.level == clampedLevel {
            return content
        }
        return prefix + content
    }

    private static func removeBlockPrefix(from line: String) -> String {
        if let heading = headingPrefix(in: line) {
            return String(line.dropFirst(heading.prefixLength))
        }
        if let prefix = listPrefix(in: line) {
            return prefix.indentation + prefix.content
        }
        let indentation = leadingWhitespace(in: line)
        let content = String(line.dropFirst(indentation.count))
        if content.hasPrefix("> ") {
            return indentation + String(content.dropFirst(2))
        }
        if content == ">" {
            return indentation
        }
        return line
    }

    private static func toggleList(kind: MarkdownFormatListKind, in line: String) -> String {
        guard !line.isEmpty else { return kind.emptyLinePrefix }
        if let prefix = listPrefix(in: line) {
            if prefix.kind == kind.normalized {
                return prefix.indentation + prefix.content
            }
            return prefix.indentation + kind.prefix(forIndentation: prefix.indentation) + prefix.content
        }

        let indentation = leadingWhitespace(in: line)
        let content = String(line.dropFirst(indentation.count))
        return indentation + kind.prefix(forIndentation: indentation) + content
    }

    private static func toggleQuote(in line: String) -> String {
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

    private static func headingPrefix(in line: String) -> (level: Int, prefixLength: Int)? {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^#{1,6}\s+"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        let prefix = nsLine.substring(with: match.range)
        return (prefix.filter { $0 == "#" }.count, match.range.length)
    }

    private static func listPrefix(in line: String) -> MarkdownFormatListPrefix? {
        guard let match = MarkdownListSupport.listPrefixMatch(in: line) else { return nil }
        let kind: MarkdownFormatListKind
        switch match.kind {
        case .ordered:
            kind = .ordered
        case .todo, .done:
            kind = .todo
        case .bullet, .dash, .plus:
            kind = .unordered
        }
        let content = String(line.dropFirst(match.prefix.count))
        return MarkdownFormatListPrefix(
            indentation: match.indentation,
            content: content,
            kind: kind.normalized,
            prefixLength: match.prefix.count
        )
    }

    private static func leadingWhitespace(in line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
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
        if let prefix = listPrefix(in: line) {
            return prefix.prefixLength
        }
        return quotePrefixLength(in: line)
    }
}

private enum MarkdownFormatListKind: Equatable {
    case ordered
    case unordered
    case todo

    var normalized: MarkdownFormatListKind {
        self
    }

    func prefix(forIndentation indentation: String) -> String {
        switch self {
        case .ordered:
            return MarkdownListSupport.orderedMarker(forIndentation: indentation) + " "
        case .unordered:
            return "• "
        case .todo:
            return "○ "
        }
    }

    var emptyLinePrefix: String {
        prefix(forIndentation: "")
    }
}

private struct MarkdownFormatListPrefix {
    let indentation: String
    let content: String
    let kind: MarkdownFormatListKind
    let prefixLength: Int
}
