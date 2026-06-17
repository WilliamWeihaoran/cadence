import Foundation

struct MarkdownLineBreakMutation: Equatable {
    let replacementRange: NSRange
    let replacement: String
    let selection: NSRange
}

enum MarkdownLineBreakSupport {
    static func mutation(in text: String, selection: NSRange) -> MarkdownLineBreakMutation? {
        let nsText = text as NSString
        let safeSelection = clamped(selection, length: nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: safeSelection.location, length: 0))
        let safeLineRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: nsText.length))
        guard safeLineRange.location != NSNotFound else { return nil }

        let rawLine = nsText.substring(with: safeLineRange)
        let line = rawLine.trimmingCharacters(in: .newlines)

        if let listMutation = listMutation(
            line: line,
            lineRange: safeLineRange,
            selection: safeSelection
        ) {
            return listMutation
        }

        guard let quotePrefix = quoteContinuationPrefix(after: line) else { return nil }
        let replacement = "\n\(quotePrefix)"
        return MarkdownLineBreakMutation(
            replacementRange: safeSelection,
            replacement: replacement,
            selection: NSRange(location: safeSelection.location + (replacement as NSString).length, length: 0)
        )
    }

    private static func listMutation(
        line: String,
        lineRange: NSRange,
        selection: NSRange
    ) -> MarkdownLineBreakMutation? {
        guard let prefixMatch = MarkdownListSupport.listPrefixMatch(in: line) else { return nil }

        let contentAfterPrefix = String(line.dropFirst(prefixMatch.prefix.count)).trimmingCharacters(in: .whitespaces)
        if contentAfterPrefix.isEmpty {
            return MarkdownLineBreakMutation(
                replacementRange: lineRange,
                replacement: "\n",
                selection: NSRange(location: lineRange.location + 1, length: 0)
            )
        }

        let replacement = "\n\(continuedListPrefix(for: prefixMatch))"
        return MarkdownLineBreakMutation(
            replacementRange: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0)
        )
    }

    private static func quoteContinuationPrefix(after line: String) -> String? {
        guard let quote = MarkdownQuoteSupport.lineInfo(in: line), !quote.content.isEmpty else { return nil }
        let nsLine = line as NSString
        let quotePrefix = nsLine.substring(with: quote.prefixRange)

        if let prefixMatch = MarkdownListSupport.listPrefixMatch(in: quote.content) {
            let contentAfterPrefix = String(quote.content.dropFirst(prefixMatch.prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !contentAfterPrefix.isEmpty else { return nil }
            return quotePrefix + continuedListPrefix(for: prefixMatch)
        }

        return quotePrefix
    }

    private static func continuedListPrefix(for prefixMatch: MarkdownListPrefixMatch) -> String {
        switch prefixMatch.kind {
        case .ordered:
            return prefixMatch.indentation + MarkdownListSupport.nextOrderedMarker(after: prefixMatch.marker) + " "
        case .todo, .done:
            return prefixMatch.indentation + "○ "
        case .bullet, .dash, .plus:
            return prefixMatch.prefix
        }
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let end = min(max(location, NSMaxRange(range)), length)
        return NSRange(location: location, length: max(0, end - location))
    }
}
