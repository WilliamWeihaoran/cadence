import Foundation

struct MarkdownHeadingLine: Equatable {
    let level: Int
    let markerRange: NSRange
    let contentRange: NSRange
    let content: String
}

struct MarkdownFencedCodeBlock: Equatable {
    let startLineIndex: Int
    let endLineIndex: Int
    let language: String?
    let content: String
    let isClosed: Bool

    var lineIndexes: ClosedRange<Int> {
        startLineIndex...endLineIndex
    }
}

enum MarkdownBlockSupport {
    static func headingLineInfo(in line: String) -> MarkdownHeadingLine? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+(.+)$"#),
              let match = regex.firstMatch(in: line, range: fullRange),
              match.numberOfRanges >= 3 else {
            return nil
        }

        let markerRange = match.range(at: 1)
        let contentRange = match.range(at: 2)
        guard markerRange.location != NSNotFound,
              contentRange.location != NSNotFound else {
            return nil
        }

        return MarkdownHeadingLine(
            level: min(max(markerRange.length, 1), 6),
            markerRange: NSRange(location: markerRange.location, length: min(nsLine.length - markerRange.location, markerRange.length + 1)),
            contentRange: contentRange,
            content: nsLine.substring(with: contentRange)
        )
    }

    /// **`---` under text is a divider in Cadence, never a setext heading.**
    ///
    /// CommonMark reads `Title` followed by `---` as an H2 and only calls a lone `---` a thematic
    /// break. Cadence deliberately does not: headings here are ATX-only end to end —
    /// `headingLineInfo` above, `MarkdownOutlineParser`, the note-title/`# ` sync, both editors'
    /// stylers and the slash-command inserts all match `#{1,6} `. Adding a second heading spelling
    /// would have to land in every one of them at once, and it would mean typing a rule under a
    /// paragraph in a *live* editor silently reformats the paragraph above the caret — which is a
    /// worse surprise than an unsupported syntax.
    ///
    /// So this stays context-free: a line of three or more `-`, `*` or `_` is a rule wherever it
    /// sits. `***` and `___` have no setext reading at all, so treating `---` the same way is also
    /// what keeps the three spellings interchangeable.
    static func isDividerLine(_ line: String) -> Bool {
        let trimmed = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" } ||
            trimmed.allSatisfy { $0 == "*" } ||
            trimmed.allSatisfy { $0 == "_" }
    }

    static func standaloneImageReference(in line: String) -> MarkdownImageReference? {
        let nsLine = line as NSString
        guard let reference = MarkdownImageAssetService.references(in: line).first,
              reference.range.location == 0,
              reference.range.length == nsLine.length else {
            return nil
        }
        return reference
    }

    static func tableCells(in line: String, expectedCount: Int) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var rawCells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if trimmed.hasPrefix("|"), !rawCells.isEmpty {
            rawCells.removeFirst()
        }
        if trimmed.hasSuffix("|"), !rawCells.isEmpty {
            rawCells.removeLast()
        }

        let cells = rawCells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if cells.count >= expectedCount {
            return Array(cells.prefix(expectedCount))
        }
        return cells + Array(repeating: "", count: max(0, expectedCount - cells.count))
    }

    static func fencedCodeBlocks(in markdown: String) -> [MarkdownFencedCodeBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }

        var blocks: [MarkdownFencedCodeBlock] = []
        var startLineIndex: Int?
        var language: String?
        var codeLines: [String] = []

        for (index, rawLine) in lines.enumerated() {
            if let currentStart = startLineIndex {
                if isClosingCodeFence(rawLine) {
                    blocks.append(
                        MarkdownFencedCodeBlock(
                            startLineIndex: currentStart,
                            endLineIndex: index,
                            language: language,
                            content: codeLines.joined(separator: "\n"),
                            isClosed: true
                        )
                    )
                    startLineIndex = nil
                    language = nil
                    codeLines.removeAll()
                } else {
                    codeLines.append(rawLine)
                }
            } else if isOpeningCodeFence(rawLine) {
                startLineIndex = index
                language = openingCodeFenceLanguage(in: rawLine)
                codeLines.removeAll()
            }
        }

        if let currentStart = startLineIndex {
            blocks.append(
                MarkdownFencedCodeBlock(
                    startLineIndex: currentStart,
                    endLineIndex: max(currentStart, lines.count - 1),
                    language: language,
                    content: codeLines.joined(separator: "\n"),
                    isClosed: false
                )
            )
        }

        return blocks
    }

    static func openingCodeFenceLanguage(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard isOpeningCodeFence(line) else { return nil }
        let suffix = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? nil : suffix
    }

    static func isOpeningCodeFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    static func isClosingCodeFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "```"
    }
}
