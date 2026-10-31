import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// [[T-9273]]: the task-embed card's subtask row, shared by the Mac card and the iOS note
/// editor's. Runs on the Mac leg because the geometry is shared code; the iOS card only paints
/// what it returns, so the last test reads that file to pin that it does.
struct CadenceTaskEmbedSubtaskRowTests {

    private let ids = (0..<3).map { _ in UUID() }

    private func subtasks() -> [MarkdownTaskEmbedSubtaskRenderInfo] {
        [
            MarkdownTaskEmbedSubtaskRenderInfo(id: ids[0], title: "Buy milk", isDone: false, order: 0),
            MarkdownTaskEmbedSubtaskRenderInfo(id: ids[1], title: "Call Sam", isDone: true, order: 1),
            MarkdownTaskEmbedSubtaskRenderInfo(id: ids[2], title: "   ", isDone: false, order: 2),
        ]
    }

    /// A fixed 6pt per character, so widths are known without a font.
    private func layout(maxX: CGFloat = 600) -> CadenceTaskEmbedSubtaskRowLayout {
        CadenceTaskEmbedSubtaskRow.layout(
            subtasks(),
            fallbackTitle: "Untitled",
            minX: 82,
            maxX: maxX,
            rowY: 66,
            rowHeight: 16
        ) { title, _ in CGFloat(title.count * 6) }
    }

    @Test func theLabelIsTheTitleAloneWithNoMarkdownCheckboxSpelledIntoIt() {
        let items = layout().items
        #expect(items.map(\.label) == ["Buy milk", "Call Sam", "Untitled"])
        #expect(items.map(\.isDone) == [false, true, false])
        for item in items {
            #expect(!item.label.contains("["), "a subtask label spells its checkbox: \(item.label)")
            #expect(!item.label.contains("]"), "a subtask label spells its checkbox: \(item.label)")
        }
    }

    @Test func eachItemIsAGlyphThenItsTitleAndTheGlyphSitsInsideTheItem() {
        for item in layout().items {
            #expect(item.checkbox.width == CadenceTaskEmbedSubtaskRow.checkboxSide)
            #expect(item.checkbox.height == CadenceTaskEmbedSubtaskRow.checkboxSide)
            #expect(item.full.contains(item.checkbox))
            #expect(item.checkbox.midY == item.full.midY)
            #expect(item.checkbox.maxX < item.text.minX, "the title starts before the glyph ends")
            #expect(item.text.maxX <= item.full.maxX)
        }
    }

    /// The Mac's widths, which the shared rule was lifted from: title + 28, clamped to 58...150,
    /// 6pt between items, and an item that would cross `maxX` is not placed at all.
    @Test func itemWidthsFollowTheTitleWithinTheClampAndTheRowStopsAtTheEdge() {
        let items = layout().items
        // "Buy milk" 48 + 28 = 76; "Call Sam" 76; "Untitled" 76.
        #expect(items.map(\.full.width) == [76, 76, 76])
        #expect(items[1].full.minX == items[0].full.maxX + CadenceTaskEmbedSubtaskRow.itemSpacing)

        let long = CadenceTaskEmbedSubtaskRow.layout(
            [MarkdownTaskEmbedSubtaskRenderInfo(id: UUID(), title: String(repeating: "x", count: 80), isDone: false, order: 0),
             MarkdownTaskEmbedSubtaskRenderInfo(id: UUID(), title: "a", isDone: false, order: 1)],
            fallbackTitle: "Untitled", minX: 0, maxX: 1000, rowY: 0, rowHeight: 18
        ) { title, _ in CGFloat(title.count * 6) }
        #expect(long.items.map(\.full.width) == [CadenceTaskEmbedSubtaskRow.maximumItemWidth, CadenceTaskEmbedSubtaskRow.minimumItemWidth])

        // Room for two whole items (82 + 76 + 6 + 76 = 240), not the third.
        let narrow = layout(maxX: 300)
        #expect(narrow.items.count == 2)
        #expect(narrow.trailingX == narrow.items[1].full.maxX + CadenceTaskEmbedSubtaskRow.itemSpacing)
    }

