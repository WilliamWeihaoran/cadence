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
        matches(of: Pattern.code, in: markdown).map(\.range)
    }

    nonisolated static func spans(in markdown: String, excluding excludedRanges: [NSRange] = []) -> [MarkdownInlineSpan] {
        let codeRanges = codeRanges(in: markdown)
        var spans: [MarkdownInlineSpan] = []

        func collect(_ kind: MarkdownInlineSpanKind, _ patterns: [String], protectedByCode: Bool = true) {
            for pattern in patterns {
                for match in matches(of: pattern, in: markdown) {
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

        collect(.boldItalic, Pattern.boldItalic)
        collect(.bold, Pattern.bold)
        collect(.italic, Pattern.italic)
        collect(.strikethrough, [Pattern.strikethrough])
        // No code protection for code itself: every code span is contained in a code range — its
        // own — so protecting it against that set would reject all of them.
        collect(.code, [Pattern.code], protectedByCode: false)
        collect(.highlight, [Pattern.highlight])

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

    private enum Pattern {
        /// Both `***bold italic***` and `___bold italic___`.
        nonisolated static let boldItalic = [#"\*\*\*(.+?)\*\*\*"#, #"___(.+?)___"#]
        /// Both `**bold**` and `__bold__`.
        nonisolated static let bold = [#"\*\*(.+?)\*\*"#, #"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#]
        /// Both `*italic*` and `_italic_`. The underscore form refuses to fire inside a word, so
        /// `snake_case_name` is not two italics.
        nonisolated static let italic = [
            #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
            #"(?<![\p{L}\p{N}_])_(?!_)(.+?)(?<!_)_(?![\p{L}\p{N}_])"#
        ]
        nonisolated static let strikethrough = #"~~(.+?)~~"#
        nonisolated static let code = #"`([^`\n]+?)`"#
        nonisolated static let highlight = #"==(.+?)=="#
    }

    nonisolated private static func matches(of pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}
