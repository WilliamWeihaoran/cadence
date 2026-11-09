import Foundation

nonisolated struct MarkdownLinkRange: Equatable {
    let fullRange: NSRange
    let labelRange: NSRange
    let urlRange: NSRange
    let label: String
    let urlString: String

    nonisolated var url: URL? {
        URL(string: urlString)
    }
}

nonisolated enum MarkdownLinkSupport {
    /// The destination admits one level of **balanced** parentheses (T-14781).
    ///
    /// It was `\(([^)]+)\)`, which ends the destination at the first `)` whatever opened before
    /// it. A Wikipedia link -- `[Swift](https://en.wikipedia.org/wiki/Swift_(programming_language))`,
    /// the commonest real URL with a parenthesis in it, and the shape AI-written markdown pastes
    /// in -- opened `…/Swift_(programming_language` (a different page) and left a stray `)` drawn
    /// after the label. CommonMark allows balanced parentheses in a destination; one level of
    /// nesting is every URL that occurs in practice, and an `NSRegularExpression` cannot recurse.
    /// The two alternatives start on different characters, so the group cannot backtrack
    /// catastrophically. A `)` that opened nothing still ends the link, so `[a](b) (c)` is the
    /// link `b` followed by prose.
    private static let linkRegex = try! NSRegularExpression(
        pattern: #"(?<!\!)\[([^\]]+)\]\(((?:[^()]|\([^()]*\))+)\)"#
    )

    nonisolated static func linkRanges(in markdown: String) -> [MarkdownLinkRange] {
        let regex = linkRegex
        let nsMarkdown = markdown as NSString
        return regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length)).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let fullRange = match.range(at: 0)
            let labelRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            guard fullRange.location != NSNotFound,
                  labelRange.location != NSNotFound,
                  urlRange.location != NSNotFound,
                  labelRange.length > 0,
                  urlRange.length > 0 else {
                return nil
            }

            return MarkdownLinkRange(
                fullRange: fullRange,
                labelRange: labelRange,
                urlRange: urlRange,
                label: nsMarkdown.substring(with: labelRange),
                urlString: nsMarkdown.substring(with: urlRange)
            )
        }
    }

    nonisolated static func linkURL(
        atUTF16Location location: Int,
        in markdown: String,
        includesHiddenSyntax: Bool = false
    ) -> URL? {
        linkRanges(in: markdown).first { link in
            let range = includesHiddenSyntax ? link.fullRange : link.labelRange
            return NSLocationInRange(location, range)
        }?.url
    }
}
