import Foundation

enum MarkdownTypingTransformSupport {
    private static let typedOrderedPrefixRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)("# + MarkdownListSupport.orderedMarkerPattern + #") $"#
    )

    static func mutation(in text: String, cursor: Int) -> MarkdownFormatMutation? {
        let nsText = text as NSString
        let safeCursor = min(max(cursor, 0), nsText.length)
        guard safeCursor > 0 else { return nil }

        if let simpleListMutation = simpleListMutation(in: nsText, cursor: safeCursor) {
            return simpleListMutation
        }

        if let orderedMutation = orderedListMutation(in: nsText, cursor: safeCursor) {
            return orderedMutation
        }

        if let slashMutation = MarkdownSlashCommandMutationSupport.typedMutation(in: nsText, cursor: safeCursor) {
            return replacing(
                text: text,
                range: slashMutation.replacementRange,
                with: slashMutation.replacement,
                selection: slashMutation.selection
            )
        }

        return nil
    }

    private static func simpleListMutation(in text: NSString, cursor: Int) -> MarkdownFormatMutation? {
        if cursor >= 2 {
            let range = NSRange(location: cursor - 2, length: 2)
            let snippet = text.substring(with: range)
            if ["* ", "- ", "+ "].contains(snippet),
               let indentation = MarkdownListSupport.indentationPrefix(in: text, replacingRange: range) {
                let level = MarkdownListSupport.visualLevel(forIndentation: indentation)
                let marker = MarkdownListSupport.unorderedMarker(forLevel: level)
                return replacing(text: text as String, range: range, with: "\(marker) ")
            }
        }

        if cursor >= 4 {
            let range = NSRange(location: cursor - 4, length: 4)
            let snippet = text.substring(with: range)
            if snippet == "[ ] ",
               MarkdownListSupport.indentationPrefix(in: text, replacingRange: range) != nil {
                return replacing(text: text as String, range: range, with: "○ ")
            }
            if snippet.lowercased() == "[x] ",
               MarkdownListSupport.indentationPrefix(in: text, replacingRange: range) != nil {
                return replacing(text: text as String, range: range, with: "✓ ")
            }
        }

        if cursor >= 3 {
            let range = NSRange(location: cursor - 3, length: 3)
            let snippet = text.substring(with: range)
            if snippet == "[] ",
               MarkdownListSupport.indentationPrefix(in: text, replacingRange: range) != nil {
                return replacing(text: text as String, range: range, with: "○ ")
            }
        }

        return nil
    }

    private static func orderedListMutation(in text: NSString, cursor: Int) -> MarkdownFormatMutation? {
        guard let ordered = typedOrderedPrefixMatch(in: text, cursor: cursor) else { return nil }
        let level = MarkdownListSupport.orderedLevel(forIndentation: ordered.indentation)
        let typedIndex = MarkdownListSupport.orderedIndex(for: ordered.marker, atLevel: level) ?? 1
        let normalizedMarker = MarkdownListSupport.orderedMarker(for: level, index: typedIndex)
        let replacement = ordered.indentation + normalizedMarker + " "
        return replacing(
            text: text as String,
            range: ordered.range,
            with: replacement
        )
    }

    private static func typedOrderedPrefixMatch(
        in text: NSString,
        cursor: Int
    ) -> (range: NSRange, indentation: String, marker: String)? {
        let safeCursor = min(max(cursor, 0), text.length)
        let lineRange = text.lineRange(for: NSRange(location: max(0, safeCursor - 1), length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: safeCursor - lineRange.location)
        let prefix = text.substring(with: prefixRange)
        guard let match = typedOrderedPrefixRegex.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else {
            return nil
        }

        let indentation = (prefix as NSString).substring(with: match.range(at: 1))
        let marker = (prefix as NSString).substring(with: match.range(at: 2))
        let replacementRange = NSRange(location: lineRange.location, length: prefixRange.length)
        return (replacementRange, indentation, marker)
    }

    private static func replacing(
        text: String,
        range: NSRange,
        with replacement: String
    ) -> MarkdownFormatMutation {
        replacing(
            text: text,
            range: range,
            with: replacement,
            selection: NSRange(location: range.location + (replacement as NSString).length, length: 0)
        )
    }

    private static func replacing(
        text: String,
        range: NSRange,
        with replacement: String,
        selection: NSRange
    ) -> MarkdownFormatMutation {
        let nsText = text as NSString
        let safeRange = NSRange(
            location: min(max(0, range.location), nsText.length),
            length: min(range.length, max(0, nsText.length - min(max(0, range.location), nsText.length)))
        )
        let updatedText = nsText.replacingCharacters(in: safeRange, with: replacement)
        let updatedLength = (updatedText as NSString).length
        let clampedSelection = NSRange(
            location: min(max(0, selection.location), updatedLength),
            length: min(selection.length, max(0, updatedLength - min(max(0, selection.location), updatedLength)))
        )
        return MarkdownFormatMutation(
            text: updatedText,
            selection: clampedSelection,
            replacementRange: safeRange,
            replacement: replacement
        )
    }
}
