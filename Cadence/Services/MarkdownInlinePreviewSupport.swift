import Foundation

nonisolated struct MarkdownInlinePreviewSegment: Equatable {
    let text: String
    let target: MarkdownReferenceDisplayTarget?

    var shouldParseMarkdown: Bool {
        target == nil
    }
}

nonisolated struct MarkdownInlinePreviewRun: Equatable {
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

nonisolated struct MarkdownInlinePreviewTraits: OptionSet, Hashable {
    let rawValue: Int

    static let bold = MarkdownInlinePreviewTraits(rawValue: 1 << 0)
    static let italic = MarkdownInlinePreviewTraits(rawValue: 1 << 1)
    static let inlineCode = MarkdownInlinePreviewTraits(rawValue: 1 << 2)
    static let strikethrough = MarkdownInlinePreviewTraits(rawValue: 1 << 3)
    static let highlight = MarkdownInlinePreviewTraits(rawValue: 1 << 4)
    static let tag = MarkdownInlinePreviewTraits(rawValue: 1 << 5)
    static let image = MarkdownInlinePreviewTraits(rawValue: 1 << 6)
}

nonisolated enum MarkdownInlinePreviewSupport {
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

    /// **The ten inline patterns, each compiled once per process and each written down once in
    /// the tree.**
    ///
    /// This was ten `#"…"#` literals handed to a generic `regexMatches(pattern:…)` helper that did
    /// `try? NSRegularExpression(pattern:)` on every call — so ten constant patterns were compiled
    /// for every inline string a preview rendered ([[T-1660]]). The nine emphasis patterns are
    /// `MarkdownInlineEmphasisPatterns`', shared with `MarkdownInlineSpanSupport`'s span table and
    /// (for five of them) with `MarkdownStylist`'s cached regexes; the tenth is the tag pattern,
    /// which `MarkdownMetadataParser` owns because it is the one file in all three targets, and
    /// which `MarkdownInlineMarkerRanges` aliases for the stylers.
    ///
    /// **The reason is the duplication, not the time.** [[T-1484]] measured a construction of this
    /// shape at ~2µs because `NSRegularExpression` caches compiled patterns internally, and
    /// `inlineMatches` runs once per inline string rather than once per line.
    ///
    /// The order is the order the ten were appended in before the table existed, image matches
    /// still between the highlight rule and the tag rule. `nonOverlapping` sorts by location, then
    /// priority, then length, and `Array.sorted` is not documented as stable — so the append order
    /// is kept rather than argued about.
    private static let emphasisRules: [InlineRule] = [
        InlineRule(MarkdownInlineEmphasisPatterns.boldItalicAsteriskRegex, traits: [.bold, .italic], priority: 10, normalizesContent: true),
        InlineRule(MarkdownInlineEmphasisPatterns.boldItalicUnderscoreRegex, traits: [.bold, .italic], priority: 10, normalizesContent: true),
        InlineRule(MarkdownInlineEmphasisPatterns.boldAsteriskRegex, traits: .bold, priority: 9, normalizesContent: true),
        InlineRule(MarkdownInlineEmphasisPatterns.boldUnderscoreRegex, traits: .bold, priority: 9, normalizesContent: true),
        InlineRule(MarkdownInlineEmphasisPatterns.italicAsteriskRegex, traits: .italic, priority: 8, normalizesContent: true),
        InlineRule(MarkdownInlineEmphasisPatterns.italicUnderscoreRegex, traits: .italic, priority: 8, normalizesContent: true),
        InlineRule(MarkdownInlineEmphasisPatterns.strikethroughRegex, traits: .strikethrough, priority: 8, normalizesContent: true),
        InlineRule(MarkdownInlineEmphasisPatterns.codeRegex, traits: .inlineCode, priority: 11),
        InlineRule(MarkdownInlineEmphasisPatterns.highlightRegex, traits: .highlight, priority: 8, normalizesContent: true),
    ].compactMap { $0 }

    /// The tag rule, kept out of the table above because it is the one whose content range is the
    /// whole match (`#tag` is drawn with its `#`) and the one whose pattern another file owns.
    private static let tagRule: InlineRule? = InlineRule(
        MarkdownInlineMarkerRanges.hashtagRegex,
        traits: .tag,
        contentRangeIndex: 0,
        priority: 5
    )

    private static func inlineMatches(in markdown: String) -> [InlineMatch] {
        var matches: [InlineMatch] = []
        for rule in emphasisRules {
            matches += regexMatches(rule, in: markdown)
        }
        matches += imageMatches(in: markdown)
        if let tagRule {
            matches += regexMatches(tagRule, in: markdown)
        }
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

    /// One compiled inline pattern plus the four numbers that decide what a match becomes.
    ///
    /// The initialiser is failable and the table above is `compactMap`ped, so a pattern that would
    /// not compile drops out of the sweep — which is exactly what the old
    /// `guard let regex = try? … else { return [] }` did for that one pattern, and nothing else.
    private struct InlineRule {
        let regex: NSRegularExpression
        let traits: MarkdownInlinePreviewTraits
        let contentRangeIndex: Int
        let priority: Int
        let normalizesContent: Bool

        init?(
            _ regex: NSRegularExpression?,
            traits: MarkdownInlinePreviewTraits,
            contentRangeIndex: Int = 1,
            priority: Int,
            normalizesContent: Bool = false
        ) {
            guard let regex else { return nil }
            self.regex = regex
            self.traits = traits
            self.contentRangeIndex = contentRangeIndex
            self.priority = priority
            self.normalizesContent = normalizesContent
        }
    }

    private static func regexMatches(_ rule: InlineRule, in markdown: String) -> [InlineMatch] {
        let nsMarkdown = markdown as NSString
        return rule.regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length)).compactMap { match in
            guard match.numberOfRanges > rule.contentRangeIndex else { return nil }
            let content = match.range(at: rule.contentRangeIndex)
            guard content.location != NSNotFound, content.length > 0 else { return nil }
            return InlineMatch(
                fullRange: match.range(at: 0),
                contentRange: content,
                displayText: rule.normalizesContent
                    ? displayText(fromInlineMarkdown: nsMarkdown.substring(with: content))
                    : nil,
                traits: rule.traits,
                linkURL: nil,
                priority: rule.priority
            )
        }
    }

    private static func imageMatches(in markdown: String) -> [InlineMatch] {
        // The unanchored form of the reference pattern, shared with the iOS live styler through
        // `MarkdownInlineMarkerRanges`. It was written out here and there as two identical literals;
        // `MarkdownImageAssetService`'s own copy is deliberately *not* the same regex — it is line
        // anchored, because it matches the standalone-image block rather than an inline reference.
        //
        // [[T-1520]]: this read `inlineImageReferencePattern` and compiled it on every call, once
        // per inline string, although `MarkdownImageAssetService` had already compiled the same
        // bytes into a stored property. The reason for the change is that duplication and the
        // one-spelling rule — [[T-1484]] measured this shape at ~2µs a call, so the time is not
        // the argument. `inlineImageReferenceRegex` **is** that stored object, not a copy.
        let regex = MarkdownInlineMarkerRanges.inlineImageReferenceRegex

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
