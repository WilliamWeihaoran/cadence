import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// **T-221's boundary tests.** A rendered block that becomes editable has to cross the text view's
/// edge, and four things are usually broken by the crossing: selection through the block,
/// copy/paste of a range spanning it, undo of an edit made inside it, and the invalidation that
/// makes it re-render. These render the real `CadenceTextView` and measure each one.
///
/// The design they pin is that **the markdown source never leaves the text storage** — only its
/// glyphs are collapsed and a grid is drawn over the space they were given. That is why three of
/// the four need no new mechanism at all.
@MainActor
struct MarkdownTableHostedEditingTests {
    private static let markdown = """
    Prose above.

    | Item | Qty | Note |
    | :--- | ---: | :---: |
    | Bolt | 4 | spare |
    | Nut | 12 | loose |

    Prose below.
    """

    @MainActor
    private final class UndoDelegate: NSObject, NSTextViewDelegate {
        let manager = UndoManager()
        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    private final class ChangeCounter: @unchecked Sendable {
        var count = 0
    }

    private func makeTextView(_ override: String? = nil) -> CadenceTextView {
        let markdown = override ?? Self.markdown
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let containerWidth: CGFloat = 560 - 36
        let container = NSTextContainer(
            containerSize: NSSize(width: containerWidth, height: .greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: 560, height: 900),
            textContainer: container
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isEditable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.backgroundColor = Theme.nsBg
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.string = markdown
        MarkdownStylist.apply(to: textView)
        return textView
    }

    @discardableResult
    private func render(_ textView: CadenceTextView) -> NSBitmapImageRep {
        let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds)!
        textView.cacheDisplay(in: textView.bounds, to: rep)
        return rep
    }

    private func parseGrid(in textView: CadenceTextView) throws -> MarkdownTableGrid {
        try #require(MarkdownTableEditor.grids(in: textView.string).first)
    }

    private func renderedGridAttribute(in textView: CadenceTextView) -> MarkdownTableGrid? {
        guard let storage = textView.textStorage else { return nil }
        var found: MarkdownTableGrid?
        storage.enumerateAttribute(.cadenceMarkdownTable, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let value = value as? MarkdownTableGrid { found = value }
        }
        return found
    }

    // MARK: - The table renders as a grid at all

    @Test func aTableIsOneCanvasAttributeRatherThanFiveBandedRows() throws {
        let textView = makeTextView()
        let storage = try #require(textView.textStorage)
        let grid = try parseGrid(in: textView)

        let canvas = try #require(renderedGridAttribute(in: textView))
        #expect(canvas.storageRange == grid.storageRange)
        #expect(canvas.rowCount == 3)

        var bandedRows = 0
        var hiddenLength = 0
        storage.enumerateAttribute(.cadenceMarkdownTableRow, in: grid.storageRange) { value, range, _ in
            if value is MarkdownTableRowStyle { bandedRows += range.length }
        }
        storage.enumerateAttribute(.cadenceMarkdownHidden, in: grid.storageRange) { value, range, _ in
            if (value as? Bool) == true { hiddenLength += range.length }
        }
        #expect(bandedRows == 0)
        #expect(hiddenLength == grid.storageRange.length)
    }

    /// The styler reserves the height and the draw pass fills it. Measured on the real layout
    /// manager rather than on the two formulas, because the thing that can go wrong is that the
    /// paragraph style is applied to the wrong line.
    @Test func theTablesFirstLineFragmentIsTallEnoughForTheWholeGrid() throws {
        let textView = makeTextView()
        render(textView)
        let hit = try #require(textView.markdownTableHits.first)
        let layoutManager = try #require(textView.layoutManager)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: hit.anchor)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        #expect(fragment.height >= hit.gridRect.height)
        #expect(hit.gridRect.height > 0)
    }

    @Test func drawingTheViewPopulatesTheTableHitCacheAndACellCanBeClicked() throws {
        let textView = makeTextView()
        render(textView)
        let hit = try #require(textView.markdownTableHits.first)
        let cell = try #require(hit.layout.cellRect(row: 1, column: 1, in: hit.gridRect))
        let clicked = try #require(textView.markdownTableCellHit(at: NSPoint(x: cell.midX, y: cell.midY)))
        #expect(clicked.anchor == hit.anchor)
        #expect(clicked.address == MarkdownTableCellAddress(row: 1, column: 1))
    }

    // MARK: - Boundary 1: selection

    /// A drag from the prose above to the prose below still selects the table's own characters,
    /// because the table's own characters are still there.
    @Test func aSelectionSpanningTheTableStillCoversItsSource() throws {
        let textView = makeTextView()
        let ns = textView.string as NSString
        let start = ns.range(of: "Prose above.").location
        let end = NSMaxRange(ns.range(of: "Prose below."))
        let span = NSRange(location: start, length: end - start)
        textView.setSelectedRange(span)
        #expect(textView.selectedRange() == span)

        let selected = ns.substring(with: textView.selectedRange())
        #expect(selected.contains("| Bolt | 4 | spare |"))
        #expect(selected.contains("| :--- | ---: | :---: |"))
    }

