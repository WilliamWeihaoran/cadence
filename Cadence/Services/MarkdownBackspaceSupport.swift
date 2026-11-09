import Foundation

nonisolated struct MarkdownBackspaceMutation: Equatable {
    let replacementRange: NSRange
    let replacement: String
    let selection: NSRange
}

nonisolated enum MarkdownBackspaceSupport {
    /// [[T-14722]]: the caret a text view's *proposed* deletion is a Backspace from, or nil.
    ///
    /// UIKit does not ask its delegate about Backspace with the caret; it proposes the character
    /// being deleted, `(n-1, 1)`, while the selection is still the caret at `n`. AppKit's
    /// `deleteBackward:` hands the Mac the caret itself. `listPrefixMutation` reasons about a
    /// caret and refuses any range, so iOS fed it the proposal and the list-prefix rule never
    /// fired there. This turns a single-character backward deletion back into the caret it came
    /// from, so both platforms ask the same question. A forward delete (caret at the proposal's
    /// start), a ranged selection, a multi-character proposal or a typed replacement is not a
    /// Backspace from a caret and answers nil.
    static func backspaceCaret(
        forProposedDeletion range: NSRange,
        replacement: String,
        currentSelection: NSRange
    ) -> NSRange? {
        guard replacement.isEmpty,
              range.location != NSNotFound,
              range.length == 1,
              currentSelection.length == 0,
              currentSelection.location == NSMaxRange(range) else { return nil }
        return NSRange(location: NSMaxRange(range), length: 0)
    }

    static func listPrefixMutation(in text: String, selection: NSRange) -> MarkdownBackspaceMutation? {
        let nsText = text as NSString
        guard selection.length == 0, nsText.length > 0 else { return nil }

        let safeLocation = min(max(0, selection.location), nsText.length)
        // [[T-14713]]: probe the caret's own location, not `length - 1`. On the empty line after the
        // note's final newline the caret sits AT `length`, and `lineRange` answers that with the
        // empty line itself; probed one short, it read the previous line, so Backspace on a fresh
        // last line below an empty bullet deleted that bullet's marker and jumped the caret up.
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
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
