import Foundation

/// **A table as something you can edit, rather than something you can only parse.**
///
/// `MarkdownTableParser` answers "is there a table here and what does it say". Nothing answered
/// "put `x` in the second cell of the third row and give me the note back", which is the question a
/// hosted cell editor asks on every keystroke it commits. Every one of those answers is a pure
/// `String -> String` decision, so it lives here with tests rather than inside the AppKit text view
/// — the same division `MarkdownRenderedBlockDeletionSupport` already draws for deleting a block.
///
/// The parser is reused whole: `grids(in:)` walks `MarkdownTableParser.rowStyles` and
/// `MarkdownTableParser.tableBlock`, so there is still exactly one place that decides where a table
/// starts and stops.

/// One editable cell, addressed the way the editor thinks about it rather than the way the source
/// is laid out: `row == 0` is the header, `row >= 1` indexes `MarkdownTableBlock.rows`. **The
/// delimiter row is not addressable**, because it is not content — it is the alignment declaration,
/// and a user who could put the caret in it could unmake the table by typing one character.
nonisolated struct MarkdownTableCellAddress: Equatable, Hashable {
    let row: Int
    let column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// Where Tab / Shift-Tab lands. Three cases rather than an optional address, because "there is no
/// next cell" splits into two different actions and collapsing them to `nil` loses the difference.
nonisolated enum MarkdownTableFocusMove: Equatable {
    case cell(MarkdownTableCellAddress)
    /// Tab off the last cell of the last row. Spreadsheet behaviour is a new row, not a dead end.
    case appendRow
    /// Shift-Tab off the header's first cell. There is nothing further back inside the table.
    case leaveTable
}

/// One edit to the note's source, expressed as the minimal replacement that performs it.
///
/// Minimal rather than whole-document on purpose: the caller feeds it to
/// `shouldChangeText(in:replacementString:)` / `replaceCharacters` / `didChangeText`, which is what
/// keeps the change on `NSTextView`'s own undo stack. A whole-document rewrite would still be
/// undoable, but as one step that replaces the entire note — so `Cmd+Z` after editing a cell would
/// visibly reflow every other block in the file.
nonisolated struct MarkdownTableEdit: Equatable {
    let replacementRange: NSRange
    let replacement: String
    /// Where the cell editor should reopen once the edit lands, if it should stay open at all.
    let focus: MarkdownTableCellAddress?
}

/// A table, its source ranges, and the rows a user is allowed to put a caret in.
nonisolated struct MarkdownTableGrid: Equatable {
    let block: MarkdownTableBlock
    /// The whole table's UTF-16 range: the header line's first character to the last line's last,
    /// terminators excluded at both ends.
    let storageRange: NSRange
    /// Line ranges of the editable rows — header first, delimiter excluded — parallel to
    /// `rowLineIndexes`.
    let rowLineRanges: [NSRange]
    let rowLineIndexes: [Int]
    /// The delimiter row's own line range. Not editable, but the renderer still has to hide it.
    let delimiterLineRange: NSRange?

    var columnCount: Int { block.alignments.count }
    var rowCount: Int { rowLineRanges.count }
    var alignments: [MarkdownTableAlignment] { block.alignments }
    var startLineIndex: Int { block.lineIndexes.first ?? 0 }

    /// Every row's cells, header first, each padded to `columnCount`.
    var rows: [[String]] { [block.headers] + block.rows }

    func cells(inRow row: Int) -> [String]? {
        let all = rows
        guard row >= 0, row < all.count else { return nil }
        return all[row]
    }

    func cell(at address: MarkdownTableCellAddress) -> String? {
        guard let cells = cells(inRow: address.row),
              address.column >= 0, address.column < cells.count else { return nil }
        return cells[address.column]
    }

    func contains(utf16Location location: Int) -> Bool {
        location >= storageRange.location && location <= NSMaxRange(storageRange)
    }

    func isValid(_ address: MarkdownTableCellAddress) -> Bool {
        address.row >= 0 && address.row < rowCount && address.column >= 0 && address.column < columnCount
    }
}

nonisolated enum MarkdownTableEditor {
    // MARK: - Reading

    static func grids(in markdown: String) -> [MarkdownTableGrid] {
        let lines = MarkdownSourceLines.lines(in: markdown)
        guard !lines.isEmpty else { return [] }
        let texts = lines.map(\.text)
        let rowStyles = MarkdownTableParser.rowStyles(in: markdown)
        guard !rowStyles.isEmpty else { return [] }

        var grids: [MarkdownTableGrid] = []
        var index = 0
        while index < lines.count {
            guard let style = rowStyles[index], style.isHeader,
                  let block = MarkdownTableParser.tableBlock(startingAt: index, lines: texts, tableRows: rowStyles) else {
                index += 1
                continue
            }

            var rowLineRanges: [NSRange] = []
            var rowLineIndexes: [Int] = []
            var delimiterLineRange: NSRange?
            for lineIndex in block.lineIndexes where lineIndex < lines.count {
                if rowStyles[lineIndex]?.isDelimiter == true {
                    delimiterLineRange = lines[lineIndex].range
                } else {
                    rowLineRanges.append(lines[lineIndex].range)
                    rowLineIndexes.append(lineIndex)
                }
            }

            let first = lines[block.lineIndexes.first ?? index].range
            let last = lines[min(block.lineIndexes.last ?? index, lines.count - 1)].range
            grids.append(
                MarkdownTableGrid(
                    block: block,
                    storageRange: NSRange(location: first.location, length: NSMaxRange(last) - first.location),
                    rowLineRanges: rowLineRanges,
                    rowLineIndexes: rowLineIndexes,
                    delimiterLineRange: delimiterLineRange
                )
            )
            index = block.nextIndex
        }
        return grids
    }

    static func grid(containingUTF16Location location: Int, in markdown: String) -> MarkdownTableGrid? {
        grids(in: markdown).first { $0.contains(utf16Location: location) }
    }

    // MARK: - Serializing

    /// A cell's text as it has to appear inside a pipe-delimited row.
    ///
    /// `|` is the only character escaped, because it is the only one
    /// `MarkdownBlockSupport.splitTableRow` treats as structural — and, deliberately, a backslash
    /// is **not**. That splitter's unescape rule is asymmetric: `\X` for any `X` other than `|`
    /// comes back as *both* characters, so writing `\\` for a literal backslash reads back as two.
    /// A cell ending in a backslash still survives, because `rowSource` always puts a space before
    /// the closing pipe and the backslash escapes that space rather than the delimiter.
    ///
    /// Newlines become spaces. A hosted cell editor is a single-line control so one cannot be
    /// typed, but a paste can carry one, and a newline written straight through would split the row
    /// in half.
    static func escapedCell(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "|": escaped.append("\\|")
            case "\n", "\r": escaped.append(" ")
            default: escaped.append(character)
            }
        }
        return escaped.trimmingCharacters(in: .whitespaces)
    }

    static func rowSource(cells: [String], columnCount: Int) -> String {
        let padded = padded(cells, to: columnCount)
        return "| " + padded.map { escapedCell($0) }.joined(separator: " | ") + " |"
    }

    static func delimiterSource(alignments: [MarkdownTableAlignment], columnCount: Int) -> String {
        let padded = alignments + Array(repeating: .leading, count: max(0, columnCount - alignments.count))
        let cells = padded.prefix(columnCount).map { alignment -> String in
            switch alignment {
            case .leading: return "---"
            case .center: return ":---:"
            case .trailing: return "---:"
            }
        }
        return "| " + cells.joined(separator: " | ") + " |"
    }

    /// The whole table, header / delimiter / body, as source lines joined by `\n`.
    static func tableSource(rows: [[String]], alignments: [MarkdownTableAlignment], columnCount: Int) -> String {
        guard columnCount > 0, let header = rows.first else { return "" }
        var lines = [rowSource(cells: header, columnCount: columnCount)]
        lines.append(delimiterSource(alignments: alignments, columnCount: columnCount))
        for row in rows.dropFirst() {
            lines.append(rowSource(cells: row, columnCount: columnCount))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Editing

    /// Rewrites one row's source line with `text` in one cell.
    ///
    /// Deliberately rewrites the **line**, not the cell's own character range. A cell's range is
    /// only knowable by re-splitting the line on unescaped pipes, and the split is exactly what the
    /// edit can invalidate — typing a `|` into a cell would otherwise land as a new column boundary
    /// mid-edit. Rewriting the line means the escaping decision is made once, in `escapedCell`.
    static func settingCell(
        _ address: MarkdownTableCellAddress,
        to text: String,
        in grid: MarkdownTableGrid
    ) -> MarkdownTableEdit? {
        guard grid.isValid(address), var cells = grid.cells(inRow: address.row) else { return nil }
        cells = padded(cells, to: grid.columnCount)
        cells[address.column] = text
        let replacement = rowSource(cells: cells, columnCount: grid.columnCount)
        let range = grid.rowLineRanges[address.row]
        return MarkdownTableEdit(replacementRange: range, replacement: replacement, focus: address)
    }

    /// The edit a **committed** cell needs, or `nil` when there is nothing to write.
    ///
    /// The no-op answer is the load-bearing one, and it is here rather than in either platform's
    /// hosted-field code because both need it and neither can be trusted to keep re-deriving it.
    /// Tab across five cells without typing and every one of them commits; if each registered a
    /// text-view edit, `Cmd+Z` five times would walk back through edits the user never made. The
    /// trim is part of the same decision — `rowSource` writes `| a | b |` with a space either side
    /// of every cell, so a field handing back `" a "` is handing back the value that is already
    /// there.
    static func commit(
        _ text: String,
        at address: MarkdownTableCellAddress,
        in grid: MarkdownTableGrid
    ) -> MarkdownTableEdit? {
        guard grid.isValid(address) else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespaces)
        guard grid.cell(at: address) != normalized else { return nil }
        return settingCell(address, to: normalized, in: grid)
    }

    /// Adds an empty row directly below `row` — what Return does.
    ///
    /// A header row's "below" is the first body row, which is the line *after* the delimiter, so
    /// this anchors on the source line rather than on the row index.
    static func insertingRow(below row: Int, in grid: MarkdownTableGrid) -> MarkdownTableEdit? {
        guard row >= 0, row < grid.rowCount else { return nil }
        let anchor = row == 0 ? (grid.delimiterLineRange ?? grid.rowLineRanges[0]) : grid.rowLineRanges[row]
        let insertion = "\n" + rowSource(cells: [], columnCount: grid.columnCount)
        return MarkdownTableEdit(
            replacementRange: NSRange(location: NSMaxRange(anchor), length: 0),
            replacement: insertion,
            focus: MarkdownTableCellAddress(row: row + 1, column: 0)
        )
    }

    /// Deletes a body row. **The header cannot be deleted** — a table without one is not a table,
    /// and the delimiter row underneath it would be left as loose prose.
    static func deletingRow(_ row: Int, in grid: MarkdownTableGrid) -> MarkdownTableEdit? {
        guard row >= 1, row < grid.rowCount else { return nil }
        let line = grid.rowLineRanges[row]
        // Take the newline that precedes the line, so the rows above and below close up rather
        // than leaving a blank line that would end the table.
        let range = NSRange(location: line.location - 1, length: line.length + 1)
        return MarkdownTableEdit(
            replacementRange: range,
            replacement: "",
            focus: MarkdownTableCellAddress(row: min(row, grid.rowCount - 2), column: 0)
        )
    }

    static func insertingColumn(at column: Int, in grid: MarkdownTableGrid) -> MarkdownTableEdit? {
        guard column >= 0, column <= grid.columnCount else { return nil }
        let columnCount = grid.columnCount + 1
        let rows = grid.rows.map { row -> [String] in
            var cells = padded(row, to: grid.columnCount)
            cells.insert("", at: min(column, cells.count))
            return cells
        }
        var alignments = grid.alignments
        alignments.insert(.leading, at: min(column, alignments.count))
        return MarkdownTableEdit(
            replacementRange: grid.storageRange,
            replacement: tableSource(rows: rows, alignments: alignments, columnCount: columnCount),
            focus: MarkdownTableCellAddress(row: 0, column: column)
        )
    }

    /// Deletes a column. **The last remaining column cannot be deleted**, for the same reason the
    /// header row cannot: what is left is not a narrower table, it is no table.
    static func deletingColumn(_ column: Int, in grid: MarkdownTableGrid) -> MarkdownTableEdit? {
        guard grid.columnCount > 1, column >= 0, column < grid.columnCount else { return nil }
        let columnCount = grid.columnCount - 1
        let rows = grid.rows.map { row -> [String] in
            var cells = padded(row, to: grid.columnCount)
            cells.remove(at: column)
            return cells
        }
        var alignments = padded(grid.alignments, to: grid.columnCount, filler: .leading)
        alignments.remove(at: column)
        return MarkdownTableEdit(
            replacementRange: grid.storageRange,
            replacement: tableSource(rows: rows, alignments: alignments, columnCount: columnCount),
            focus: MarkdownTableCellAddress(row: 0, column: min(column, columnCount - 1))
        )
    }

    // MARK: - Focus

    /// Tab and Shift-Tab. Left to right, wrapping to the next row — spreadsheet behaviour, so
    /// there is nothing to learn.
    static func focus(
        after address: MarkdownTableCellAddress,
        movingForward: Bool,
        in grid: MarkdownTableGrid
    ) -> MarkdownTableFocusMove {
        guard grid.isValid(address) else { return .leaveTable }
        if movingForward {
            if address.column + 1 < grid.columnCount {
                return .cell(MarkdownTableCellAddress(row: address.row, column: address.column + 1))
            }
            if address.row + 1 < grid.rowCount {
                return .cell(MarkdownTableCellAddress(row: address.row + 1, column: 0))
            }
            return .appendRow
        }
        if address.column > 0 {
            return .cell(MarkdownTableCellAddress(row: address.row, column: address.column - 1))
        }
        if address.row > 0 {
            return .cell(MarkdownTableCellAddress(row: address.row - 1, column: grid.columnCount - 1))
        }
        return .leaveTable
    }

    // MARK: - Padding

    private static func padded(_ cells: [String], to count: Int) -> [String] {
        padded(cells, to: count, filler: "")
    }

    private static func padded<Element>(_ values: [Element], to count: Int, filler: Element) -> [Element] {
        if values.count >= count { return Array(values.prefix(count)) }
        return values + Array(repeating: filler, count: count - values.count)
    }
}