    /// A caret arrowed at the table steps over it instead of disappearing inside hidden text.
    @Test func theCaretStepsOverARenderedTableRatherThanIntoIt() throws {
        let textView = makeTextView()
        let storage = try #require(textView.textStorage)
        let grid = try parseGrid(in: textView)

        let forward = MarkdownHiddenRangeSupport.nextVisibleCaretLocation(
            from: grid.storageRange.location - 1,
            movingForward: true,
            in: storage
        )
        #expect(forward >= NSMaxRange(grid.storageRange))

        let backward = MarkdownHiddenRangeSupport.nextVisibleCaretLocation(
            from: NSMaxRange(grid.storageRange),
            movingForward: false,
            in: storage
        )
        #expect(backward <= grid.storageRange.location)
    }

    // MARK: - Boundary 2: copy/paste

    /// Copying a range that spans the table yields the markdown, pipes and all. Written to a
    /// private pasteboard so the test cannot clobber the machine's clipboard.
    @Test func copyingAcrossTheTableYieldsItsMarkdown() throws {
        let textView = makeTextView()
        let ns = textView.string as NSString
        let start = ns.range(of: "Prose above.").location
        let end = NSMaxRange(ns.range(of: "Prose below."))
        textView.setSelectedRange(NSRange(location: start, length: end - start))

        // Exactly what `NSTextView.copy(_:)` does: declare the view's own writable types on the
        // pasteboard, then hand the same list to `writeSelection`. Both halves matter — the plural
        // writer refuses a type the pasteboard has not declared, and the singular
        // `writeSelection(to:type:)` returns false on its own.
        // Measured, not assumed: on macOS 26 an `NSTextView` still advertises the *legacy* type
        // names — `NSStringPboardType` and `NeXT Rich Text Format v1.0 pasteboard type` — so asking
        // it to write `NSPasteboard.PasteboardType.string` ("public.utf8-plain-text") returns false
        // without writing anything. Take the list from the view.
        let types = textView.writablePasteboardTypes
        let plainText = try #require(types.first { $0 == .string || $0.rawValue == "NSStringPboardType" })
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.haoranwei.Cadence.T221Tests"))
        pasteboard.clearContents()
        pasteboard.declareTypes(types, owner: nil)
        #expect(textView.writeSelection(to: pasteboard, types: types))

        let copied = try #require(pasteboard.string(forType: plainText) ?? pasteboard.string(forType: .string))
        #expect(copied.contains("| Item | Qty | Note |"))
        #expect(copied.contains("| :--- | ---: | :---: |"))
        #expect(copied.contains("| Nut | 12 | loose |"))
        #expect(copied.hasPrefix("Prose above."))
    }

    /// And the round trip: markdown pasted back in renders as a table again, because nothing in the
    /// rendered form is stored anywhere but in the source.
    @Test func markdownCopiedOutOfATableRendersAsATableWhenItGoesBackIn() throws {
        let source = makeTextView()
        let copied = (source.string as NSString).substring(with: try parseGrid(in: source).storageRange)

        let destination = makeTextView("Nothing here yet.\n\n" + copied + "\n")
        let canvas = try #require(renderedGridAttribute(in: destination))
        #expect(canvas.cells(inRow: 1) == ["Bolt", "4", "spare"])
    }

    // MARK: - Boundary 3: undo

    /// The whole reason the hosted editor writes through `shouldChangeText` / `replaceCharacters` /
    /// `didChangeText`: a committed cell is an ordinary text-view edit, so `Cmd+Z` reaches it
    /// through the route the editor already has and puts the note back exactly as it was.
    @Test func undoRestoresTheNoteExactlyAfterACellIsCommitted() throws {
        let textView = makeTextView()
        let delegate = UndoDelegate()
        textView.delegate = delegate
        delegate.manager.groupsByEvent = false
        let before = textView.string
        let grid = try parseGrid(in: textView)

        delegate.manager.beginUndoGrouping()
        #expect(textView.applyTableCellText("Screw", at: .init(row: 1, column: 0), anchor: grid.storageRange.location))
        delegate.manager.endUndoGrouping()

        #expect(textView.string.contains("| Screw | 4 | spare |"))
        #expect(textView.string != before)
        #expect(delegate.manager.canUndo)

        delegate.manager.undo()
        #expect(textView.string == before)
    }

    @Test func undoRestoresTheNoteExactlyAfterAColumnIsDeleted() throws {
        let textView = makeTextView()
        let delegate = UndoDelegate()
        textView.delegate = delegate
        delegate.manager.groupsByEvent = false
        let before = textView.string
        let grid = try parseGrid(in: textView)
        let edit = try #require(MarkdownTableEditor.deletingColumn(1, in: grid))

        delegate.manager.beginUndoGrouping()
        #expect(textView.applyMarkdownTableEdit(edit))
        delegate.manager.endUndoGrouping()

        #expect(!textView.string.contains("| Bolt | 4 | spare |"))
        delegate.manager.undo()
        #expect(textView.string == before)
    }

