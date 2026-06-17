import Foundation

enum MarkdownPreviewBlock: Equatable {
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

struct MarkdownPreviewTable: Equatable {
    let headers: [String]
    let rows: [[String]]
}

enum MarkdownPreviewParser {
    static func blocks(in markdown: String) -> [MarkdownPreviewBlock] {
        var blocks: [MarkdownPreviewBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInCodeFence = false
        let tableRows = MarkdownTableParser.rowStyles(in: markdown)
        let lines = markdown.components(separatedBy: .newlines)

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

        var lineIndex = 0
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

    private static func tableBlock(
        startingAt lineIndex: Int,
        lines: [String],
        tableRows: [Int: MarkdownTableRowStyle]
    ) -> (value: MarkdownPreviewTable, nextIndex: Int)? {
        guard let headerStyle = tableRows[lineIndex], headerStyle.isHeader else {
            return nil
        }

        let headers = MarkdownBlockSupport.tableCells(in: lines[lineIndex], expectedCount: headerStyle.columnCount)
        guard !headers.isEmpty else { return nil }

        var rows: [[String]] = []
        var cursor = lineIndex + 1
        while cursor < lines.count, let style = tableRows[cursor] {
            if !style.isDelimiter {
                rows.append(MarkdownBlockSupport.tableCells(in: lines[cursor], expectedCount: headerStyle.columnCount))
            }
            cursor += 1
        }

        return (MarkdownPreviewTable(headers: headers, rows: rows), cursor)
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
