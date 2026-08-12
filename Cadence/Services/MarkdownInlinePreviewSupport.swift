import Foundation

struct MarkdownInlinePreviewSegment: Equatable {
    let text: String
    let target: MarkdownReferenceDisplayTarget?

    var shouldParseMarkdown: Bool {
        target == nil
    }
}

struct MarkdownInlinePreviewRun: Equatable {
    let text: String
    let target: MarkdownReferenceDisplayTarget?
    let linkURL: String?
    let traits: MarkdownInlinePreviewTraits

    init(
        text: String,
        target: MarkdownReferenceDisplayTarget? = nil,
        linkURL: String? = nil,
        traits: MarkdownInlinePreviewTraits = []
    ) {
        self.text = text
        self.target = target
        self.linkURL = linkURL
        self.traits = traits
    }
}

struct MarkdownInlinePreviewTraits: OptionSet, Hashable {
    let rawValue: Int

    static let bold = MarkdownInlinePreviewTraits(rawValue: 1 << 0)
    static let italic = MarkdownInlinePreviewTraits(rawValue: 1 << 1)
    static let inlineCode = MarkdownInlinePreviewTraits(rawValue: 1 << 2)
    static let strikethrough = MarkdownInlinePreviewTraits(rawValue: 1 << 3)
    static let highlight = MarkdownInlinePreviewTraits(rawValue: 1 << 4)
    static let tag = MarkdownInlinePreviewTraits(rawValue: 1 << 5)
    static let image = MarkdownInlinePreviewTraits(rawValue: 1 << 6)
}

enum MarkdownInlinePreviewSupport {
    static func segments(in markdown: String) -> [MarkdownInlinePreviewSegment] {
        MarkdownReferenceDisplaySupport.inlineSegments(in: markdown)
            .map { segment in
                MarkdownInlinePreviewSegment(text: segment.text, target: segment.target)
            }
    }

    static func runs(in markdown: String) -> [MarkdownInlinePreviewRun] {
        segments(in: markdown).flatMap { segment in
            if let target = segment.target {
                return [MarkdownInlinePreviewRun(text: segment.text, target: target)]
            }
            return styledRuns(in: segment.text)
        }
    }

    // There is no `plainText(in:)`. It was `segments(...).map(\.text).joined()` with no production
    // caller; every renderer goes through `runs`, and anything that wants the flattened string
    // should join the runs (or the segments) it is already reading.

    private static func styledRuns(in markdown: String) -> [MarkdownInlinePreviewRun] {
        let matches = inlineMatches(in: markdown)
        guard !matches.isEmpty else {
            return markdown.isEmpty ? [] : [MarkdownInlinePreviewRun(text: markdown)]
        }

        let nsMarkdown = markdown as NSString
        var runs: [MarkdownInlinePreviewRun] = []
        var cursor = 0

        for match in matches {
            guard match.fullRange.location >= cursor else { continue }
            if match.fullRange.location > cursor {
                runs.append(
                    MarkdownInlinePreviewRun(
                        text: nsMarkdown.substring(
                            with: NSRange(location: cursor, length: match.fullRange.location - cursor)
                        )
                    )
                )
            }

            runs.append(
                MarkdownInlinePreviewRun(
                    text: match.displayText ?? nsMarkdown.substring(with: match.contentRange),
                    linkURL: match.linkURL,
                    traits: match.traits
                )
            )
            cursor = NSMaxRange(match.fullRange)
        }

        if cursor < nsMarkdown.length {
            runs.append(
                MarkdownInlinePreviewRun(
                    text: nsMarkdown.substring(with: NSRange(location: cursor, length: nsMarkdown.length - cursor))
                )
            )
        }

        return runs.filter { !$0.text.isEmpty }
    }

