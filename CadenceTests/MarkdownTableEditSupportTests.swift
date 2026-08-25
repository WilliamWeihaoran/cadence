import Foundation
import Testing
@testable import Cadence

/// The markdown half of T-221: every decision a hosted table cell editor makes about the note's
/// source, tested as a value rather than as a rendering.
struct MarkdownTableEditSupportTests {
    private static let markdown = """
    Intro paragraph.

    | Item | Qty | Note |
    | :--- | ---: | :---: |
    | Bolt | 4 | spare |
    | Nut | 12 |  |

    Outro paragraph.
    """

    private func parseGrid(_ markdown: String = markdown) throws -> MarkdownTableGrid {
        try #require(MarkdownTableEditor.grids(in: markdown).first)
    }

    private func applying(_ edit: MarkdownTableEdit, to markdown: String) -> String {
        (markdown as NSString).replacingCharacters(in: edit.replacementRange, with: edit.replacement)
    }

    // MARK: - Reading

    @Test func aGridExcludesTheDelimiterRowFromTheRowsAUserCanEdit() throws {
        let grid = try parseGrid()
        #expect(grid.rowCount == 3)
        #expect(grid.columnCount == 3)
        #expect(grid.rowLineIndexes == [2, 4, 5])
        #expect(grid.delimiterLineRange != nil)
        #expect(grid.cells(inRow: 0) == ["Item", "Qty", "Note"])
        #expect(grid.cells(inRow: 1) == ["Bolt", "4", "spare"])
        #expect(grid.cells(inRow: 2) == ["Nut", "12", ""])
    }

    @Test func aGridsStorageRangeCoversTheWholeTableAndNothingElse() throws {
        let grid = try parseGrid()
        let covered = (Self.markdown as NSString).substring(with: grid.storageRange)
        #expect(covered.hasPrefix("| Item |"))
        #expect(covered.hasSuffix("| Nut | 12 |  |"))
        #expect(!covered.contains("Intro"))
        #expect(!covered.contains("Outro"))
    }

    @Test func alignmentsComeFromTheDelimiterRow() throws {
        let grid = try parseGrid()
        #expect(grid.alignments == [.leading, .trailing, .center])
    }

    @Test func twoTablesInOneNoteAreTwoGrids() {
        let markdown = """
        | a | b |
        | - | - |
        | 1 | 2 |

        between

        | c | d |
        | - | - |
        """
        let grids = MarkdownTableEditor.grids(in: markdown)
        #expect(grids.count == 2)
        #expect(grids[0].rowCount == 2)
        #expect(grids[1].rowCount == 1)
    }

    @Test func aLocationInsideATableFindsThatTable() throws {
        let grid = try parseGrid()
        let inside = grid.storageRange.location + 3
        #expect(MarkdownTableEditor.grid(containingUTF16Location: inside, in: Self.markdown)?.storageRange == grid.storageRange)
        #expect(MarkdownTableEditor.grid(containingUTF16Location: 2, in: Self.markdown) == nil)
    }

    // MARK: - Cell edits

