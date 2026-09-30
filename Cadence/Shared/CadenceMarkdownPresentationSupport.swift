import Foundation
import SwiftUI

enum CadenceMarkdownPresentationSupport {
    /// The whole document flattened into one scannable run — every block joined with a space,
    /// markers resolved, optionally cut at `limit`.
    ///
    /// This is the **search** shape, and it is deliberately not the list-row shape. A search row
    /// answers "what is in this note", so it has to reach past the first block to the words the
    /// query might have matched, and `limit` is what keeps that run from being a whole note. A
    /// list row answers a different question — "what does this note open with" — and its answer
    /// feeds a one-line slot that is sometimes the row's *title*. `plainRowExcerpt` is that shape.
    static func plainPreviewText(from markdown: String, limit: Int? = nil) -> String {
        let text = plainPreviewLines(from: markdown)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let limit, text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One plain-text line per block that has anything to say, in document order.
    ///
    /// `plainPreviewText` is exactly this joined with spaces — the two shapes share one reader so
    /// a note cannot read one way in a list row and another way in search, which is the split
    /// T-1700 was filed for.
    static func plainPreviewLines(from markdown: String) -> [String] {
        MarkdownPreviewParser.blocks(in: markdown).compactMap(plainLine(from:))
    }

    /// The note's opening line for a list row: the first block with anything on it, markers
    /// resolved, so `## Level two` reads "Level two" rather than being drawn verbatim.
    ///
    /// `belowTitleHeading` drops a leading `# H1` whose own text is that title, for the rows that
    /// draw the title themselves and would otherwise print the same string twice. It is matched on
    /// the *parsed* heading rather than by string-equality against `"# \(title)"`, which is what
    /// `#  Markdown Smoke` — an H1 with two spaces, which `MarkdownNoteTitleSync` still takes the
    /// title from — used to slip through. Only a **leading** H1 is dropped: an `# H1` further down
    /// the body is a section heading, not the document's name, and `MarkdownNoteTitleSync` reads it
    /// the same way.
    static func plainRowExcerpt(
        from markdown: String,
        belowTitleHeading title: String? = nil
    ) -> String? {
        var blocks = MarkdownPreviewParser.blocks(in: markdown)[...]
        if let title {
            let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = blocks.first,
               case .heading(let level, let text) = first,
               level == 1,
               normalizedInlineText(text) == wanted {
                blocks = blocks.dropFirst()
            }
        }
        return blocks.lazy.compactMap(plainLine(from:)).first
    }

    /// A single block as one plain line, or `nil` when it carries no text at all — a divider, a
    /// bare image with no alt text.
    ///
    /// `nonisolated`, as are the two helpers it calls: these are pure functions of a parsed block,
    /// and `plainPreviewLines` passes this one to `compactMap` as a *value*, which carries no
    /// isolation with it.
    nonisolated private static func plainLine(from block: MarkdownPreviewBlock) -> String? {
        let text = previewFragments(from: block)
            .map(normalizedInlineText)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    nonisolated private static func previewFragments(from block: MarkdownPreviewBlock) -> [String] {
        switch block {
        case .heading(_, let text),
             .paragraph(let text),
             .bullet(_, let text),
             .ordered(_, _, let text),
             .checklist(_, _, let text, _),
             .quote(_, let text):
            return [text]
        case .code(_, let text):
            return text.split(whereSeparator: \.isNewline).map(String.init)
        case .image(let reference):
            let altText = reference.altText.trimmingCharacters(in: .whitespacesAndNewlines)
            return altText.isEmpty ? [] : [altText]
        case .taskEmbed(let reference):
            let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? [] : [title]
        case .table(let table):
            return table.headers + table.rows.flatMap { $0 }
        case .divider:
            return []
        }
    }

    // MARK: - Table alignment

    /// The alignment a table cell in `column` should be drawn with.
    ///
    /// `:---:` and `---:` are parsed into `MarkdownPreviewTable.alignments`, and until now only the
    /// live editor canvas read them — the read-only preview drew every cell left, so opening a note
    /// with a right-aligned numeric column in preview silently reshaped it. Alignment is the one
    /// piece of table syntax with no other way to express it, so the two surfaces disagreeing about
    /// it is a content difference, not a styling one.
    ///
    /// The rule lives here rather than in the view because the view is inside `#if os(iOS)`, where
    /// the macOS-built test target cannot see it — the same reason `CadenceTodayLayoutSupport`
    /// exists. Columns past the end of `alignments` fall back to `.leading`, which is markdown's own
    /// default for a delimiter cell with no colons and what both surfaces drew unconditionally
    /// before.
    static func tableColumnAlignment(
        _ column: Int,
        in alignments: [MarkdownTableAlignment]
    ) -> MarkdownTableAlignment {
        alignments.indices.contains(column) ? alignments[column] : .leading
    }

    /// How a cell's own text lays out when it wraps to a second line.
    static func tableColumnTextAlignment(
        _ column: Int,
        in alignments: [MarkdownTableAlignment]
    ) -> TextAlignment {
        switch tableColumnAlignment(column, in: alignments) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    /// Where a cell sits inside the fixed-width slot the preview grid gives it.
    ///
    /// Vertically always `.top`: preview rows are top-aligned so a wrapped cell does not drag the
    /// single-line cells beside it down to its own centre. Only the horizontal half comes from the
    /// delimiter row.
    static func tableCellAlignment(
        _ column: Int,
        in alignments: [MarkdownTableAlignment]
    ) -> Alignment {
        switch tableColumnAlignment(column, in: alignments) {
        case .leading: return .topLeading
        case .center: return .top
        case .trailing: return .topTrailing
        }
    }

    nonisolated private static func normalizedInlineText(_ markdown: String) -> String {
        let text = MarkdownInlinePreviewSupport.runs(in: markdown)
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
