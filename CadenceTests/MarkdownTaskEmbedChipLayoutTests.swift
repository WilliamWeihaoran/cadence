import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// The embed card lays chips out left to right and drops whatever does not fit, so these cover the
/// budgeting rules rather than pixel positions: a due date must survive every crowded combination,
/// and whatever the layout drops must disappear from hit testing too.
@MainActor
struct MarkdownTaskEmbedChipLayoutTests {
    private func renderInfo(
        title: String = "Draft the quarterly planning summary",
        statusRaw: String = TaskStatus.todo.rawValue,
        priorityRaw: String = TaskPriority.none.rawValue,
        sectionName: String = "",
        containerName: String = "Quarterly Planning Initiative",
        dueDate: String = "",
        scheduledDate: String = "",
        estimatedMinutes: Int = 90,
        recurrenceRaw: String = TaskRecurrenceRule.none.rawValue
    ) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: UUID(),
            title: title,
            statusRaw: statusRaw,
            priorityRaw: priorityRaw,
            sectionName: sectionName,
            containerName: containerName,
            containerColorHex: "#4a9eff",
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            scheduledStartMin: -1,
            estimatedMinutes: estimatedMinutes,
            actualMinutes: 0,
            recurrenceRaw: recurrenceRaw,
            isDone: false,
            isCancelled: false,
            isMissing: false,
            subtasks: []
        )
    }

    private func fields(for task: MarkdownTaskEmbedRenderInfo, textContainerWidth: CGFloat) -> [MarkdownTaskEmbedField] {
        let cardRect = MarkdownTaskEmbedDrawing.cardRect(
            forLineRect: NSRect(x: 0, y: 0, width: textContainerWidth, height: task.cardHeight + 12),
            textContainerWidth: textContainerWidth,
            task: task
        )
        return MarkdownTaskEmbedDrawing.chipRects(task: task, cardRect: cardRect).map(\.field)
    }

    @Test func crowdedTaskStillRendersDueChip() {
        let task = renderInfo(
            statusRaw: TaskStatus.inProgress.rawValue,
            priorityRaw: TaskPriority.high.rawValue,
            sectionName: "Backlog Grooming",
            dueDate: "2030-04-18",
            scheduledDate: "2030-04-16"
        )

        #expect(fields(for: task, textContainerWidth: 560).contains(.dueDate))
    }

    @Test func dueChipSurvivesEveryCrowdingCombination() {
        let statuses = [TaskStatus.todo.rawValue, TaskStatus.inProgress.rawValue]
        let priorities = [TaskPriority.none.rawValue, TaskPriority.high.rawValue]
        let sections = ["", "Backlog Grooming"]
        let recurrences = [TaskRecurrenceRule.none.rawValue, TaskRecurrenceRule.weekly.rawValue]
        let widths: [CGFloat] = [220, 360, 560, 900]

        for status in statuses {
            for priority in priorities {
                for section in sections {
                    for recurrence in recurrences {
                        for width in widths {
                            let task = renderInfo(
                                statusRaw: status,
                                priorityRaw: priority,
                                sectionName: section,
                                dueDate: "2030-04-18",
                                scheduledDate: "2030-04-16",
                                recurrenceRaw: recurrence
                            )
                            #expect(
                                fields(for: task, textContainerWidth: width).contains(.dueDate),
                                "due chip dropped for status=\(status) priority=\(priority) section=\(section) recurrence=\(recurrence) width=\(width)"
                            )
                        }
                    }
                }
            }
        }
    }

    @Test func renderedDueChipIsHitTestable() throws {
        let task = renderInfo(
            statusRaw: TaskStatus.inProgress.rawValue,
            priorityRaw: TaskPriority.high.rawValue,
            sectionName: "Backlog Grooming",
            dueDate: "2030-04-18",
            scheduledDate: "2030-04-16"
        )
        let cardRect = MarkdownTaskEmbedDrawing.cardRect(
            forLineRect: NSRect(x: 0, y: 0, width: 560, height: task.cardHeight + 12),
            textContainerWidth: 560,
            task: task
        )
        let dueRect = try #require(
            MarkdownTaskEmbedDrawing.chipRects(task: task, cardRect: cardRect)
                .first(where: { $0.field == .dueDate })?
                .rect
        )

        let center = NSPoint(x: dueRect.midX, y: dueRect.midY)
        #expect(MarkdownTaskEmbedDrawing.fieldHit(at: center, task: task, cardRect: cardRect) == .dueDate)
    }

    @Test func droppedChipsAreNeitherDrawnNorHitTestable() {
        let task = renderInfo(
            statusRaw: TaskStatus.inProgress.rawValue,
            priorityRaw: TaskPriority.high.rawValue,
            sectionName: "Backlog Grooming",
            dueDate: "2030-04-18",
            scheduledDate: "2030-04-16"
        )
        let cardRect = MarkdownTaskEmbedDrawing.cardRect(
            forLineRect: NSRect(x: 0, y: 0, width: 240, height: task.cardHeight + 12),
            textContainerWidth: 240,
            task: task
        )
        let rendered = MarkdownTaskEmbedDrawing.chipRects(task: task, cardRect: cardRect)
        #expect(rendered.contains(where: { $0.field == .dueDate }))

        // Sweep the chip row: every point that hit-tests to a field has to belong to a chip the
        // card actually drew, so nothing is clickable-but-invisible.
        let renderedFields = Set(rendered.map(\.field))
        let row = rendered.first?.rect ?? .zero
        for step in stride(from: cardRect.minX, through: cardRect.maxX, by: 2) {
            let hit = MarkdownTaskEmbedDrawing.fieldHit(
                at: NSPoint(x: step, y: row.midY),
                task: task,
                cardRect: cardRect
            )
            guard let hit, hit != .title else { continue }
            #expect(renderedFields.contains(hit), "field \(hit) is hittable but was not drawn")
        }
    }

    @Test func narrowCardDropsOtherChipsBeforeTheDueDate() {
        let task = renderInfo(
            statusRaw: TaskStatus.inProgress.rawValue,
            priorityRaw: TaskPriority.high.rawValue,
            sectionName: "Backlog Grooming",
            dueDate: "2030-04-18",
            scheduledDate: ""
        )
        let roomy = fields(for: task, textContainerWidth: 900)
        let narrow = fields(for: task, textContainerWidth: 260)

        // The narrow card really does have to give something up…
        #expect(narrow.count < roomy.count)
        // …and the deadline is never what it gives up.
        #expect(narrow.contains(.dueDate))
    }
}
#endif