    @Test func settingACellRewritesOnlyThatRowsLine() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.settingCell(.init(row: 1, column: 2), to: "ordered", in: grid))
        #expect(edit.replacement == "| Bolt | 4 | ordered |")
        let updated = applying(edit, to: Self.markdown)
        #expect(updated.contains("| Bolt | 4 | ordered |"))
        #expect(updated.contains("| Nut | 12 |  |"))
        #expect(updated.contains("Intro paragraph."))
        #expect(updated.contains("Outro paragraph."))
    }

    @Test func settingTheHeaderCellEditsTheHeaderAndNotTheDelimiter() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.settingCell(.init(row: 0, column: 0), to: "Part", in: grid))
        let updated = applying(edit, to: Self.markdown)
        let reparsed = try parseGrid(updated)
        #expect(reparsed.cells(inRow: 0) == ["Part", "Qty", "Note"])
        #expect(reparsed.alignments == [.leading, .trailing, .center])
    }

    /// The reason a cell edit rewrites the whole *line* rather than the cell's own range: the cell's
    /// range is only knowable by splitting on unescaped pipes, and a typed `|` is exactly what
    /// invalidates that split mid-edit.
    @Test func aPipeTypedIntoACellSurvivesAReparseAsContentRatherThanAsAColumn() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.settingCell(.init(row: 1, column: 0), to: "Bolt | washer", in: grid))
        let updated = applying(edit, to: Self.markdown)
        let reparsed = try parseGrid(updated)
        #expect(reparsed.columnCount == 3)
        #expect(reparsed.cells(inRow: 1) == ["Bolt | washer", "4", "spare"])
    }

    /// A cell ending in a backslash is the case that decides whether the escaper writes `\\\\`.
    /// It must not: the splitter's unescape returns both characters of `\\X` for any `X` other than
    /// `|`, so a doubled backslash reads back as two. Left alone, the backslash escapes the space
    /// `rowSource` puts before the closing pipe and the column boundary survives anyway.
    @Test func aBackslashTypedIntoACellDoesNotEatTheNextColumn() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.settingCell(.init(row: 1, column: 0), to: "path\\", in: grid))
        let reparsed = try parseGrid(applying(edit, to: Self.markdown))
        #expect(reparsed.columnCount == 3)
        #expect(reparsed.cells(inRow: 1) == ["path\\", "4", "spare"])
        #expect(!edit.replacement.contains("\\\\"))
    }

    /// An empty row is a legitimate row, and Return is what makes that reachable. The shared
    /// `MarkdownTableParser` used to end a table at one, so a row added below the caret rendered as
    /// prose the instant it appeared.
    @Test func anEmptyRowStillContinuesTheTable() {
        let markdown = "| a | b |\n| - | - |\n|  |  |\n| 1 | 2 |"
        let grid = MarkdownTableEditor.grids(in: markdown).first
        #expect(grid?.rowCount == 3)
        #expect(grid?.cells(inRow: 1) == ["", ""])
        #expect(grid?.cells(inRow: 2) == ["1", "2"])
    }

    /// …and the two-pipe rule that keeps prose out is untouched by that relaxation.
    @Test func proseAfterATableIsStillNotSwallowedAsAnEmptyRow() {
        let markdown = "| a | b |\n| - | - |\n| 1 | 2 |\nShip it | maybe"
        #expect(MarkdownTableEditor.grids(in: markdown).first?.rowCount == 2)
    }

    @Test func anAlreadyEscapedPipeInTheSourceIsPreservedWhenAnotherCellIsEdited() throws {
        let source = """
        | a | b |
        | - | - |
        | x \\| y | z |
        """
        let grid = try parseGrid(source)
        #expect(grid.cells(inRow: 1) == ["x | y", "z"])
        let edit = try #require(MarkdownTableEditor.settingCell(.init(row: 1, column: 1), to: "w", in: grid))
        let reparsed = try parseGrid(applying(edit, to: source))
        #expect(reparsed.cells(inRow: 1) == ["x | y", "w"])
    }

    @Test func settingACellOutsideTheGridIsRefused() throws {
        let grid = try parseGrid()
        #expect(MarkdownTableEditor.settingCell(.init(row: 3, column: 0), to: "x", in: grid) == nil)
        #expect(MarkdownTableEditor.settingCell(.init(row: 0, column: 3), to: "x", in: grid) == nil)
        #expect(MarkdownTableEditor.settingCell(.init(row: -1, column: 0), to: "x", in: grid) == nil)
    }

    // MARK: - Rows

    /// Return on the header row has to skip the delimiter line, which is not a row and is not
    /// addressable. Anchoring on the row index alone would insert the new row *above* the
    /// alignment declaration and unmake the table.
    @Test func returnOnTheHeaderRowInsertsBelowTheDelimiterRatherThanAboveIt() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.insertingRow(below: 0, in: grid))
        let updated = applying(edit, to: Self.markdown)
        let lines = updated.components(separatedBy: "\n")
        #expect(lines[3] == "| :--- | ---: | :---: |")
        #expect(lines[4] == "|  |  |  |")
        let reparsed = try parseGrid(updated)
        #expect(reparsed.rowCount == 4)
        #expect(reparsed.alignments == [.leading, .trailing, .center])
        #expect(edit.focus == MarkdownTableCellAddress(row: 1, column: 0))
    }

    @Test func returnOnABodyRowInsertsDirectlyBelowIt() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.insertingRow(below: 1, in: grid))
        let lines = applying(edit, to: Self.markdown).components(separatedBy: "\n")
        #expect(lines[4] == "| Bolt | 4 | spare |")
        #expect(lines[5] == "|  |  |  |")
        #expect(lines[6] == "| Nut | 12 |  |")
    }

    @Test func deletingARowClosesTheGapRatherThanLeavingABlankLine() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.deletingRow(1, in: grid))
        let updated = applying(edit, to: Self.markdown)
        #expect(!updated.contains("Bolt"))
        #expect(!updated.contains("\n\n| Nut"))
        let reparsed = try parseGrid(updated)
        #expect(reparsed.rowCount == 2)
        #expect(reparsed.cells(inRow: 1) == ["Nut", "12", ""])
    }

    @Test func theHeaderRowCannotBeDeleted() throws {
        #expect(MarkdownTableEditor.deletingRow(0, in: try parseGrid()) == nil)
    }

    // MARK: - Columns

    @Test func insertingAColumnWidensEveryRowAndTheDelimiter() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.insertingColumn(at: 1, in: grid))
        let reparsed = try parseGrid(applying(edit, to: Self.markdown))
        #expect(reparsed.columnCount == 4)
        #expect(reparsed.cells(inRow: 0) == ["Item", "", "Qty", "Note"])
        #expect(reparsed.cells(inRow: 1) == ["Bolt", "", "4", "spare"])
        #expect(reparsed.alignments == [.leading, .leading, .trailing, .center])
    }

    @Test func insertingAColumnAtTheEndIsAllowed() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.insertingColumn(at: grid.columnCount, in: grid))
        let reparsed = try parseGrid(applying(edit, to: Self.markdown))
        #expect(reparsed.columnCount == 4)
        #expect(reparsed.cells(inRow: 1) == ["Bolt", "4", "spare", ""])
    }

    @Test func deletingAColumnTakesItsAlignmentWithIt() throws {
        let grid = try parseGrid()
        let edit = try #require(MarkdownTableEditor.deletingColumn(1, in: grid))
        let reparsed = try parseGrid(applying(edit, to: Self.markdown))
        #expect(reparsed.columnCount == 2)
        #expect(reparsed.cells(inRow: 0) == ["Item", "Note"])
        #expect(reparsed.cells(inRow: 1) == ["Bolt", "spare"])
        #expect(reparsed.alignments == [.leading, .center])
    }

    @Test func theLastColumnCannotBeDeleted() {
        let markdown = "| only |\n| --- |\n| one |"
        let grid = MarkdownTableEditor.grids(in: markdown).first
        #expect(grid?.columnCount == 1)
        #expect(MarkdownTableEditor.deletingColumn(0, in: grid!) == nil)
    }

    // MARK: - Focus

    @Test func tabMovesRightThenWrapsToTheNextRow() throws {
        let grid = try parseGrid()
        #expect(MarkdownTableEditor.focus(after: .init(row: 0, column: 0), movingForward: true, in: grid)
                == .cell(.init(row: 0, column: 1)))
        #expect(MarkdownTableEditor.focus(after: .init(row: 0, column: 2), movingForward: true, in: grid)
                == .cell(.init(row: 1, column: 0)))
    }

    @Test func tabOffTheLastCellAsksForANewRow() throws {
        let grid = try parseGrid()
        #expect(MarkdownTableEditor.focus(after: .init(row: 2, column: 2), movingForward: true, in: grid) == .appendRow)
    }

    @Test func shiftTabMovesLeftThenWrapsToThePreviousRowsLastColumn() throws {
        let grid = try parseGrid()
        #expect(MarkdownTableEditor.focus(after: .init(row: 1, column: 1), movingForward: false, in: grid)
                == .cell(.init(row: 1, column: 0)))
        #expect(MarkdownTableEditor.focus(after: .init(row: 1, column: 0), movingForward: false, in: grid)
                == .cell(.init(row: 0, column: 2)))
    }

    @Test func shiftTabOffTheFirstCellLeavesTheTable() throws {
        let grid = try parseGrid()
        #expect(MarkdownTableEditor.focus(after: .init(row: 0, column: 0), movingForward: false, in: grid) == .leaveTable)
    }

    // MARK: - Serializing

    @Test func delimiterSourceSpellsEachAlignment() {
        #expect(MarkdownTableEditor.delimiterSource(alignments: [.leading, .center, .trailing], columnCount: 3)
                == "| --- | :---: | ---: |")
    }

    @Test func aShortRowIsPaddedToTheTablesColumnCount() {
        #expect(MarkdownTableEditor.rowSource(cells: ["a"], columnCount: 3) == "| a |  |  |")
    }

    @Test func aLongRowIsTruncatedToTheTablesColumnCount() {
        #expect(MarkdownTableEditor.rowSource(cells: ["a", "b", "c", "d"], columnCount: 2) == "| a | b |")
    }

    @Test func aNewlineInACellBecomesASpaceRatherThanANewRow() {
        #expect(MarkdownTableEditor.escapedCell("one\ntwo") == "one two")
    }
}
