import Foundation
import SwiftUI
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
        isMissing: Bool = false,
        dueDate: String = "",
        scheduledDate: String = "",
        estimatedMinutes: Int = 0,
        actualMinutes: Int = 0
    ) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: UUID(),
            title: "Write the brief",
            statusRaw: statusRaw,
            priorityRaw: priorityRaw,
            sectionName: "",
            containerName: containerName,
            containerColorHex: "#4a9eff",
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            scheduledStartMin: -1,
            estimatedMinutes: estimatedMinutes,
            actualMinutes: actualMinutes,
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

    // MARK: - [[T-14321]] date chip urgency

    /// 2026-11-08 at noon, local: the reference "today" for the date-tone tests.
    private var reference: Date {
        DateFormatters.date(from: "2026-11-08")!.addingTimeInterval(12 * 3600)
    }

    private func tint(of prefix: String, _ task: MarkdownTaskEmbedRenderInfo) -> Color? {
        CadenceTaskEmbedTouchChips.chips(for: task, relativeTo: reference)
            .first { $0.title.hasPrefix(prefix) }?.tint
    }

    /// The bug: every Due chip was red. A due date still ahead -- tomorrow, next month -- or on
    /// the day itself is not overdue, and draws dim as the Mac card draws it.
    @Test func aDueDateNotYetPassedIsNotRed() {
        #expect(tint(of: "Due ", task(dueDate: "2026-11-09")) == Theme.dim)
        #expect(tint(of: "Due ", task(dueDate: "2026-12-20")) == Theme.dim)
        #expect(tint(of: "Due ", task(dueDate: "2026-11-08")) == Theme.dim)
        #expect(tint(of: "Due ", task(dueDate: "2026-11-07")) == Theme.red)
    }

    /// Work already done is not late, whatever its due date says.
    @Test func aFinishedTasksPastDueDateIsNotRed() {
        let done = task(statusRaw: TaskStatus.done.rawValue, isDone: true, dueDate: "2026-11-01")
        #expect(tint(of: "Due ", done) == Theme.dim)
    }

    /// Do: red once passed, the highlight accent on the day, dim ahead -- never a flat blue.
    @Test func aDoDateTakesTheMacCardsThreeHues() {
        #expect(tint(of: "Do ", task(scheduledDate: "2026-11-07")) == Theme.red)
        #expect(tint(of: "Do ", task(scheduledDate: "2026-11-08")) == Theme.markerHighlightAccent)
        #expect(tint(of: "Do ", task(scheduledDate: "2026-11-09")) == Theme.dim)
        #expect(tint(of: "Do ", task(statusRaw: TaskStatus.done.rawValue, isDone: true, scheduledDate: "2026-11-07")) == Theme.dim)
    }

    /// The shared rule the Mac card maps onto its own colours, pinned at the case level.
    @Test func theSharedToneRuleMatchesTheMacCard() {
        let today = "2026-11-08"
        #expect(CadenceTaskEmbedDateTone.dueDate(of: task(dueDate: "2026-11-07"), todayKey: today) == .overdue)
        #expect(CadenceTaskEmbedDateTone.dueDate(of: task(dueDate: "2026-11-08"), todayKey: today) == .neutral)
        #expect(CadenceTaskEmbedDateTone.dueDate(of: task(), todayKey: today) == .neutral)
        #expect(CadenceTaskEmbedDateTone.doDate(of: task(scheduledDate: "2026-11-07"), todayKey: today) == .overdue)
        #expect(CadenceTaskEmbedDateTone.doDate(of: task(scheduledDate: today), todayKey: today) == .today)
        #expect(CadenceTaskEmbedDateTone.doDate(of: task(), todayKey: today) == .neutral)
    }

    // MARK: - [[T-14322]] estimate chip words

    /// An estimate alone reads as itself, as the Mac card says it -- not "-/1h".
    @Test func anEstimateAloneReadsAsItself() {
        #expect(titles(task(estimatedMinutes: 60)) == ["1h"])
        #expect(titles(task(estimatedMinutes: 90)) == ["1h\u{00A0}30m"])
    }

    /// Time logged against a task with no estimate is still shown -- it drew no chip at all.
    @Test func loggedTimeWithNoEstimateStillDrawsAChip() {
        #expect(titles(task(actualMinutes: 30)) == ["30m/-"])
        #expect(titles(task(estimatedMinutes: 60, actualMinutes: 30)) == ["30m/1h"])
    }

    /// Neither figure: no chip on iOS, and `nil` from the shared rule the Mac card fills in.
    @Test func noEstimateAndNoLoggedTimeDrawsNoChip() {
        #expect(titles(task()).isEmpty)
        #expect(CadenceTaskEmbedEstimateLabel.label(for: task()) == nil)
    }

    // MARK: - The Mac card reads the same two rules

    /// By source: the Mac card is drawn by a text view no unit test can paint, and its chip builder
    /// is private. It must take its Do / Due hues and its estimate words from the rules above, or
    /// the two cards are free to drift apart again ([[T-14321]], [[T-14322]]).
    @Test func theMacCardReadsTheSharedDateToneAndEstimateRules() throws {
        let mac = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift"))
        let chips = try #require(CadenceSourceScan.functionBody(named: "displayChips", in: mac))
        #expect(chips.contains("color(for: CadenceTaskEmbedDateTone.doDate(of: task, todayKey: todayKey))"))
        #expect(chips.contains("color(for: CadenceTaskEmbedDateTone.dueDate(of: task, todayKey: todayKey))"))
        let estimate = try #require(CadenceSourceScan.functionBody(named: "estimateLabel", in: mac))
        #expect(estimate.contains("CadenceTaskEmbedEstimateLabel.label(for: task)"))
        let tone = try #require(CadenceSourceScan.functionBody(named: "color", in: mac))
        #expect(tone.contains("case .overdue: return MarkdownStylist.redColor"))
        #expect(tone.contains("case .today: return MarkdownStylist.highlightAccentColor"))
        #expect(tone.contains("case .neutral: return MarkdownStylist.dimColor"))
    }
}
