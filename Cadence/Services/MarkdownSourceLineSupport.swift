import Foundation

/// One line of a note, with the UTF-16 range it occupies in the source.
///
/// `range` covers `text` only — never the terminator — because every consumer uses it to address
/// an `NSTextStorage` run, and a run that swallowed the newline would paint a block's styling onto
/// the line after it.
nonisolated struct MarkdownSourceLine: Equatable {
    let index: Int
    let text: String
    let range: NSRange
}

/// **The single line-splitting convention every markdown parser here uses: split on `\n`, and on
/// nothing else.**
///
/// This exists because three different conventions were live at once and were being *composed*.
/// `MarkdownTableParser.rowStyles`, the iOS styler and the macOS styler split on `"\n"`;
/// `MarkdownBlockSupport.fencedCodeBlocks` and `MarkdownPreviewParser` split on
/// `CharacterSet.newlines`; `MarkdownRenderedBlockDeletionSupport` numbered its lines with
/// `NSString.lineRange(for:)`. All three agree on LF-only text, which is what every hand-written
/// fixture is, and disagree the moment a note carries a `\r`, U+2028, U+2029 or U+0085 — which is
/// what markdown pasted from a browser, from Windows, or out of a PDF routinely carries:
///
/// - `components(separatedBy: .newlines)` treats `\r\n` as *two* separators and yields a phantom
///   empty line between them, so every line index after the first CRLF is off by one. That index
///   is then handed to a line-record table built by splitting on `"\n"` — so a fenced code block
///   hides the wrong run, and the fence itself stays on screen.
/// - `NSString.lineRange(for:)` breaks on U+2028/U+2029/U+0085 as well, so its numbering drifts
///   from both of the others.
///
/// Splitting on `"\n"` alone is the convention that wins because it is the only one where the line
/// ranges *tile the source exactly*: `sum(line.length) + (count - 1) == source.utf16.count`. The
/// stylers depend on that — they address storage by `location += length + 1` — and a parser whose
/// line count disagrees with the styler's is a mis-ranged block, not a cosmetic difference.
///
/// The cost is that a CRLF line keeps its `\r` as the last character of `text`. Line *predicates*
/// therefore trim `.whitespacesAndNewlines` rather than `.whitespaces`; a line by construction
/// holds no interior newline, so that only ever strips a stray terminator at the edges.
nonisolated enum MarkdownSourceLines {
    nonisolated static func texts(in markdown: String) -> [String] {
        markdown.components(separatedBy: "\n")
    }

    nonisolated static func lines(in markdown: String) -> [MarkdownSourceLine] {
        var lines: [MarkdownSourceLine] = []
        var location = 0
        for (index, text) in texts(in: markdown).enumerated() {
            let length = (text as NSString).length
            lines.append(MarkdownSourceLine(index: index, text: text, range: NSRange(location: location, length: length)))
            location += length + 1
        }
        return lines
    }

    /// A line reduced to what a block predicate should classify: no leading or trailing whitespace,
    /// and no stray `\r` / U+2028 / U+2029 left over from a foreign line ending.
    nonisolated static func classificationText(of line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
