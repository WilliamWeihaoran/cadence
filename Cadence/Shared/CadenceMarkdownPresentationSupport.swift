import Foundation
import SwiftUI

enum CadenceMarkdownPresentationSupport {
    static func plainPreviewText(from markdown: String, limit: Int? = nil) -> String {
        var fragments: [String] = []
        for block in MarkdownPreviewParser.blocks(in: markdown) {
            for fragment in previewFragments(from: block) {
                let normalized = normalizedInlineText(fragment)
                if !normalized.isEmpty {
                    fragments.append(normalized)
                }
            }
        }

        let text = fragments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard let limit, text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func previewFragments(from block: MarkdownPreviewBlock) -> [String] {
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

    private static func normalizedInlineText(_ markdown: String) -> String {
        let text = MarkdownInlinePreviewSupport.runs(in: markdown)
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
