import Foundation
import Testing
@testable import Cadence

/// [[T-9271]]: the iOS task-embed card's chip row, built once for the note editor's drawn card and
/// Focus's read-only copy. Runs on the Mac leg because the builder is shared code; the two iOS
/// renderers only measure and paint what it returns.
struct CadenceTaskEmbedTouchChipsTests {

    private func task(
        statusRaw: String = TaskStatus.todo.rawValue,
        priorityRaw: String = TaskPriority.none.rawValue,
        containerName: String = "",
        isDone: Bool = false,
        isMissing: Bool = false
    ) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: UUID(),
            title: "Write the brief",
            statusRaw: statusRaw,
            priorityRaw: priorityRaw,
            sectionName: "",
            containerName: containerName,
            containerColorHex: "#4a9eff",
            dueDate: "",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 0,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: isDone,
            isCancelled: statusRaw == TaskStatus.cancelled.rawValue,
            isMissing: isMissing,
            subtasks: []
        )
    }

    private func titles(_ task: MarkdownTaskEmbedRenderInfo) -> [String] {
        CadenceTaskEmbedTouchChips.chips(for: task).map(\.title)
    }

    /// [[T-5015]] (b): an open task draws no status chip, and neither does a snapshot still
    /// carrying the retired "inprogress" — the row starts with the next chip that has something to say.
    @Test func anOpenOrRetiredInProgressTaskDrawsNoStatusChip() {
        #expect(titles(task(containerName: "Errands")) == ["Errands"])
        #expect(titles(task(statusRaw: TaskStatus.inProgress.rawValue, containerName: "Errands")) == ["Errands"])
        #expect(!titles(task()).contains(TaskStatus.todo.label))
    }

    /// The two statuses that do earn a chip keep it, in the Mac card's hues.
    @Test func doneAndCancelledKeepTheirChip() {
        let done = CadenceTaskEmbedTouchChips.chips(for: task(statusRaw: TaskStatus.done.rawValue, isDone: true))
        #expect(done == [CadenceTaskEmbedTouchChip(title: "Done", tint: Theme.green)])

        let cancelled = CadenceTaskEmbedTouchChips.chips(for: task(statusRaw: TaskStatus.cancelled.rawValue))
        #expect(cancelled == [CadenceTaskEmbedTouchChip(title: "Canceled", tint: Theme.dim)])
    }

    /// Low is blue on every other surface; green is what Done is on this same card.
    @Test func priorityChipTakesTheAppWidePriorityHue() {
        for priority in TaskPriority.allCases where priority != .none {
            let chips = CadenceTaskEmbedTouchChips.chips(for: task(priorityRaw: priority.rawValue))
            #expect(chips == [CadenceTaskEmbedTouchChip(title: priority.label, tint: Theme.priorityColor(priority))])
        }
        let low = CadenceTaskEmbedTouchChips.chips(for: task(priorityRaw: TaskPriority.low.rawValue))
        #expect(low.first?.tint != Theme.green)
    }

    /// A reference whose task is gone says "Missing" and nothing else.
    @Test func aMissingReferenceSaysMissingAlone() {
        let chips = CadenceTaskEmbedTouchChips.chips(for: task(statusRaw: TaskStatus.cancelled.rawValue, isMissing: true))
        #expect(chips == [CadenceTaskEmbedTouchChip(title: "Missing", tint: Theme.red)])
    }
}
