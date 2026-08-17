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

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let rangeEnd = min(max(location, NSMaxRange(range)), length)
        return NSRange(location: location, length: max(0, rangeEnd - location))
    }
}
