import Foundation

nonisolated struct MarkdownHeadingLine: Equatable {
    let level: Int
    let markerRange: NSRange
    let contentRange: NSRange
    let content: String
}

nonisolated struct MarkdownFencedCodeBlock: Equatable {
    let startLineIndex: Int
    let endLineIndex: Int
    let language: String?
    let content: String
    let isClosed: Bool

    var lineIndexes: ClosedRange<Int> {
        startLineIndex...endLineIndex
    }
}

nonisolated enum MarkdownBlockSupport {
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
    nonisolated static func isDividerLine(_ line: String) -> Bool {
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
        guard let reference = MarkdownImageAssetService.standaloneReferences(in: line).first,
              reference.range.location == 0,
              reference.range.length == nsLine.length else {
            return nil
        }
        return reference
    }

    /// Splits a table row on **unescaped** `|`, unescaping `\|` into a literal pipe as it goes.
    ///
    /// A raw `split(separator: "|")` treats `\|` as a column break, so one escaped pipe anywhere in
    /// a row shifts every cell after it left by one and drops the last one off the end — silently,
    /// because the row still has the right *shape*. `\|` is the only escape markdown defines inside
    /// a table cell, so any other backslash is kept verbatim: a Windows path in a cell is the
    /// user's text, not syntax.
    ///
    /// Leading and trailing delimiters are *not* removed here — `tableCells` and the row predicates
    /// each need the raw split — so `"| a | b |"` comes back as four cells, the first and last
    /// empty.
    nonisolated static func splitTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in line {
            if isEscaped {
                if character != "|" { current.append("\\") }
                current.append(character)
                isEscaped = false
                continue
            }
            switch character {
            case "\\":
                isEscaped = true
            case "|":
                cells.append(current)
                current = ""
            default:
                current.append(character)
            }
        }

        if isEscaped { current.append("\\") }
        cells.append(current)
        return cells
    }

    /// The cells a table row actually carries, before any column count is imposed on it.
    nonisolated static func tableRowCells(in line: String) -> [String] {
        let trimmed = MarkdownSourceLines.classificationText(of: line)
        var cells = splitTableRow(trimmed)

        // A leading `|` is an optional delimiter, not an empty first column. The first character
        // cannot itself be escaped, so testing the raw string is safe here.
        if cells.count > 1, trimmed.hasPrefix("|"), cells.first?.isEmpty == true {
            cells.removeFirst()
        }
        // A trailing delimiter shows up as an empty *last* cell, and only an unescaped `|` can
        // produce one — `a \|` splits to a single cell reading `a |`. So this test, unlike the one
        // above, must read the split rather than the string.
        if cells.count > 1, cells.last?.isEmpty == true {
            cells.removeLast()
        }

        return cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    nonisolated static func tableCells(in line: String, expectedCount: Int) -> [String] {
        let cells = tableRowCells(in: line)
        if cells.count >= expectedCount {
            return Array(cells.prefix(expectedCount))
        }
        return cells + Array(repeating: "", count: max(0, expectedCount - cells.count))
    }

    nonisolated static func fencedCodeBlocks(in markdown: String) -> [MarkdownFencedCodeBlock] {
        // `MarkdownSourceLines`, not `components(separatedBy: .newlines)`. The line indexes in the
        // returned blocks are looked up in line-record tables built by splitting on `"\n"`, and
        // `.newlines` inserts a phantom empty line at every `\r\n` — so a CRLF note hid the wrong
        // run and left its fences on screen. See `MarkdownSourceLines` for the full account.
        let lines = MarkdownSourceLines.texts(in: markdown)
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

    nonisolated static func openingCodeFenceLanguage(in line: String) -> String? {
        let trimmed = MarkdownSourceLines.classificationText(of: line)
        guard isOpeningCodeFence(line) else { return nil }
        let suffix = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? nil : suffix
    }

    nonisolated static func isOpeningCodeFence(_ line: String) -> Bool {
        MarkdownSourceLines.classificationText(of: line).hasPrefix("```")
    }

    /// Trims newlines as well as spaces, because a line split on `"\n"` alone keeps the `\r` of a
    /// CRLF ending — and ` ``` \r` is a closing fence in every editor that wrote it.
    nonisolated static func isClosingCodeFence(_ line: String) -> Bool {
        MarkdownSourceLines.classificationText(of: line) == "```"
    }
}
