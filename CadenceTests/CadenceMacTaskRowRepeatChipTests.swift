// macOS only: `MacTaskRow` and its repeat picker are macOS views.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-5015]] (b), the second half: the Mac task row gains the recurrence picker iOS has.**
///
/// The owner's decision sent the entry's two "row chips" opposite ways. In Progress was removed
/// everywhere (`CadenceInProgressStatusRetirementTests`); the repeat mark was kept and brought to
/// macOS, because removing it from iOS was explicitly declined — it is a working control the owner
/// uses, and deleting it would push recurrence editing back into the inspector.
///
/// The writer underneath is `MacTaskRowContextMenu.selectRecurrenceRule`, already held by effect in
/// `MacTaskRowContextMenuEffectTests`. What is **not** held anywhere else, and is what this suite
/// owns, is that the row reaches it from a chip at all, and that the chip disposes of its three
/// answers the way the committing-popover contract requires.
@MainActor
struct CadenceMacTaskRowRepeatChipTests {

    // MARK: - The chip exists on the row

    /// The row draws the picker, and draws it only on a task that repeats — the same
    /// `recurrenceRule != .none` guard `iOSTaskRow` uses. A chip reading "Never" on every
    /// non-repeating row is dead chrome; a chip on no row at all is the gap this ticket closed.
    @Test func theRowDrawsTheRepeatPickerAndOnlyOnARecurringTask() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift")
        )
        // `declarationBody`, not `functionBody(named:)`: the strip is a computed property, and
        // that helper searches for `func <name>(`, so it would have found nothing and the
        // `#require` would have read as "the chip is missing" for the wrong reason.
        let strip = try #require(
            CadenceSourceScan.declarationBody("private var metadataStrip: some View", in: source),
            "metadataStrip is gone or its braces do not balance, so this reads nothing"
        )
        #expect(strip.contains("repeatChip"), "the Mac row's metadata strip draws no repeat chip")
        #expect(
            strip.contains("task.recurrenceRule != .none"),
            "the repeat chip is not guarded on the task actually repeating: \(strip)"
        )
    }

    /// The chip opens the picker rather than being a label. This is the distinction the owner was
    /// shown and decided on: the repeat mark is a *control*, which is why it survived while the
    /// read-only In Progress label did not.
    @Test func theChipOpensThePicker() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift")
        )
        let chip = try #require(
            CadenceSourceScan.declarationBody("private var repeatChip: some View", in: source),
            "repeatChip is gone or its braces do not balance, so this reads nothing"
        )
        #expect(chip.contains("showRepeatPicker = true"), "the chip does not open anything")
        #expect(chip.contains("MacTaskRowRepeatPickerPopover"), "the chip opens something other than the picker")
    }

    // MARK: - One writer, shared with the menu

    /// **The picker's only store write is the menu's writer.** Two Mac recurrence controls with two
    /// implementations is how they start disagreeing about a series member — the one branch that
    /// must never be skipped — so this asserts both that the shared static is called and that no
    /// second write path sits beside it.
    @Test func thePickerWritesOnlyThroughTheMenusSharedWriter() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/MacTaskRowRepeatPickerPopover.swift")
        )
        #expect(
            source.contains("MacTaskRowContextMenu.selectRecurrenceRule("),
            "the picker does not route through the menu's writer"
        )
        #expect(
            !source.contains("task.recurrenceRule ="),
            "the picker writes the rule itself, bypassing the series-scope branch"
        )
        #expect(
            !source.contains("applyRecurrenceRule("),
            "the picker reaches the recurrence workflow directly instead of through the shared writer"
        )
    }

    /// Parity with the iOS chip, stated as the thing that would drift: both row pickers offer
    /// **every** rule, `.none` included, because "Never" is how recurrence is turned off and a
    /// picker that cannot unset the field it names is a dead end.
    @Test func bothPlatformsRowPickersOfferEveryRule() throws {
        for path in [
            "Cadence/macOS/Views/MacTaskRowRepeatPickerPopover.swift",
            "Cadence/iOS/iOSTaskRowActionViews.swift",
        ] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(
                source.contains("TaskRecurrenceRule.allCases"),
                "\(path) does not offer every recurrence rule"
            )
        }
    }

    // MARK: - What the three answers do

    /// **A refused write keeps the popover open**, which is the whole of [[T-656]]'s committing
    /// form: the close *is* the success report, so closing over a refusal reports a write that did
    /// not happen. This is the one that bites — it is a pure function precisely so it can.
    @Test func onlyARefusalKeepsThePickerOpen() {
        #expect(MacTaskRowRepeatPickerPopover.closesPopover(for: .settled))
        #expect(MacTaskRowRepeatPickerPopover.closesPopover(for: .needsRecurrenceScope(.weekly)))
        #expect(
            MacTaskRowRepeatPickerPopover.closesPopover(for: .refused(.recurrence("nope"))) == false,
            "the picker closed over a refused write, reporting a change that did not land"
        )
    }

    /// A popover that stays open must say why, and one that closes must not leave a stale notice to
    /// greet the next open. The two functions are a pair and this is the half that pairs them.
    @Test func theNoticeIsShownExactlyWhenThePickerStaysOpen() {
        #expect(MacTaskRowRepeatPickerPopover.failureNotice(for: .settled) == nil)
        #expect(MacTaskRowRepeatPickerPopover.failureNotice(for: .needsRecurrenceScope(.daily)) == nil)
        #expect(
            MacTaskRowRepeatPickerPopover.failureNotice(for: .refused(.recurrence("nope")))
                == CadenceTaskFieldEditCommit.saveFailureNotice,
            "a refused rule change says nothing under the rows"
        )
        // The pairing itself: open iff there is a notice, across every outcome the writer returns.
        for outcome: MacTaskRowContextMenu.ActionOutcome in [
            .settled,
            .needsRecurrenceScope(.monthly),
            .refused(.recurrence("nope")),
        ] {
            #expect(
                MacTaskRowRepeatPickerPopover.closesPopover(for: outcome)
                    == (MacTaskRowRepeatPickerPopover.failureNotice(for: outcome) == nil),
                "\(outcome) either closes with a notice or stays open without one"
            )
        }
    }

    /// A series member's scope question is **not** a refusal: nothing was attempted, so there is
    /// nothing to report and the row's confirmation dialog is what asks next. Driven through the
    /// real writer rather than asserted on a hand-made outcome, so the two halves cannot drift.
    @Test func aSeriesMemberHandsTheRowAScopeQuestionRatherThanAFailure() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let task = AppTask(title: "Weekly review")
        task.recurrenceRule = .weekly
        context.insert(task)
        try context.save()

        let outcome = MacTaskRowContextMenu.selectRecurrenceRule(
            .daily,
            for: task,
            allTasks: [task],
            modelContext: context
        )

        #expect(outcome == .needsRecurrenceScope(.daily))
        #expect(MacTaskRowRepeatPickerPopover.closesPopover(for: outcome))
        #expect(MacTaskRowRepeatPickerPopover.failureNotice(for: outcome) == nil)
        #expect(task.recurrenceRule == .weekly, "the rule changed before the scope was answered")
    }

    // MARK: - [[T-9122]]: the note embed card's Repeat field is the same picker

    private static let embedPath = "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift"

    /// **The embed card's Repeat field draws the row chip's list and writes through its writer.**
    /// It drew a private option list -- a "Repeat" caption, a blue dot where the rule glyph goes, a
    /// 6pt corner -- and its own series branch, so one Mac field had two looks and two writers.
    @Test func theEmbedRepeatFieldDrawsTheSharedListAndWritesOnlyThroughTheRowsWriters() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.embedPath))
        #expect(source.contains("CadenceChoicePopoverList("), "the embed Repeat field draws its own list")
        #expect(source.contains("systemImage: rule.systemImage"), "the embed rows lost the rule glyph")
        #expect(source.contains("TaskRecurrenceRule.allCases"), "the embed field does not offer every rule")
        #expect(source.contains("MacTaskRowContextMenu.selectRecurrenceRule("), "the pick bypasses the row's writer")
        #expect(source.contains("MacTaskRowContextMenu.applyRecurrenceRule("), "the scope answer bypasses the row's writer")
        for retired in ["func optionList", "func optionButton", "TaskWorkflowService.applyRecurrenceRule(",
                        "CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(", "task.recurrenceRule ="] {
            #expect(!source.contains(retired), "the embed popover still holds its own \(retired)")
        }
    }

    /// **Only a settled write closes the embed list** -- unlike the row chip, which also closes on a
    /// scope question, because there the row hosts the dialog. Here the dialog hangs off the popover
    /// itself, so closing would dismiss the question with it; a refusal stays open as everywhere.
    @Test func theEmbedListClosesOnlyOnASettledWrite() {
        #expect(TaskEmbedFieldEditorPopover.recurrenceClosesPopover(for: .settled))
        #expect(
            TaskEmbedFieldEditorPopover.recurrenceClosesPopover(for: .needsRecurrenceScope(.weekly)) == false,
            "the embed list closed over its own scope dialog"
        )
        #expect(
            TaskEmbedFieldEditorPopover.recurrenceClosesPopover(for: .refused(.recurrence("nope"))) == false,
            "the embed list closed over a refused write"
        )
    }
}
#endif