    /// Tabbing through cells without typing must not stack up undo steps that undo nothing
    /// visible — five Tabs would otherwise cost five `Cmd+Z` presses to get back past.
    @Test func committingACellWithItsOwnValueRegistersNoEdit() throws {
        let textView = makeTextView()
        let delegate = UndoDelegate()
        textView.delegate = delegate
        let before = textView.string
        let grid = try parseGrid(in: textView)

        #expect(textView.applyTableCellText("Bolt", at: .init(row: 1, column: 0), anchor: grid.storageRange.location) == false)
        #expect(textView.string == before)
        #expect(delegate.manager.canUndo == false)
    }

    // MARK: - Boundary 4: invalidation

    /// The macOS render gate is the ordinary `textDidChange` restyle — `MarkdownStyleSignature` is
    /// iOS-only and has no reader on this platform — so a committed cell must post the notification
    /// the coordinator restyles from. Without it the grid silently keeps its old value.
    @Test func committingACellPostsTheNotificationTheEditorRestylesFrom() throws {
        let textView = makeTextView()
        let counter = ChangeCounter()
        let token = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { _ in counter.count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        let grid = try parseGrid(in: textView)
        #expect(textView.applyTableCellText("Screw", at: .init(row: 1, column: 0), anchor: grid.storageRange.location))
        #expect(counter.count == 1)
    }

    @Test func restylingAfterACommitRendersTheNewCellValue() throws {
        let textView = makeTextView()
        let grid = try parseGrid(in: textView)
        #expect(textView.applyTableCellText("Screw", at: .init(row: 1, column: 0), anchor: grid.storageRange.location))
        MarkdownStylist.apply(to: textView)

        let canvas = try #require(renderedGridAttribute(in: textView))
        #expect(canvas.cells(inRow: 1) == ["Screw", "4", "spare"])
        render(textView)
        #expect(textView.markdownTableHits.count == 1)
        #expect(textView.markdownTableHits.first?.grid.cells(inRow: 1) == ["Screw", "4", "spare"])
    }

    /// An edit inside the table leaves it anchored where it was, which is what lets a cell editor
    /// reopen on the next cell after committing this one.
    @Test func aTablesAnchorSurvivesEveryKindOfEditMadeInsideIt() throws {
        let textView = makeTextView()
        let anchor = try parseGrid(in: textView).storageRange.location

        #expect(textView.applyTableCellText("Screw", at: .init(row: 1, column: 0), anchor: anchor))
        #expect(MarkdownTableEditor.grids(in: textView.string).first?.storageRange.location == anchor)

        var grid = try self.parseGrid(in: textView)
        #expect(textView.applyMarkdownTableEdit(try #require(MarkdownTableEditor.insertingRow(below: 1, in: grid))))
        #expect(MarkdownTableEditor.grids(in: textView.string).first?.storageRange.location == anchor)

        grid = try self.parseGrid(in: textView)
        #expect(textView.applyMarkdownTableEdit(try #require(MarkdownTableEditor.insertingColumn(at: 1, in: grid))))
        #expect(MarkdownTableEditor.grids(in: textView.string).first?.storageRange.location == anchor)
    }

    // MARK: - The raw-source escape

    /// Showing the source is a command, not a caret position: the table only un-renders when
    /// `revealedTableAnchor` names it, and then it falls back to the banded per-row styling the
    /// editor has always drawn.
    @Test func revealingATableGivesBackItsBandedSourceRows() throws {
        let textView = makeTextView()
        let grid = try parseGrid(in: textView)
        textView.revealedTableAnchor = grid.storageRange.location
        MarkdownStylist.apply(to: textView)
        let storage = try #require(textView.textStorage)

        #expect(renderedGridAttribute(in: textView) == nil)

        var bandedRows = 0
        var hiddenLength = 0
        storage.enumerateAttribute(.cadenceMarkdownTableRow, in: grid.storageRange) { value, range, _ in
            if value is MarkdownTableRowStyle { bandedRows += range.length }
        }
        storage.enumerateAttribute(.cadenceMarkdownHidden, in: grid.storageRange) { value, range, _ in
            if (value as? Bool) == true { hiddenLength += range.length }
        }
        // Per *line*, so the newlines between them are not covered — three lines, two separators.
        let separators = grid.block.lineIndexes.count - 1
        #expect(bandedRows == grid.storageRange.length - separators)
        #expect(hiddenLength == 0)

        render(textView)
        #expect(textView.markdownTableHits.isEmpty)
    }

    @Test func revealingOneTableLeavesTheOtherRendered() throws {
        let textView = makeTextView("""
        | a | b |
        | - | - |
        | 1 | 2 |

        between

        | c | d |
        | - | - |
        | 3 | 4 |
        """)
        let grids = MarkdownTableEditor.grids(in: textView.string)
        #expect(grids.count == 2)
        textView.revealedTableAnchor = grids[0].storageRange.location
        MarkdownStylist.apply(to: textView)

        let canvas = try #require(renderedGridAttribute(in: textView))
        #expect(canvas.storageRange == grids[1].storageRange)
    }
}
#endif