    /// The tap target is the glyph grown by the slop, not the first stretch of the title.
    @Test func theCheckboxHitIsTheGlyphPlusSlopAndNeverTheTitle() throws {
        let items = layout().items
        let first = try #require(items.first)
        let slopX: CGFloat = 8
        let slopY: CGFloat = 11

        let centre = CGPoint(x: first.checkbox.midX, y: first.checkbox.midY)
        #expect(CadenceTaskEmbedSubtaskRow.checkboxHit(at: centre, in: items, slopX: slopX, slopY: slopY) == ids[0])

        let justInside = CGPoint(x: first.checkbox.maxX + slopX - 0.5, y: first.checkbox.maxY + slopY - 0.5)
        #expect(CadenceTaskEmbedSubtaskRow.checkboxHit(at: justInside, in: items, slopX: slopX, slopY: slopY) == ids[0])

        let titleMiddle = CGPoint(x: first.text.midX, y: first.text.midY)
        #expect(first.checkbox.maxX + slopX < titleMiddle.x, "non-vacuity: the probe is on the title")
        #expect(CadenceTaskEmbedSubtaskRow.checkboxHit(at: titleMiddle, in: items, slopX: slopX, slopY: slopY) == nil)

        let second = items[1]
        #expect(CadenceTaskEmbedSubtaskRow.checkboxHit(
            at: CGPoint(x: second.checkbox.midX, y: second.checkbox.midY), in: items, slopX: slopX, slopY: slopY
        ) == ids[1])
    }

    @Test func theTickStaysInsideItsGlyph() {
        let rect = CGRect(x: 85, y: 69, width: 10, height: 10)
        let points = CadenceTaskEmbedSubtaskRow.checkPoints(in: rect)
        #expect(points.count == 3)
        for point in points {
            #expect(rect.contains(point))
        }
        // y-down: the middle vertex is the lowest point of the tick.
        #expect(points[1].y > points[0].y)
        #expect(points[1].y > points[2].y)
    }

    /// [[T-9322]]: the overflow count is every subtask the row did not draw, and the chip has
    /// room — a placed item gives its slot up rather than the count going undrawn.
    @Test func theOverflowCountsEverySubtaskNotDrawnAndReservesRoomForItsChip() throws {
        func run(maxX: CGFloat, total: Int) -> (row: CadenceTaskEmbedSubtaskRowLayout, overflow: (count: Int, full: CGRect)?) {
            CadenceTaskEmbedSubtaskRow.layoutWithOverflow(
                subtasks(),
                totalCount: total,
                fallbackTitle: "Untitled",
                minX: 0,
                maxX: maxX,
                rowY: 66,
                rowHeight: 16,
                overflowWidth: { _ in 40 }
            ) { title, _ in CGFloat(title.count * 6) }
        }

        // Every item 76 wide, 6 apart: all three end at 240, so a 300 row has nothing left over.
        let roomy = run(maxX: 300, total: 3)
        #expect(roomy.row.items.count == 3)
        #expect(roomy.overflow == nil)

        // Two fit (0...76, 82...158) and the chip after them (164 + 40 = 204) does too: +1.
        let twoFit = try #require(run(maxX: 210, total: 3).overflow)
        #expect(twoFit.count == 1)
        #expect(twoFit.full.minX == 164)

        // Two fit at 160 but the chip does not: the second gives way and the chip reads +2.
        let squeezed = run(maxX: 160, total: 3)
        let chip = try #require(squeezed.overflow)
        #expect(squeezed.row.items.count == 1)
        #expect(chip.count == 2)
        #expect(chip.full.minX == squeezed.row.items[0].full.maxX + CadenceTaskEmbedSubtaskRow.itemSpacing)
        #expect(chip.full.maxX <= 160)

        // Subtasks past those offered are counted alongside those the row dropped.
        let more = run(maxX: 160, total: 7)
        #expect(more.row.items.count + (more.overflow?.count ?? 0) == 7)

        // Not even the chip fits: nothing is drawn, rather than a chip crossing the edge.
        let tiny = run(maxX: 30, total: 3)
        #expect(tiny.row.items.isEmpty)
        #expect(tiny.overflow == nil)
    }

    /// The iOS card paints the shared row and no longer spells `[ ] ` / `[x] ` into its image.
    @Test func theIOSCardDrawsTheSharedRowAndNoBracketedCheckbox() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownTaskEmbedLayoutInfo.swift")
        )
        #expect(source.contains("CadenceTaskEmbedSubtaskRow.layout("))
        #expect(source.contains("CadenceTaskEmbedSubtaskRow.checkboxHit("))
        #expect(!source.contains("\"[x] \""))
        #expect(!source.contains("\"[ ] \""))
    }
}
