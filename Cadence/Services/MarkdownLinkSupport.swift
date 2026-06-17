import Foundation

struct MarkdownLinkRange: Equatable {
    let fullRange: NSRange
    let labelRange: NSRange
    let urlRange: NSRange
    let label: String
    let urlString: String

    nonisolated var url: URL? {
        URL(string: urlString)
    }
}

enum MarkdownLinkSupport {
    nonisolated static func linkRanges(in markdown: String) -> [MarkdownLinkRange] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\!)\[([^\]]+)\]\(([^)]+)\)"#) else {
            return []
        }

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
