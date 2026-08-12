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
            in: nsText,
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
        in text: NSString,
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

        // Which alphabet a lone "v."/"c." belongs to depends on the run above it, and pressing
        // return is the one path that has the whole note to read.
        let previousMarker = prefixMatch.kind == .ordered
            ? MarkdownListSupport.precedingOrderedMarker(
                in: text,
                before: lineRange,
                atLevel: MarkdownListSupport.orderedLevel(forIndentation: prefixMatch.indentation)
            )
            : nil

        let replacement = "\n\(continuedListPrefix(for: prefixMatch, precededBy: previousMarker))"
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

    /// The prefix that continues `line`, or `nil` when it is not a list line.
    ///
    /// This is the **only** definition of that question. `MarkdownListSupport.continuation`
    /// was a second one, and the two disagreed about plain bullets: it normalised a dash
    /// item to continue with the canonical bullet glyph, while this — the path the editor
    /// actually runs — returns the author's own marker verbatim, so `- item` continues as
    /// `- `. Verbatim is right: preserving the marker someone typed is what other markdown
    /// editors do, and glyph policy belongs to `normalizedMarkdownListPrefixes`, which runs
    /// separately. The disagreement was invisible because nothing covered a bullet — the
    /// dead copy's assertions were all ordered, todo, or non-list lines.
    static func continuedListPrefix(after line: String, precededBy previousMarker: String? = nil) -> String? {
        guard let match = MarkdownListSupport.listPrefixMatch(in: line) else { return nil }
        return continuedListPrefix(for: match, precededBy: previousMarker)
    }

    private static func continuedListPrefix(
        for prefixMatch: MarkdownListPrefixMatch,
        precededBy previousMarker: String? = nil
    ) -> String {
        switch prefixMatch.kind {
        case .ordered:
            let level = MarkdownListSupport.orderedLevel(forIndentation: prefixMatch.indentation)
            return prefixMatch.indentation
                + MarkdownListSupport.nextOrderedMarker(
                    after: prefixMatch.marker,
                    atLevel: level,
                    precededBy: previousMarker
                )
                + " "
        case .todo, .done:
            // Keep the spelling the line is already written in, box emptied. Continuing
            // `- [x] shipped` with `○ ` left one list written two ways and put GitHub syntax back
            // out of the document a line at a time — which is exactly what the normalizer stopped
            // doing.
            return MarkdownChecklistSupport.emptiedPrefix(in: prefixMatch.prefix)
                ?? prefixMatch.indentation + "○ "
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
