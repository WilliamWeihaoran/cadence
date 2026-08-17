import Foundation

nonisolated enum MarkdownReferenceKind: Hashable {
    case note
    case task
}

nonisolated struct MarkdownReferenceCompletionContext {
    let range: NSRange
    let kind: MarkdownReferenceKind
    let query: String
    let cursorLocation: Int
}

nonisolated enum MarkdownReferenceCompletionSupport {
    nonisolated static func context(in text: String, selection: NSRange) -> MarkdownReferenceCompletionContext? {
        guard selection.length == 0 else { return nil }

        let nsText = text as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, safeCursor - 1), length: 0))
        guard safeCursor >= lineRange.location else { return nil }

        let prefixRange = NSRange(location: lineRange.location, length: safeCursor - lineRange.location)
        let prefix = nsText.substring(with: prefixRange)
        let nsPrefix = prefix as NSString
        let openRange = nsPrefix.range(of: "[[", options: .backwards)
        guard openRange.location != NSNotFound else { return nil }

        let tokenStart = NSMaxRange(openRange)
        let token = nsPrefix.substring(with: NSRange(location: tokenStart, length: max(0, nsPrefix.length - tokenStart)))
        guard isValidToken(token) else { return nil }

        let lowercased = token.lowercased()
        let kind: MarkdownReferenceKind
        let query: String
        if lowercased.hasPrefix("task:") {
            kind = .task
            query = String(token.dropFirst(5))
        } else if lowercased.hasPrefix("note:") {
            kind = .note
            query = String(token.dropFirst(5))
        } else {
            kind = .note
            query = token
        }

        return MarkdownReferenceCompletionContext(
            range: NSRange(location: lineRange.location + openRange.location, length: safeCursor - lineRange.location - openRange.location),
            kind: kind,
            query: query,
            cursorLocation: safeCursor
        )
    }

    nonisolated private static func isValidToken(_ token: String) -> Bool {
        token.count <= 80 &&
            !token.contains("[") &&
            !token.contains("]") &&
            !token.contains("\n")
    }
}
