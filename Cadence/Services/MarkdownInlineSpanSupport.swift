import Foundation

nonisolated enum MarkdownInlineSpanKind: Equatable {
    case boldItalic
    case bold
    case italic
    case strikethrough
    case code
    case highlight
}

/// One inline run a styler has to act on: the whole match, the content inside the markers, and the
/// marker runs to hide.
nonisolated struct MarkdownInlineSpan: Equatable {
    let kind: MarkdownInlineSpanKind
    let fullRange: NSRange
    let contentRange: NSRange
    let markerRanges: [NSRange]
}

/// **Which inline runs a live editor styles, and which it must leave alone.**
///
/// This used to live inside `iOSMarkdownStyler` as ten private methods that each ran a regex and
/// wrote attributes in the same breath, which meant the *decisions* — is this `**` inside a code
/// span, does emphasis get to eat a backtick, which markers are hidden — could only be tested
/// through a `UIKit` `NSAttributedString`. The two tests that did so sat under `#if os(iOS)` in a
/// test target that builds for macOS, so they had never once executed.
///
/// Splitting the decision from the drawing is what makes it testable, and it is also the half both
/// editors should eventually share: macOS re-implements the same precedence with its own regexes.
///
/// **Order is behaviour, not tidiness.** The spans come back in application order — bold-italic
/// before bold before italic, so `***x***` is not consumed as `**` + a stray `*`; code after the
/// emphasis passes, so `**Review `API` today**` styles the emphasis *and* keeps the code markers
/// intact. A caller must apply them in the order given.
nonisolated enum MarkdownInlineSpanSupport {
    /// Full ranges of `` `inline code` ``, backticks included.
    ///
    /// Callers use these two ways: as the *protected* set that stops emphasis, links, tags and
    /// highlights from styling anything inside a code span, and as the code spans themselves.
    nonisolated static func codeRanges(in markdown: String) -> [NSRange] {
        Compiled.code.flatMap { matches(of: $0, in: markdown) }.map(\.range)
    }

    nonisolated static func spans(in markdown: String, excluding excludedRanges: [NSRange] = []) -> [MarkdownInlineSpan] {
        let codeRanges = codeRanges(in: markdown)
        var spans: [MarkdownInlineSpan] = []

        func collect(_ kind: MarkdownInlineSpanKind, _ regexes: [NSRegularExpression], protectedByCode: Bool = true) {
            for regex in regexes {
                for match in matches(of: regex, in: markdown) {
                    guard match.numberOfRanges >= 2 else { continue }
                    let full = match.range(at: 0)
                    let content = match.range(at: 1)
                    guard content.location != NSNotFound else { continue }
                    guard shouldStyle(
                        full,
                        excluding: excludedRanges,
                        protecting: protectedByCode ? codeRanges : []
                    ) else { continue }
                    spans.append(MarkdownInlineSpan(
                        kind: kind,
                        fullRange: full,
                        contentRange: content,
                        markerRanges: markerRanges(fullRange: full, contentRange: content)
                    ))
                }
            }
        }

        collect(.boldItalic, Compiled.boldItalic)
        collect(.bold, Compiled.bold)
        collect(.italic, Compiled.italic)
        collect(.strikethrough, Compiled.strikethrough)
        // No code protection for code itself: every code span is contained in a code range — its
        // own — so protecting it against that set would reject all of them.
        collect(.code, Compiled.code, protectedByCode: false)
        collect(.highlight, Compiled.highlight)

        return spans
    }

    /// A match is styled when it does not touch an excluded block and is not swallowed whole by a
    /// code span.
    ///
    /// The two tests differ deliberately. *Excluded* ranges are block runs — a fenced code block, a
    /// table row, a divider — and any overlap at all disqualifies the match, because a marker half
    /// inside a table row would hide characters the table canvas is drawing from. *Protected*
    /// ranges are inline code, where only full containment disqualifies: `**Review `API` today**`
    /// straddles a code span and is still bold.
    nonisolated static func shouldStyle(
        _ range: NSRange,
        excluding excludedRanges: [NSRange],
        protecting protectedRanges: [NSRange] = []
    ) -> Bool {
        guard range.location != NSNotFound, range.length > 0 else { return false }
        guard !excludedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else {
            return false
        }
        return !protectedRanges.contains { protected in
            range.location >= protected.location && NSMaxRange(range) <= NSMaxRange(protected)
        }
    }

    /// The opening and closing marker runs of a match: everything in `fullRange` that is not
    /// `contentRange`.
    nonisolated static func markerRanges(fullRange: NSRange, contentRange: NSRange) -> [NSRange] {
        let opening = NSRange(
            location: fullRange.location,
            length: max(0, contentRange.location - fullRange.location)
        )
        let closingStart = NSMaxRange(contentRange)
        let closing = NSRange(
            location: closingStart,
            length: max(0, NSMaxRange(fullRange) - closingStart)
        )
        return [opening, closing].filter { $0.length > 0 }
    }

    /// The compiled form of the six families, grouped the way `spans` applies them.
    ///
    /// Each array is `compactMap`ped over `try?`, so a pattern that would not compile drops out of
    /// its family exactly as the old per-call `guard let regex = try? … else { return [] }` dropped
    /// it from a single call. Nothing here spells a pattern out: the strings are
    /// `MarkdownInlineEmphasisPatterns`', which the inline preview and the macOS styler also read.
    private enum Compiled {
        nonisolated static let boldItalic = [
            MarkdownInlineEmphasisPatterns.boldItalicAsteriskRegex,
            MarkdownInlineEmphasisPatterns.boldItalicUnderscoreRegex
        ].compactMap { $0 }
        nonisolated static let bold = [
            MarkdownInlineEmphasisPatterns.boldAsteriskRegex,
            MarkdownInlineEmphasisPatterns.boldUnderscoreRegex
        ].compactMap { $0 }
        nonisolated static let italic = [
            MarkdownInlineEmphasisPatterns.italicAsteriskRegex,
            MarkdownInlineEmphasisPatterns.italicUnderscoreRegex
        ].compactMap { $0 }
        nonisolated static let strikethrough = [MarkdownInlineEmphasisPatterns.strikethroughRegex].compactMap { $0 }
        nonisolated static let code = [MarkdownInlineEmphasisPatterns.codeRegex].compactMap { $0 }
        nonisolated static let highlight = [MarkdownInlineEmphasisPatterns.highlightRegex].compactMap { $0 }
    }

    nonisolated private static func matches(of regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}

/// **The one spelling of each inline emphasis pattern, and the one compiled form of it.**
///
/// Nine literals that three passes over the same markdown each used to write out for themselves:
/// this file's span table, `MarkdownInlinePreviewSupport.inlineMatches` — which handed every one of
/// them to a generic `regexMatches(pattern:…)` helper, so all nine were compiled again on **every
/// inline string** — and, for five of the nine, `MarkdownStylist`'s cached-regex block in
/// `macOS/Editor/MarkdownEditorSupport.swift`, spelled with backslash escapes rather than as raw
/// literals so a search for one spelling could not see the other. Measured on 2026-09-30, before
/// the change: twenty-six occurrences of the ten patterns across five files.
///
/// **What they decide is the same question three times** — which run of a note is bold, which is
/// italic, which is code — asked by the renderer, by the iOS live styler and by the macOS live
/// styler. A character edited into one of them and not the others is a note that renders one way
/// and edits another, which is the drift [[T-1484]] and [[T-1521]] were both filed about.
///
/// **No speed claim is made.** [[T-1484]] measured a construction of this shape at ~2µs, because
/// `NSRegularExpression` caches compiled patterns internally; `inlineMatches` runs once per inline
/// string, not once per line. The reason for the change is the duplication and the one-spelling
/// rule. [[T-1660]].
///
/// The compiled properties are `try?` rather than `try!` because that is what both Services
/// readers did per call; `MarkdownStylist` keeps its own `try!` and reads the **pattern**, which is
/// each site's own answer to a pattern that will not compile ([[T-1521]]'s distinction).
nonisolated enum MarkdownInlineEmphasisPatterns {
    /// `***bold italic***`.
    nonisolated static let boldItalicAsterisk = #"\*\*\*(.+?)\*\*\*"#
    /// `___bold italic___`.
    nonisolated static let boldItalicUnderscore = #"___(.+?)___"#
    /// `**bold**`.
    nonisolated static let boldAsterisk = #"\*\*(.+?)\*\*"#
    /// `__bold__`.
    nonisolated static let boldUnderscore = #"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#
    /// `*italic*`.
    nonisolated static let italicAsterisk = #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#
    /// `_italic_`. The underscore form refuses to fire inside a word, so `snake_case_name` is not
    /// two italics.
    nonisolated static let italicUnderscore = #"(?<![\p{L}\p{N}_])_(?!_)(.+?)(?<!_)_(?![\p{L}\p{N}_])"#
    nonisolated static let strikethrough = #"~~(.+?)~~"#
    nonisolated static let code = #"`([^`\n]+?)`"#
    nonisolated static let highlight = #"==(.+?)=="#

    nonisolated static let boldItalicAsteriskRegex = try? NSRegularExpression(pattern: boldItalicAsterisk)
    nonisolated static let boldItalicUnderscoreRegex = try? NSRegularExpression(pattern: boldItalicUnderscore)
    nonisolated static let boldAsteriskRegex = try? NSRegularExpression(pattern: boldAsterisk)
    nonisolated static let boldUnderscoreRegex = try? NSRegularExpression(pattern: boldUnderscore)
    nonisolated static let italicAsteriskRegex = try? NSRegularExpression(pattern: italicAsterisk)
    nonisolated static let italicUnderscoreRegex = try? NSRegularExpression(pattern: italicUnderscore)
    nonisolated static let strikethroughRegex = try? NSRegularExpression(pattern: strikethrough)
    nonisolated static let codeRegex = try? NSRegularExpression(pattern: code)
    nonisolated static let highlightRegex = try? NSRegularExpression(pattern: highlight)
}
