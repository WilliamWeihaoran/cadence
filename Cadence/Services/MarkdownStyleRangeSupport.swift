import Foundation

/// **Which runs of a note a styler is allowed to touch, and where a block starts and ends.**
///
/// Every function here decides something about a *string* — no font, no colour, no attribute. That
/// is the whole reason the file exists: this logic used to sit inside `iOSMarkdownStyler`, under
/// `#if os(iOS)`, where the macOS-built `CadenceTests` target cannot see it. The layer whose bugs
/// get reported (a heading marker that will not hide, a code fence that stays rendered while the
/// caret is inside it, an inline pass that styles a table cell's pipes) was the one layer with no
/// coverage at all.
///
/// These are written to be callable from either platform rather than shaped around iOS's call
/// sites, and macOS has since taken them up: `MarkdownEditorSupport.heading` re-derived the
/// visible-content test inline — with the *wrong* character set — until T-181 routed it through
/// `hasVisibleHeadingContent` here.
nonisolated enum MarkdownStyleRanges {
    /// Whether an ATX heading has anything after its marker that a reader would see.
    ///
    /// This is the difference between hiding the `#` and dimming it. `MarkdownBlockSupport.headingLineInfo`
    /// already requires *some* character after the marker, so the case this catches is a heading
    /// whose content is only whitespace: hiding the marker there leaves a line that looks empty and
    /// cannot be clicked back into, so the marker stays visible and dimmed instead.
    ///
    /// `markerRange` is `MarkdownHeadingLine.markerRange`, which already includes the single space
    /// after the hashes.
    static func hasVisibleHeadingContent(in line: String, markerRange: NSRange) -> Bool {
        let nsLine = line as NSString
        let contentStart = min(nsLine.length, markerRange.location + markerRange.length)
        let contentLength = max(0, nsLine.length - contentStart)
        guard contentLength > 0 else { return false }
        return !nsLine.substring(with: NSRange(location: contentStart, length: contentLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// The single storage range spanned by a run of consecutive source lines.
    ///
    /// Built from the first line's start to the last line's end rather than by summing lengths, so
    /// the line terminators between them are included and the result addresses the block as one
    /// paragraph run.
    static func combinedLineRange(
        for lineIndexes: ClosedRange<Int>,
        recordsByIndex: [Int: MarkdownSourceLine]
    ) -> NSRange? {
        let records = lineIndexes.compactMap { recordsByIndex[$0] }
        guard let first = records.first, let last = records.last else { return nil }
        return NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
    }

    /// Whether a block should show its own source instead of a rendered canvas.
    ///
    /// True when the caret is inside it. Both the fenced-code pass and the table pass need this and
    /// each had its own `NSIntersectionRange(...).length > 0` spelling; a rendered block whose
    /// source you cannot get back to is unrecoverable, so the test is worth having in one place.
    static func isRevealed(_ blockRange: NSRange, by revealedBlockRange: NSRange?) -> Bool {
        guard let revealedBlockRange else { return false }
        return NSIntersectionRange(blockRange, revealedBlockRange).length > 0
    }

    /// The runs an inline pass must leave alone.
    ///
    /// Inline styling is a document-wide regex sweep, so without this a `*` inside a fenced code
    /// block turns the code italic, a `|` row's pipes get marker-hidden, and a divider or a
    /// standalone image/task-embed line — whose whole range is already replaced by a drawn canvas —
    /// gets a second, conflicting set of attributes.
    ///
    /// The emptiness test goes through `MarkdownSourceLines.classificationText`, which is the
    /// convention that file documents: lines are split on `"\n"` alone, so a CRLF line keeps its
    /// `\r` and a line *predicate* has to trim `.whitespacesAndNewlines`. T-121 moved a
    /// `.whitespaces`-only spelling here verbatim rather than correcting it in a relocation pass,
    /// with a note that it reached the same answer anyway; **that was checked under T-181 and it
    /// does — this switch is inert, not a fix.** The two spellings differ only on a line made
    /// entirely of whitespace plus at least one newline-class character (`"\r"`, `" \u{2028} "`),
    /// and every such line fails all three predicates below: neither standalone reference can match
    /// without brackets, and `isDividerLine` trims `.whitespacesAndNewlines` itself before requiring
    /// three of `-`/`*`/`_`. `MarkdownStyleRangeSupportTests` pins that.
    static func inlineStyleExclusionRanges(
        lineRecords: [MarkdownSourceLine],
        tableRows: [Int: MarkdownTableRowStyle],
        codeBlocks: [MarkdownFencedCodeBlock]
    ) -> [NSRange] {
        let recordsByIndex = Dictionary(uniqueKeysWithValues: lineRecords.map { ($0.index, $0) })
        var ranges: [NSRange] = codeBlocks.compactMap { block in
            combinedLineRange(for: block.lineIndexes, recordsByIndex: recordsByIndex)
        }

        ranges += tableRows.keys.compactMap { recordsByIndex[$0]?.range }

        for record in lineRecords {
            let trimmed = MarkdownSourceLines.classificationText(of: record.text)
            guard !trimmed.isEmpty else { continue }
            if MarkdownBlockSupport.standaloneImageReference(in: record.text) != nil ||
                MarkdownTaskEmbedParser.standaloneTaskReference(in: record.text) != nil ||
                MarkdownBlockSupport.isDividerLine(trimmed) {
                ranges.append(record.range)
            }
        }

        return ranges.filter { $0.length > 0 }
    }
}

/// One `![alt](cadence-image://<uuid>)` reference, as three ranges in the source.
nonisolated struct MarkdownInlineImageReference: Equatable {
    let fullRange: NSRange
    /// The alt text. Can be present but **empty** — `![](cadence-image://…)` is legal — which is a
    /// different case from absent, because an empty label means there is no text to style and the
    /// raw URL is shown dimmed instead of being hidden.
    let labelRange: NSRange
    let idRange: NSRange

    var hasLabel: Bool { labelRange.location != NSNotFound && labelRange.length > 0 }
}

/// **Which characters of an inline marker disappear.**
///
/// Pure `NSRange` arithmetic, extracted from the iOS styler because it is the arithmetic the user
/// sees when it is wrong: a length that is one too long swallows the first character of a link's
/// label, one too short leaves a stray `]` or `#` on screen, and either way the caret then has to
/// step over a run that does not match the syntax it is meant to be hiding.
nonisolated enum MarkdownInlineMarkerRanges {
    /// A `#tag`, not preceded by a letter, digit or underscore.
    ///
    /// The lookbehind is what keeps `C#` and `id_#4` from becoming tags; the tag body deliberately
    /// starts with an alphanumeric so a bare `#-` or `#_` is not one either.
    static let hashtagPattern = #"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#

    /// The unanchored form of `MarkdownImageAssetService`'s reference pattern — the anchored one
    /// there matches only a line that is *nothing but* an image, which is the standalone-block case.
    static let inlineImageReferencePattern =
        #"!\[("# + MarkdownImageAssetService.altTextPattern + #")\]\(cadence-image://([0-9A-Fa-f-]{36})\)"#

    static func hashtagRanges(in markdown: String) -> [NSRange] {
        matchRanges(of: hashtagPattern, in: markdown).map { $0.range }
    }

    static func imageReferences(in markdown: String) -> [MarkdownInlineImageReference] {
        matchRanges(of: inlineImageReferencePattern, in: markdown).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let full = match.range(at: 0)
            let label = match.range(at: 1)
            let id = match.range(at: 2)
            guard full.location != NSNotFound, id.location != NSNotFound else { return nil }
            return MarkdownInlineImageReference(fullRange: full, labelRange: label, idRange: id)
        }
    }

    /// The three runs of an image reference that are not its alt text: `![`, `](cadence-image://`
    /// and the id plus `)`.
    ///
    /// Only correct when the reference `hasLabel` — with no label there is nothing left visible, so
    /// the styler shows the id rather than hiding it.
    static func hiddenRanges(for reference: MarkdownInlineImageReference) -> [NSRange] {
        let full = reference.fullRange
        let label = reference.labelRange
        let id = reference.idRange
        return [
            NSRange(location: full.location, length: max(0, label.location - full.location)),
            NSRange(location: label.location + label.length, length: max(0, id.location - (label.location + label.length))),
            NSRange(location: id.location, length: max(0, NSMaxRange(full) - id.location))
        ]
    }

    /// The runs of a `[label](url)` link that are syntax: the opening `[`, the `](` between the two
    /// halves, and the closing `)`.
    ///
    /// The middle range is measured between the two halves instead of assuming `](` is two
    /// characters, because `MarkdownLinkSupport` allows whitespace there.
    static func hiddenRanges(forLink full: NSRange, label: NSRange, url: NSRange) -> [NSRange] {
        [
            NSRange(location: full.location, length: 1),
            NSRange(location: label.location + label.length, length: max(0, url.location - (label.location + label.length))),
            NSRange(location: url.location + url.length, length: max(0, NSMaxRange(full) - (url.location + url.length)))
        ]
    }

    /// The `[[` and `]]` of a wiki reference, plus any prefix the display form drops (`task:`).
    static func hiddenRanges(forReference full: NSRange, hiddenPrefixUTF16Length: Int) -> [NSRange] {
        var ranges = [
            NSRange(location: full.location, length: 2),
            NSRange(location: NSMaxRange(full) - 2, length: 2)
        ]
        if hiddenPrefixUTF16Length > 0 {
            ranges.append(NSRange(location: full.location + 2, length: hiddenPrefixUTF16Length))
        }
        return ranges
    }

    private static func matchRanges(of pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}

nonisolated extension NSRange {
    /// The same range, moved to a document-absolute location.
    ///
    /// Every line-level matcher here reports ranges relative to the line it was handed, and every
    /// styler applies them to whole-document storage. Doing that by hand at the call site is how a
    /// marker ends up hidden one line away from the marker.
    func shifted(by offset: Int) -> NSRange {
        NSRange(location: location + offset, length: length)
    }
}
