import Foundation

nonisolated enum MarkdownInsertionSupport {
    static func paddedBlockInsertion(
        _ markdown: String,
        in text: String,
        selection: NSRange
    ) -> String {
        let nsText = text as NSString
        let safeSelection = clamped(selection, length: nsText.length)

        let needsLeadingBreak: Bool
        if safeSelection.location == 0 {
            needsLeadingBreak = false
        } else {
            let previous = nsText.substring(with: NSRange(location: max(0, safeSelection.location - 1), length: 1))
            needsLeadingBreak = previous != "\n"
        }

        let needsTrailingBreak: Bool
        if NSMaxRange(safeSelection) >= nsText.length {
            needsTrailingBreak = false
        } else {
            let next = nsText.substring(with: NSRange(location: NSMaxRange(safeSelection), length: 1))
            needsTrailingBreak = next != "\n"
        }

        return (needsLeadingBreak ? "\n\n" : "") + markdown + (needsTrailingBreak ? "\n\n" : "\n")
    }

    /// T-11492: whether the selection's first or last line is a task reference standing alone,
    /// which `MarkdownTaskEmbedParser.standaloneTaskReference` draws as a card. Anything written
    /// onto that line — at its end or its start — makes the reference inline text and the card
    /// vanishes, and the card shows no caret, so the user cannot see the insertion point is there.
    static func selectionTouchesStandaloneTaskEmbedLine(in text: String, selection: NSRange) -> Bool {
        let nsText = text as NSString
        let safeSelection = clamped(selection, length: nsText.length)
        let probes = [safeSelection.location, NSMaxRange(safeSelection)]
        return probes.contains { location in
            let line = nsText.substring(with: nsText.lineRange(for: NSRange(location: location, length: 0)))
            return MarkdownTaskEmbedParser.standaloneTaskReference(in: line) != nil
        }
    }

    /// An inline reference (a note link or task reference chosen from a picker) is written into the
    /// line as is, except on a task-embed card's line, where it would break the card: there it
    /// goes on its own line exactly as a block would. Nil means "insert inline as you normally do",
    /// so each platform keeps its own inline padding.
    static func blockPaddedInsertionIfOnTaskEmbedLine(
        _ markdown: String,
        in text: String,
        selection: NSRange
    ) -> String? {
        guard selectionTouchesStandaloneTaskEmbedLine(in: text, selection: selection) else { return nil }
        return paddedBlockInsertion(markdown, in: text, selection: selection)
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let rangeEnd = min(max(location, NSMaxRange(range)), length)
        return NSRange(location: location, length: max(0, rangeEnd - location))
    }
}
