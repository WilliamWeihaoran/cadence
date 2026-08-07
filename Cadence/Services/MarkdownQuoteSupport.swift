import Foundation

struct MarkdownQuoteLine: Equatable {
    let prefixRange: NSRange
    let contentRange: NSRange
    let depth: Int
    let content: String
}

enum MarkdownQuoteSupport {
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

    static func continuation(after line: String) -> String? {
        guard let quote = lineInfo(in: line), !quote.content.isEmpty else { return nil }

        let nsLine = line as NSString
        let prefix = nsLine.substring(with: quote.prefixRange)
        if let listContinuation = MarkdownListSupport.continuation(after: quote.content) {
            return prefix + listContinuation
        }

        return prefix
    }

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
