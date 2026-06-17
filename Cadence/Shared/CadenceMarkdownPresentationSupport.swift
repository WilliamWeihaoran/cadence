import Foundation

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

    private static func normalizedInlineText(_ markdown: String) -> String {
        let text = MarkdownInlinePreviewSupport.runs(in: markdown)
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