    private static func inlineMatches(in markdown: String) -> [InlineMatch] {
        var matches: [InlineMatch] = []
        matches += regexMatches(pattern: #"\*\*\*(.+?)\*\*\*"#, traits: [.bold, .italic], priority: 10, in: markdown, normalizesContent: true)
        matches += regexMatches(pattern: #"___(.+?)___"#, traits: [.bold, .italic], priority: 10, in: markdown, normalizesContent: true)
        matches += regexMatches(pattern: #"\*\*(.+?)\*\*"#, traits: .bold, priority: 9, in: markdown, normalizesContent: true)
        matches += regexMatches(pattern: #"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#, traits: .bold, priority: 9, in: markdown, normalizesContent: true)
        matches += regexMatches(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, traits: .italic, priority: 8, in: markdown, normalizesContent: true)
        matches += regexMatches(
            pattern: #"(?<![\p{L}\p{N}_])_(?!_)(.+?)(?<!_)_(?![\p{L}\p{N}_])"#,
            traits: .italic,
            priority: 8,
            in: markdown,
            normalizesContent: true
        )
        matches += regexMatches(pattern: #"~~(.+?)~~"#, traits: .strikethrough, priority: 8, in: markdown, normalizesContent: true)
        matches += regexMatches(pattern: #"`([^`\n]+?)`"#, traits: .inlineCode, priority: 11, in: markdown)
        matches += regexMatches(pattern: #"==(.+?)=="#, traits: .highlight, priority: 8, in: markdown, normalizesContent: true)
        matches += imageMatches(in: markdown)
        matches += regexMatches(
            pattern: #"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#,
            traits: .tag,
            contentRangeIndex: 0,
            priority: 5,
            in: markdown
        )
        matches += MarkdownLinkSupport.linkRanges(in: markdown).map { link in
            InlineMatch(
                fullRange: link.fullRange,
                contentRange: link.labelRange,
                displayText: displayText(fromInlineMarkdown: link.label),
                traits: [],
                linkURL: link.urlString,
                priority: 7
            )
        }
        return nonOverlapping(matches)
    }

    private static func displayText(fromInlineMarkdown markdown: String) -> String {
        runs(in: markdown).map(\.text).joined()
    }

    private static func regexMatches(
        pattern: String,
        traits: MarkdownInlinePreviewTraits,
        contentRangeIndex: Int = 1,
        priority: Int,
        in markdown: String,
        normalizesContent: Bool = false
    ) -> [InlineMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsMarkdown = markdown as NSString
        return regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length)).compactMap { match in
            guard match.numberOfRanges > contentRangeIndex else { return nil }
            let content = match.range(at: contentRangeIndex)
            guard content.location != NSNotFound, content.length > 0 else { return nil }
            return InlineMatch(
                fullRange: match.range(at: 0),
                contentRange: content,
                displayText: normalizesContent
                    ? displayText(fromInlineMarkdown: nsMarkdown.substring(with: content))
                    : nil,
                traits: traits,
                linkURL: nil,
                priority: priority
            )
        }
    }

    private static func imageMatches(in markdown: String) -> [InlineMatch] {
        guard let regex = try? NSRegularExpression(
            pattern: #"!\[("# + MarkdownImageAssetService.altTextPattern + #")\]\(cadence-image://([0-9A-Fa-f-]{36})\)"#
        ) else { return [] }

        let nsMarkdown = markdown as NSString
        return regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length)).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let labelRange = match.range(at: 1)
            guard labelRange.location != NSNotFound else { return nil }

            let label = MarkdownImageAssetService
                .unescapedAltText(nsMarkdown.substring(with: labelRange))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return InlineMatch(
                fullRange: match.range(at: 0),
                contentRange: labelRange,
                displayText: label.isEmpty ? "Image" : label,
                traits: .image,
                linkURL: nil,
                priority: 7
            )
        }
    }

    private static func nonOverlapping(_ matches: [InlineMatch]) -> [InlineMatch] {
        let ordered = matches.sorted { lhs, rhs in
            if lhs.fullRange.location != rhs.fullRange.location {
                return lhs.fullRange.location < rhs.fullRange.location
            }
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.fullRange.length > rhs.fullRange.length
        }

        var accepted: [InlineMatch] = []
        for match in ordered {
            guard !accepted.contains(where: { NSIntersectionRange($0.fullRange, match.fullRange).length > 0 }) else {
                continue
            }
            accepted.append(match)
        }
        return accepted.sorted { $0.fullRange.location < $1.fullRange.location }
    }
}

private struct InlineMatch {
    let fullRange: NSRange
    let contentRange: NSRange
    let displayText: String?
    let traits: MarkdownInlinePreviewTraits
    let linkURL: String?
    let priority: Int
}
