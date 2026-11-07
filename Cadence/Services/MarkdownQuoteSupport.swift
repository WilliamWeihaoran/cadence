import Foundation

nonisolated struct MarkdownQuoteLine: Equatable {
    let prefixRange: NSRange
    let contentRange: NSRange
    let depth: Int
    let content: String
}

/// A list or checklist item written inside a blockquote: `> - [ ] todo`, `> 1. step`.
nonisolated struct MarkdownQuotedListLine: Equatable {
    let quote: MarkdownQuoteLine
    /// The list item read from the text after `quote.prefixRange`, with every range already in the
    /// WHOLE line's coordinates — the quote prefix is never part of the list's own `prefixRange`.
    let list: MarkdownListLineInfo
}

nonisolated enum MarkdownQuoteSupport {
    /// Both indents of a quote paragraph at `depth`: the gutter the rail is drawn in, plus a step
    /// per nesting level. Shared by the macOS and iOS stylers, which each spelled `18 + 12·(d-1)`,
    /// and by a quoted list line, which must keep its marker inside the rail ([[T-12282]]).
    static func paragraphIndent(depth: Int) -> CGFloat {
        18 + CGFloat(max(depth - 1, 0)) * 12
    }

    /// The list item inside a quote line, or nil when the line is not quoted or what follows the
    /// quote prefix is not a list item.
    ///
    /// Both editors' stylers used to stop at the quote: a line that matched the blockquote branch
    /// never reached the list branch, so `> - [ ] todo` drew a quote rail with the literal
    /// characters `- [ ] todo` beside it, on BOTH platforms ([[T-12282]]). Return-continuation
    /// already read a list after the prefix (`MarkdownLineBreakSupport.quoteContinuationPrefix`),
    /// so continuation and styling disagreed about the same line. This reads it the same way —
    /// `lineInfo` for the prefix, `MarkdownListSupport` for what follows — so the two agree by
    /// construction.
    static func listLineInfo(in line: String) -> MarkdownQuotedListLine? {
        guard let quote = lineInfo(in: line) else { return nil }
        let nsLine = line as NSString
        let offset = NSMaxRange(quote.prefixRange)
        guard offset < nsLine.length,
              let list = MarkdownListSupport.lineInfo(in: nsLine.substring(from: offset)) else {
            return nil
        }
        return MarkdownQuotedListLine(quote: quote, list: list.shifted(by: offset))
    }

    private static let quoteRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(>\s*)+"#)

    static func lineInfo(in line: String) -> MarkdownQuoteLine? {
        let regex = quoteRegex
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else {
            return nil
        }

        let prefixRange = match.range(at: 0)
        guard prefixRange.location != NSNotFound, prefixRange.length > 0 else {
            return nil
        }

        let depth = nsLine.substring(with: prefixRange).filter { $0 == ">" }.count
        guard depth > 0 else { return nil }

        let rawContentRange = NSRange(
            location: min(NSMaxRange(prefixRange), nsLine.length),
            length: max(0, nsLine.length - min(NSMaxRange(prefixRange), nsLine.length))
        )
        let contentRange = trimmedRange(rawContentRange, in: nsLine)
        let content = contentRange.length > 0 ? nsLine.substring(with: contentRange) : ""

        return MarkdownQuoteLine(
            prefixRange: prefixRange,
            contentRange: contentRange,
            depth: min(depth, 6),
            content: content
        )
    }

    // Quote continuation on Return is **not** here. It lives on the live editor path,
    // `MarkdownLineBreakSupport.quoteContinuationPrefix`. A second `continuation(after:)` used to
    // sit beside `lineInfo` with no production caller, and the two had already drifted: this one
    // normalised `> - item` to `> • `, while the editor keeps `> - `.

    private static func trimmedRange(_ range: NSRange, in text: NSString) -> NSRange {
        var location = range.location
        var length = range.length

        while length > 0,
              isWhitespace(text.character(at: location)) {
            location += 1
            length -= 1
        }

        while length > 0,
              isWhitespace(text.character(at: location + length - 1)) {
            length -= 1
        }

        return NSRange(location: location, length: length)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(UInt32(character)) else { return false }
        return CharacterSet.whitespaces.contains(scalar)
    }
}
