import Foundation
import Testing
@testable import Cadence

// [[T-9331]]: the iOS note editor's task-embed card counted every subtask its row did not draw
// (since [[T-9273]]) but drew the `+N` only when 34pt were left after the placed items, so a full
// row silently hid that subtasks were missing. It now lays out through the shared
// `CadenceTaskEmbedSubtaskRow.layoutWithOverflow`, as the Mac card does since [[T-9322]]. Gated
// `#if os(iOS)`: the card and its UIKit measuring do not exist on the macOS leg.
#if os(iOS)
import UIKit

struct iOSMarkdownTaskEmbedSubtaskOverflowTests {

    private func task(subtaskTitles: [String]) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: UUID(),
            title: "Quarter close",
            statusRaw: TaskStatus.todo.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            sectionName: "",
            containerName: "",
            containerColorHex: Theme.blueHex,
            dueDate: "",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 0,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: false,
            isCancelled: false,
            isMissing: false,
            subtasks: subtaskTitles.enumerated().map {
                MarkdownTaskEmbedSubtaskRenderInfo(id: UUID(), title: $1, isDone: false, order: $0)
            }
        )
    }

    /// The row without the chip's room reserved — the layout the card drew from before the fix —
    /// measured in the card's own 10pt font.
    private func unreservedRow(_ task: MarkdownTaskEmbedRenderInfo, width: CGFloat) -> CadenceTaskEmbedSubtaskRowLayout {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .medium)]
        return CadenceTaskEmbedSubtaskRow.layout(
            task.visibleSubtasks,
            fallbackTitle: TaskTitleSupport.defaultCompactDisplayTitle,
            minX: iOSMarkdownTaskEmbedLayoutInfo.subtaskRowMinX,
            maxX: width - 12,
            rowY: iOSMarkdownTaskEmbedLayoutInfo.subtaskRowY,
            rowHeight: iOSMarkdownTaskEmbedLayoutInfo.subtaskRowHeight
        ) { title, _ in ceil(NSString(string: title).size(withAttributes: attributes).width) }
    }

    /// At every card width, each subtask is either drawn on the row or counted by a chip that sits
    /// inside the card — and on some width the chip only fits because a placed item gave way.
    @Test func everySubtaskIsDrawnOrCountedByAChipThatFitsAtEveryCardWidth() throws {
        let fixtures = [
            task(subtaskTitles: ["Reconcile invoices", "Chase the receipts", "File the VAT return"]),
            task(subtaskTitles: ["Reconcile invoices", "Chase the receipts", "File the VAT return", "Tea", "Jam"]),
        ]
        var reservationsTaken = 0
        var chipsDrawn = 0
        for fixture in fixtures {
            let card = iOSMarkdownTaskEmbedLayoutInfo(task: fixture)
            var width: CGFloat = 260
            while width <= MarkdownTaskEmbedRenderInfo.maxCardWidth {
                let layout = card.subtaskRow(width: width)
                let placed = layout.row.items.count
                if placed < fixture.subtaskTotalCount {
                    let chip = try #require(layout.overflow, "width \(width): \(fixture.subtaskTotalCount - placed) subtasks missing and no +N")
                    chipsDrawn += 1
                    #expect(chip.count == fixture.subtaskTotalCount - placed, "width \(width)")
                    #expect(chip.full.width == iOSMarkdownTaskEmbedLayoutInfo.subtaskOverflowWidth, "width \(width)")
                    #expect(chip.full.maxX <= width - 12, "width \(width): the chip crosses the card's edge")
                    if let last = layout.row.items.last {
                        #expect(chip.full.minX > last.full.maxX, "width \(width): the chip overlaps the last item")
                    }
                } else {
                    #expect(layout.overflow == nil, "width \(width)")
                }
                if unreservedRow(fixture, width: width).items.count > placed { reservationsTaken += 1 }
                width += 1
            }
        }
        #expect(chipsDrawn > 0, "non-vacuity: no width left a subtask off the row")
        #expect(reservationsTaken > 0, "non-vacuity: no width needed an item to give way to the chip")
    }

    /// A subtask that gave its room to the chip is not drawn, so a finger cannot tick it either:
    /// hit-testing reads the same layout the drawing does.
    @Test func aSubtaskThatGaveWayToTheChipIsNotTappable() throws {
        let fixture = task(subtaskTitles: ["Reconcile invoices", "Chase the receipts", "File the VAT return"])
        let card = iOSMarkdownTaskEmbedLayoutInfo(task: fixture)
        var width: CGFloat = 260
        var checked = 0
        while width <= MarkdownTaskEmbedRenderInfo.maxCardWidth {
            let unreserved = unreservedRow(fixture, width: width)
            let layout = card.subtaskRow(width: width)
            if unreserved.items.count > layout.row.items.count {
                let maxWidth = width + 22  // `renderedWidth` is `maxWidth - 22` in this range
                guard card.cardWidth(maxWidth: maxWidth) == width else { width += 1; continue }
                let dropped = try #require(unreserved.items.last)
                if case .subtaskCheckbox(let id) = card.hitTarget(
                    at: CGPoint(x: dropped.checkbox.midX, y: dropped.checkbox.midY),
                    maxWidth: maxWidth
                ) {
                    #expect(id != dropped.subtaskID, "width \(width): an undrawn subtask is still tappable")
                }
                for item in layout.row.items {
                    guard case .subtaskCheckbox(let id) = card.hitTarget(
                        at: CGPoint(x: item.checkbox.midX, y: item.checkbox.midY),
                        maxWidth: maxWidth
                    ) else {
                        Issue.record("width \(width): a drawn subtask's glyph is not tappable")
                        continue
                    }
                    #expect(id == item.subtaskID)
                }
                checked += 1
            }
            width += 1
        }
        #expect(checked > 0, "non-vacuity: no width dropped an item for the chip")
    }
}
#endif
