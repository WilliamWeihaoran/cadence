import Foundation

nonisolated enum MarkdownPreviewBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(depth: Int, text: String)
    case ordered(depth: Int, number: String, text: String)
    case checklist(depth: Int, isDone: Bool, text: String, lineIndex: Int)
    case quote(depth: Int, text: String)
    case code(language: String?, text: String)
    case image(MarkdownImageReference)
    case taskEmbed(MarkdownTaskEmbedReference)
    case table(MarkdownPreviewTable)
    case divider
}

nonisolated struct MarkdownPreviewTable: Equatable {
    let headers: [String]
    let rows: [[String]]
    /// One entry per column, from the delimiter row's colons.
    ///
    /// Carried here rather than re-derived by each preview surface: the alignment is a property of
    /// the parse, and a second parse in a view is how the live canvas and the preview came to
    /// disagree about tables in the first place.
    let alignments: [MarkdownTableAlignment]
}

nonisolated enum MarkdownPreviewParser {
    static func blocks(in markdown: String) -> [MarkdownPreviewBlock] {
        var blocks: [MarkdownPreviewBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInCodeFence = false
        let tableRows = MarkdownTableParser.rowStyles(in: markdown)
        // The same `"\n"` split `rowStyles` above and `frontmatterLineCount` below both use. This
        // read `.newlines`, which yields a phantom empty line per `\r\n` — so on markdown pasted
        // from a browser the `lineIndex` a checklist block carries pointed at the wrong line of the
        // note, and tapping the box toggled a different one.
        let lines = MarkdownSourceLines.texts(in: markdown)

        func flushParagraph() {
            let text = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        func flushCode() {
            blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n")))
            codeLines.removeAll()
            codeLanguage = nil
        }

        // Start after any YAML frontmatter rather than stripping it from `markdown` first: the
        // `lineIndex` a `.checklist` block carries is handed back to the caller to toggle that line
        // in the *original* note, so the numbering has to stay the note's own. Skipping the block
        // matters because `---` is also divider syntax and `tags: [a]` is a perfectly good
        // paragraph, so an unfiltered parse renders the block as rule / prose / rule — which is
        // what iOS's preview and every `plainPreviewText` excerpt were showing.
        var lineIndex = min(MarkdownMetadataParser.frontmatterLineCount(in: markdown), lines.count)
        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if isInCodeFence {
                if MarkdownBlockSupport.isClosingCodeFence(line) {
                    flushCode()
                    isInCodeFence = false
                } else {
                    codeLines.append(rawLine)
                }
                lineIndex += 1
                continue
            }

            if MarkdownBlockSupport.isOpeningCodeFence(line) {
                flushParagraph()
                isInCodeFence = true
                codeLanguage = MarkdownBlockSupport.openingCodeFenceLanguage(in: line)
                lineIndex += 1
                continue
            }

            if line.isEmpty {
                flushParagraph()
                lineIndex += 1
                continue
            }

            if let table = tableBlock(startingAt: lineIndex, lines: lines, tableRows: tableRows) {
                flushParagraph()
                blocks.append(.table(table.value))
                lineIndex = table.nextIndex
                continue
            }

            if let image = MarkdownBlockSupport.standaloneImageReference(in: rawLine) {
                flushParagraph()
                blocks.append(.image(image))
                lineIndex += 1
                continue
            }

            if let taskReference = MarkdownTaskEmbedParser.standaloneTaskReference(in: rawLine) {
                flushParagraph()
                blocks.append(.taskEmbed(taskReference))
                lineIndex += 1
                continue
            }

            if let heading = MarkdownBlockSupport.headingLineInfo(in: line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.content))
                lineIndex += 1
                continue
            }

            if MarkdownBlockSupport.isDividerLine(line) {
                flushParagraph()
                blocks.append(.divider)
                lineIndex += 1
                continue
            }

            if let list = listBlock(in: rawLine, lineIndex: lineIndex) {
                flushParagraph()
                blocks.append(list)
                lineIndex += 1
                continue
            }

            if let quote = MarkdownQuoteSupport.lineInfo(in: rawLine), !quote.content.isEmpty {
                flushParagraph()
                blocks.append(.quote(depth: quote.depth, text: quote.content))
                lineIndex += 1
                continue
            }

            paragraphLines.append(rawLine)
            lineIndex += 1
        }

        if isInCodeFence {
            flushCode()
        }
        flushParagraph()
        return blocks
    }

    private static func listBlock(in line: String, lineIndex: Int) -> MarkdownPreviewBlock? {
        guard let prefix = MarkdownListSupport.listPrefixMatch(in: line) else { return nil }
        let nsLine = line as NSString
        let contentLocation = min((prefix.prefix as NSString).length, nsLine.length)
        let text = nsLine.substring(from: contentLocation).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        let depth = min(max(MarkdownListSupport.visualLevel(forIndentation: prefix.indentation), 0), 6)
        switch prefix.kind {
        case .todo:
            return .checklist(depth: depth, isDone: false, text: text, lineIndex: lineIndex)
        case .done:
            return .checklist(depth: depth, isDone: true, text: text, lineIndex: lineIndex)
        case .ordered:
            return .ordered(depth: depth, number: prefix.marker, text: text)
        case .bullet, .dash, .plus:
            return .bullet(depth: depth, text: text)
        }
    }

    /// The grouping walk itself is `MarkdownTableParser.tableBlock` — shared with the iOS live
    /// styler, which had its own copy. This is only the preview's reading of the result: an empty
    /// header row means "not a table", so the caller falls through to the next block kind.
    private static func tableBlock(
        startingAt lineIndex: Int,
        lines: [String],
        tableRows: [Int: MarkdownTableRowStyle]
    ) -> (value: MarkdownPreviewTable, nextIndex: Int)? {
        guard let block = MarkdownTableParser.tableBlock(startingAt: lineIndex, lines: lines, tableRows: tableRows),
              !block.headers.isEmpty else {
            return nil
        }

        return (
            MarkdownPreviewTable(headers: block.headers, rows: block.rows, alignments: block.alignments),
            block.nextIndex
        )
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
