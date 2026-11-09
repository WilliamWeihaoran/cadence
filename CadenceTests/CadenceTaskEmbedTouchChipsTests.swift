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
        sectionName: String = "",
        containerName: String = "",
        isDone: Bool = false,
        isMissing: Bool = false,
        dueDate: String = "",
        scheduledDate: String = "",
        scheduledStartMin: Int = -1,
        estimatedMinutes: Int = 0,
        actualMinutes: Int = 0,
        recurrenceRaw: String = TaskRecurrenceRule.none.rawValue
    ) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: UUID(),
            title: "Write the brief",
            statusRaw: statusRaw,
            priorityRaw: priorityRaw,
            sectionName: sectionName,
            containerName: containerName,
            containerColorHex: "#4a9eff",
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            scheduledStartMin: scheduledStartMin,
            estimatedMinutes: estimatedMinutes,
            actualMinutes: actualMinutes,
            recurrenceRaw: recurrenceRaw,
            isDone: isDone,
            isCancelled: statusRaw == TaskStatus.cancelled.rawValue,
            isMissing: isMissing,
            subtasks: []
        )
    }

    private func titles(_ task: MarkdownTaskEmbedRenderInfo) -> [String] {
        CadenceTaskEmbedTouchChips.chips(for: task).map(\.title)
    }

    /// The chips beside the list chip every card now carries ([[T-14324]]).
    private func titlesBesideTheList(_ task: MarkdownTaskEmbedRenderInfo) -> [String] {
        CadenceTaskEmbedTouchChips.chips(for: task).filter { $0.field != .container }.map(\.title)
    }

    private func chip(_ field: MarkdownTaskEmbedField, of task: MarkdownTaskEmbedRenderInfo) -> CadenceTaskEmbedTouchChip? {
        CadenceTaskEmbedTouchChips.chips(for: task).first { $0.field == field }
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
        let done = chip(.status, of: task(statusRaw: TaskStatus.done.rawValue, isDone: true))
        #expect(done?.title == "Done")
        #expect(done?.tint == Theme.green)

        let cancelled = chip(.status, of: task(statusRaw: TaskStatus.cancelled.rawValue))
        #expect(cancelled?.title == "Canceled")
        #expect(cancelled?.tint == Theme.dim)
    }

    /// Low is blue on every other surface; green is what Done is on this same card.
    @Test func priorityChipTakesTheAppWidePriorityHue() {
        for priority in TaskPriority.allCases where priority != .none {
            let priorityChip = chip(.priority, of: task(priorityRaw: priority.rawValue))
            #expect(priorityChip?.title == priority.label)
            #expect(priorityChip?.tint == Theme.priorityColor(priority))
        }
        #expect(chip(.priority, of: task(priorityRaw: TaskPriority.low.rawValue))?.tint != Theme.green)
        // [[T-14324]]: the Mac card painted Medium in the marker-highlight yellow, not the amber
        // every other surface paints it.
        #expect(chip(.priority, of: task(priorityRaw: TaskPriority.medium.rawValue))?.tint == Theme.amber)
    }

    /// A reference whose task is gone says "Missing" and nothing else.
    @Test func aMissingReferenceSaysMissingAlone() {
        let chips = CadenceTaskEmbedTouchChips.chips(for: task(statusRaw: TaskStatus.cancelled.rawValue, isMissing: true))
        #expect(chips.map(\.title) == ["Missing"])
        #expect(chips.map(\.tint) == [Theme.red])
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
        // An untimed Do keeps its "Do " prefix; a timed one is pinned in the order test below.
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
        #expect(titlesBesideTheList(task(estimatedMinutes: 60)) == ["1h"])
        #expect(titlesBesideTheList(task(estimatedMinutes: 90)) == ["1h\u{00A0}30m"])
    }

    /// Time logged against a task with no estimate is still shown -- it drew no chip at all.
    @Test func loggedTimeWithNoEstimateStillDrawsAChip() {
        #expect(titlesBesideTheList(task(actualMinutes: 30)) == ["30m/-"])
        #expect(titlesBesideTheList(task(estimatedMinutes: 60, actualMinutes: 30)) == ["30m/1h"])
    }

    /// Neither figure: no chip on iOS, and `nil` from the shared rule the Mac card fills in.
    @Test func noEstimateAndNoLoggedTimeDrawsNoChip() {
        #expect(titlesBesideTheList(task()).isEmpty)
        #expect(CadenceTaskEmbedEstimateLabel.label(for: task()) == nil)
    }

    // MARK: - [[T-14324]] one row for both cards

    /// A task carrying every field: the row both cards draw, in one order.
    private var everyField: MarkdownTaskEmbedRenderInfo {
        task(
            statusRaw: TaskStatus.cancelled.rawValue,
            priorityRaw: TaskPriority.high.rawValue,
            sectionName: "Backlog",
            containerName: "Errands",
            dueDate: "2026-11-20",
            scheduledDate: "2026-11-09",
            scheduledStartMin: 9 * 60,
            estimatedMinutes: 60,
            recurrenceRaw: TaskRecurrenceRule.weekly.rawValue
        )
    }

    /// The order was status, priority, estimate, Do, Due, list on iOS and status, priority, list,
    /// section, Do, Due, estimate, repeat on the Mac card; iOS drew no section and no repeat chip.
    @Test func theRowIsStatusPriorityListSectionDoDueEstimateRepeat() {
        let chips = CadenceTaskEmbedTouchChips.chips(for: everyField, relativeTo: reference)
        #expect(chips.map(\.field) == [.status, .priority, .container, .section, .scheduledDate, .dueDate, .estimate, .recurrence])
        #expect(chips.first { $0.field == .section }?.title == "Backlog")
        #expect(chips.first { $0.field == .recurrence }?.title == TaskRecurrenceRule.weekly.label)
        // A timed Do reads as the Mac card says it, without the "Do " prefix.
        #expect(chips.first { $0.field == .scheduledDate }?.title == "Tomorrow \(TimeFormatters.timeString(from: 9 * 60))")
    }

    /// The default section draws no chip, on either card.
    @Test func theDefaultSectionDrawsNoChip() {
        let chips = CadenceTaskEmbedTouchChips.chips(for: task(sectionName: TaskSectionDefaults.defaultName, containerName: "Errands"))
        #expect(!chips.contains { $0.field == .section })
    }

    /// iOS drew no list chip for an Inbox task and a muted one for a list; both cards now say
    /// "Inbox" in the dim hue, and a list in its own colour.
    @Test func theListChipSaysInboxAndTakesTheListsColour() {
        let inbox = chip(.container, of: task())
        #expect(inbox?.title == "Inbox")
        #expect(inbox?.tint == Theme.dim)
        let list = chip(.container, of: task(containerName: "Errands"))
        #expect(list?.title == "Errands")
        #expect(list?.tint == Color(hex: "#4a9eff"))
    }

    /// Estimate was amber on iOS and blue on the Mac card; repeat was green on the Mac card alone.
    @Test func theEstimateAndRepeatHuesAreOneEach() {
        let chips = CadenceTaskEmbedTouchChips.chips(for: everyField, relativeTo: reference)
        #expect(chips.first { $0.field == .estimate }?.tint == Theme.blue)
        #expect(chips.first { $0.field == .recurrence }?.tint == Theme.green)
    }

    /// The iOS row is the shared row minus its empty fields -- the one difference the pointer
    /// answers -- with the same words, hues and importance for everything it keeps.
    @Test func theIOSRowIsTheSharedRowWithoutEmptyFields() {
        for fixture in [everyField, task(), task(containerName: "Errands", dueDate: "2026-11-07")] {
            let slots = CadenceTaskEmbedChipRow.slots(for: fixture, relativeTo: reference)
            let chips = CadenceTaskEmbedTouchChips.chips(for: fixture, relativeTo: reference)
            let filled = slots.filter { $0.title != nil }
            #expect(chips.map(\.field) == filled.map(\.field))
            #expect(chips.map(\.title) == filled.compactMap(\.title))
            #expect(chips.map(\.tint) == filled.map(\.tone.color))
            #expect(chips.map(\.importance) == filled.map(\.importance))
        }
        // An empty task: the shared row still offers Do, Due and estimate for the Mac placeholders.
        let empty = CadenceTaskEmbedChipRow.slots(for: task(), relativeTo: reference)
        #expect(empty.filter { $0.title == nil }.map(\.field) == [.scheduledDate, .dueDate, .estimate])
    }

    /// Both cards drop by importance: the due date outlives everything on a narrow row. iOS cut
    /// whatever sat last, which in the new order would have been the due date's neighbours first
    /// and the due date before the list.
    @Test func aNarrowRowKeepsTheDueDateAndDropsTheEstimateFirst() {
        let chips = CadenceTaskEmbedTouchChips.chips(for: everyField, relativeTo: reference)
        let widths = chips.map { _ in CGFloat(60) }
        let kept = CadenceTaskEmbedChipRow.keptIndices(importances: chips.map(\.importance), widths: widths, available: 60, gap: 6)
        #expect(kept.map { chips[$0].field } == [.dueDate])
        let three = CadenceTaskEmbedChipRow.keptIndices(importances: chips.map(\.importance), widths: widths, available: 192, gap: 6)
        #expect(three.map { chips[$0].field } == [.container, .scheduledDate, .dueDate])
        let all = CadenceTaskEmbedChipRow.keptIndices(importances: chips.map(\.importance), widths: widths, available: 10_000, gap: 6)
        #expect(all == Array(chips.indices))
    }

    #if os(macOS)
    /// The Mac card offers the same fields in the same order with the same words, plus its pointer
    /// placeholders for the empty ones -- and lays out from that row.
    @MainActor
    @Test func theMacCardOffersTheSameRow() {
        for fixture in [everyField, task(), task(containerName: "Errands", dueDate: "2026-11-07", actualMinutes: 30)] {
            let mac = MarkdownTaskEmbedDrawing.offeredChips(for: fixture)
            let slots = CadenceTaskEmbedChipRow.slots(for: fixture)
            #expect(mac.map(\.field) == slots.map(\.field))
            let iOS = CadenceTaskEmbedTouchChips.chips(for: fixture)
            let macFilled = mac.filter { offered in slots.contains { $0.field == offered.field && $0.title != nil } }
            #expect(macFilled.map(\.field) == iOS.map(\.field), "the Mac card's row is not the iOS card's")
            #expect(macFilled.map(\.label) == iOS.map(\.title), "the two cards word a chip differently")
        }
        // An Inbox task with nothing set: the list chip and the three placeholders.
        #expect(MarkdownTaskEmbedDrawing.offeredChips(for: task()).map(\.label) == ["Inbox", "No do date", "No due date", "No estimate"])
    }
    #endif

    /// By source: the Mac card's chip builder is private and drawn by a text view no unit test can
    /// paint. It must take its row and its hues from the shared builder, or the two cards are free
    /// to drift apart again ([[T-14321]], [[T-14322]], [[T-14324]]).
    @Test func theMacCardReadsTheSharedRow() throws {
        let mac = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift"))
        let chips = try #require(CadenceSourceScan.functionBody(named: "displayChips", in: mac))
        #expect(chips.contains("CadenceTaskEmbedChipRow.slots(for: task)"))
        #expect(chips.contains("color: nsColor(for: slot.tone)"))
        #expect(!chips.contains("MarkdownStylist."), "the Mac card picks a chip hue of its own again")
        let tone = try #require(CadenceSourceScan.functionBody(named: "nsColor", in: mac))
        #expect(tone.contains("NSColor(tone.color)"))
        let kept = try #require(CadenceSourceScan.functionBody(named: "keptChipIndices", in: mac))
        #expect(kept.contains("CadenceTaskEmbedChipRow.keptIndices("))
    }
}
