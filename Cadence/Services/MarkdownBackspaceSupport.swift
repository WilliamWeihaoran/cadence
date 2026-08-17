import Foundation

nonisolated struct MarkdownBackspaceMutation: Equatable {
    let replacementRange: NSRange
    let replacement: String
    let selection: NSRange
}

nonisolated enum MarkdownBackspaceSupport {
    static func listPrefixMutation(in text: String, selection: NSRange) -> MarkdownBackspaceMutation? {
        let nsText = text as NSString
        guard selection.length == 0, nsText.length > 0 else { return nil }

        let safeLocation = min(max(0, selection.location), nsText.length)
        let probeLocation = min(safeLocation, max(nsText.length - 1, 0))
        let lineRange = nsText.lineRange(for: NSRange(location: probeLocation, length: 0))
        let safeLineRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: nsText.length))
        guard safeLineRange.location != NSNotFound else { return nil }

        let rawLine = nsText.substring(with: safeLineRange)
        let line = rawLine.trimmingCharacters(in: .newlines)
        guard let prefixMatch = MarkdownListSupport.listPrefixMatch(in: line) else { return nil }

        let prefixStart = safeLineRange.location
        let prefixEnd = prefixStart + prefixMatch.prefix.count
        guard safeLocation > prefixStart else { return nil }

        let contentAfterPrefix = String(line.dropFirst(prefixMatch.prefix.count)).trimmingCharacters(in: .whitespaces)
        guard safeLocation == prefixEnd || contentAfterPrefix.isEmpty else { return nil }

        let prefixLength = min(prefixMatch.prefix.count, max(0, safeLocation - prefixStart))
        guard prefixLength > 0 else { return nil }

        return MarkdownBackspaceMutation(
            replacementRange: NSRange(location: prefixStart, length: prefixLength),
            replacement: "",
            selection: NSRange(location: prefixStart, length: 0)
        )
    }
}
