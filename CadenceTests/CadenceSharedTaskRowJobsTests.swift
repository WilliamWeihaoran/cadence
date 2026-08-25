import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-172: tasks are rendered by ~13 views doing ~5 jobs. Two of those jobs, unified.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning
/// `CadenceBundleTaskRowMetrics.titleLineLimit == 2` proves the shared figure is right; it proves
/// nothing about anybody *using* it. T-161 is the standing example — a committed fix was reverted
/// with the whole suite green, because the tests pinned a helper while nothing observed the call
/// sites. So every decision below also gets a call-site test that reads the real source files and
/// fails the moment a card or a row goes back to its own copy.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The precedent is `CadenceSharedBoardChromeTests`, whose helpers this file follows — exact
/// per-file counts rather than "contains", comment-stripping rather than allowlisting, and a
/// non-vacuity test so a broken scan cannot make the absence assertions pass silently.
@MainActor
struct CadenceSharedTaskRowJobsTests {

    // MARK: - Board card metadata: the rules

    private func task(
        doDate: String = "",
        dueDate: String = "",
        isDone: Bool = false
    ) -> AppTask {
        let task = AppTask(title: "T")
        task.scheduledDate = doDate
        task.dueDate = dueDate
        task.status = isDone ? .done : .todo
        return task
    }

    /// Do date, due date, then the list. The dates come first because they are the two facts that
    /// change what you do next; the list is identity, not state.
    @Test func theStripStatesTheDatesBeforeTheList() {
        let chips = CadenceBoardCardMetadata.chips(
            for: task(doDate: "2026-08-20", dueDate: "2026-08-25"),
            showsContainer: true,
            todayKey: "2026-08-20"
        )

        #expect(chips.map(\.kind) == [.doDate, .dueDate, .list])
    }

    /// A field with no value contributes no chip. macOS keeps an empty `Due` chip on its own cards
    /// because that chip *is* the due-date picker, and that affordance stays in the macOS card —
    /// the shared descriptor describes what a card **states**, and an empty chip states nothing.
    @Test func anEmptyFieldStatesNothing() {
        #expect(CadenceBoardCardMetadata.chips(for: task(), showsContainer: false).isEmpty)
        #expect(CadenceBoardCardMetadata.doDateChip(for: task(), todayKey: "2026-08-20") == nil)
        #expect(CadenceBoardCardMetadata.dueDateChip(for: task(), todayKey: "2026-08-20") == nil)
    }

    /// `showsContainer` is the one per-board knob, and it is the only thing that suppresses a chip
    /// whose field has a value.
    @Test func theListChipIsTheOnlyChipABoardCanTurnOff() {
        let scheduled = task(doDate: "2026-08-20", dueDate: "2026-08-25")

        #expect(
            CadenceBoardCardMetadata.chips(for: scheduled, showsContainer: false).map(\.kind)
                == [.doDate, .dueDate]
        )
    }

    /// **The bug this unification closes.** The iOS card built its own chip list and had no do-date
    /// chip in it at all, so a task planned for today read as planned on a Mac board and as undated
    /// on an iPad one. One descriptor, one answer.
    @Test func aTaskPlannedForTodayStatesItsDoDate() {
        let chips = CadenceBoardCardMetadata.chips(
            for: task(doDate: "2026-08-20"),
            showsContainer: false,
            todayKey: "2026-08-20"
        )

        #expect(chips.count == 1)
        #expect(chips.first?.kind == .doDate)
        #expect(chips.first?.icon == CadenceBoardCardMetadata.doDateIcon)
        #expect(chips.first?.emphasis == .attention)
    }

    /// Over-do outranks do-today, and a finished task is neither — the same `isDone` guard
    /// `AppTask.isOverdue(todayKey:)` applies to the deadline. This was macOS's three-way choice,
    /// computed inline in `doDateMetaItem`, with no iOS counterpart to disagree with it.
    @Test func theDoDatesEmphasisRanksOverdoAboveTodayAndExemptsFinishedWork() {
        #expect(CadenceBoardCardMetadata.doDateEmphasis(for: task(doDate: "2026-08-19"), todayKey: "2026-08-20") == .urgent)
        #expect(CadenceBoardCardMetadata.doDateEmphasis(for: task(doDate: "2026-08-20"), todayKey: "2026-08-20") == .attention)
        #expect(CadenceBoardCardMetadata.doDateEmphasis(for: task(doDate: "2026-08-21"), todayKey: "2026-08-20") == .neutral)
        #expect(
            CadenceBoardCardMetadata.doDateEmphasis(
                for: task(doDate: "2026-08-19", isDone: true),
                todayKey: "2026-08-20"
            ) == .neutral
        )
    }

    @Test func theDueChipGoesUrgentOnlyWhileTheWorkIsUnfinished() {
        #expect(
            CadenceBoardCardMetadata.dueDateChip(for: task(dueDate: "2026-08-19"), todayKey: "2026-08-20")?.emphasis
                == .urgent
        )
        #expect(
            CadenceBoardCardMetadata.dueDateChip(for: task(dueDate: "2026-08-19", isDone: true), todayKey: "2026-08-20")?.emphasis
                == .neutral
        )
        #expect(
            CadenceBoardCardMetadata.dueDateChip(for: task(dueDate: "2026-08-25"), todayKey: "2026-08-20")?.emphasis
                == .neutral
        )
    }

    /// A task in no list is in the Inbox, which is a real place — so the chip names it rather than
    /// going blank. Both cards already agreed on this one; it is stated once now.
    @Test func aTaskInNoListNamesTheInbox() {
        let chip = CadenceBoardCardMetadata.listChip(for: task())

        #expect(chip.text == CadenceBoardCardMetadata.inboxLabel)
        #expect(chip.icon == CadenceBoardCardMetadata.inboxIcon)
    }

    /// Identity and emphasis are two colours, not one pre-blended one, because the two cards apply
    /// them differently on purpose: macOS keeps the red flag red on an unhurried due date and tints
    /// only the label, and iOS's inert chip tints both because a tinted glyph beside grey text read
    /// as disabled. A due chip whose glyph went neutral would stop being identifiable as the due
    /// chip; a neutral *label* is just a date nobody needs to hurry about.
    @Test func identityHoldsStillWhileEmphasisMoves() {
        let comfortable = CadenceBoardCardMetadata.dueDateChip(for: task(dueDate: "2026-08-25"), todayKey: "2026-08-20")
        let late = CadenceBoardCardMetadata.dueDateChip(for: task(dueDate: "2026-08-19"), todayKey: "2026-08-20")

        #expect(comfortable?.identityColor == Theme.red)
        #expect(late?.identityColor == Theme.red)
        #expect(comfortable?.labelColor == Theme.dim)
        #expect(late?.labelColor == Theme.red)
    }

    /// `.attention` is the chip's **own** identity rather than a fourth colour: a do date that is
    /// today reads amber, which is what "do date" means everywhere else in the app.
    @Test func attentionBorrowsTheChipsOwnIdentityRatherThanInventingAColour() {
        let today = CadenceBoardCardMetadata.doDateChip(for: task(doDate: "2026-08-20"), todayKey: "2026-08-20")

        #expect(today?.emphasis == .attention)
        #expect(today?.labelColor == Theme.amber)
        #expect(today?.labelColor == today?.identityColor)
    }

    // MARK: - Board card metadata: the call sites

    /// **The T-161 test for the board card.** Both cards must reach the one descriptor. Revert
    /// either to its own inline list — which is exactly the state that let iOS drop the do date —
    /// and this fails; pinning the rules above would not have noticed.
    @Test func bothBoardCardsStateWhatTheSharedDescriptorSays() throws {
        try expectCallSites(
            of: "CadenceBoardCardMetadata.chips",
            at: [
                "Cadence/macOS/Views/KanbanCardView.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
            ]
        )
    }

    /// The glyphs and the Inbox fallback moved into the descriptor, so neither card may spell them
    /// again. This is the check that catches a card re-deriving one chip while still calling the
    /// shared function for the others — the exact half-revert an exact call count cannot see.
    @Test func neitherBoardCardSpellsAChipsGlyphOrItsInboxFallbackItself() throws {
        for path in ["Cadence/macOS/Views/KanbanCardView.swift", "Cadence/iOS/iOSBoardCards.swift"] {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("\"sun.max.fill\""), "\(path) spells the do-date glyph itself again")
            #expect(!code.contains("\"tray.fill\""), "\(path) spells the Inbox fallback glyph itself again")
            #expect(!code.contains("\"Inbox\""), "\(path) spells the Inbox fallback label itself again")
        }
    }

    // MARK: - T-174: a chip that would repeat the surface's own day

    /// **The rule, and it is an equality — not "day columns hide the do date".** A board column that
    /// has already named its day in its header does not need every card under it to name the day
    /// again. Everything else on the strip is untouched: the deadline and the list are facts the
    /// column has not stated.
    @Test func aDoDateThatOnlyRepeatsTheSurfacesOwnDayIsOmitted() {
        let chips = CadenceBoardCardMetadata.chips(
            for: task(doDate: "2026-08-20", dueDate: "2026-08-25"),
            showsContainer: true,
            dayAlreadyStatedBySurface: "2026-08-20",
            todayKey: "2026-08-20"
        )

        #expect(chips.map(\.kind) == [.dueDate, .list])
    }

    /// **The narrowness is the point, and it is what keeps the board's only urgency cue alive.** The
    /// do chip's `.urgent` red is the sole per-card over-do signal, so the suppression is conditioned
    /// on the dates actually matching rather than on the *kind* of column doing the drawing. Both
    /// boards bucket day columns on the do date today, so this case does not arise — and if a future
    /// bucketing change makes it arise, the chip and its colour come back on their own instead of
    /// being silently swallowed. Spelled as "day columns omit it", this test could not exist.
    @Test func aDoDateTheSurfaceHasNotStatedKeepsItsChipAndItsUrgency() {
        let chips = CadenceBoardCardMetadata.chips(
            for: task(doDate: "2026-08-19"),
            showsContainer: false,
            dayAlreadyStatedBySurface: "2026-08-21",
            todayKey: "2026-08-20"
        )

        #expect(chips.map(\.kind) == [.doDate])
        #expect(chips.first?.emphasis == .urgent)
        #expect(chips.first?.labelColor == Theme.red)
    }

    /// A surface that names no day passes nothing and gets the whole strip — the default has to be
    /// the *showing* one, or a caller that forgets the knob loses a chip rather than gaining one.
    /// An empty string counts as naming nothing, so a caller whose date key has not resolved yet
    /// cannot suppress the chip on every card at once.
    @Test func theSurfaceDayKnobDefaultsToStatingNothing() {
        let planned = task(doDate: "2026-08-20")

        #expect(CadenceBoardCardMetadata.chips(for: planned, showsContainer: false).map(\.kind) == [.doDate])
        #expect(
            CadenceBoardCardMetadata.chips(for: planned, showsContainer: false, dayAlreadyStatedBySurface: "")
                .map(\.kind) == [.doDate]
        )
        #expect(!CadenceBoardCardMetadata.repeatsSurfaceDay("2026-08-20", dayAlreadyStatedBySurface: nil))
        #expect(!CadenceBoardCardMetadata.repeatsSurfaceDay("2026-08-20", dayAlreadyStatedBySurface: ""))
        // An undated task has no chip to suppress, so it can never match a stated day.
        #expect(!CadenceBoardCardMetadata.repeatsSurfaceDay("", dayAlreadyStatedBySurface: ""))
        #expect(CadenceBoardCardMetadata.repeatsSurfaceDay("2026-08-20", dayAlreadyStatedBySurface: "2026-08-20"))
    }

    /// The knob reaches the **do** date only. A day column names the day a card is planned for, not
    /// the day it is owed — a task due on the column's date and planned for another one keeps the
    /// deadline it would otherwise have lost.
    @Test func theSurfaceDayKnobDoesNotReachTheDeadline() {
        let chips = CadenceBoardCardMetadata.chips(
            for: task(doDate: "2026-08-22", dueDate: "2026-08-20"),
            showsContainer: false,
            dayAlreadyStatedBySurface: "2026-08-20",
            todayKey: "2026-08-20"
        )

        #expect(chips.map(\.kind) == [.doDate, .dueDate])
    }

    // MARK: - T-174: the call sites

    /// **The T-161 test for the surface-day knob.** Pinning the rule above proves nothing about
    /// anybody passing it — that is exactly the hole a green suite hid last time. Both platforms'
    /// day columns must hand their date key to every card they draw, including the ones in the
    /// Completed footer, and the surfaces that name a *bucket* rather than a day must not.
    @Test func bothPlatformsDayColumnsTellTheCardWhichDayTheyHaveAlreadyNamed() throws {
        try expectOccurrences(
            of: "dayAlreadyStatedBySurface: dateKey",
            at: [
                // Active cards and the Completed footer's cards, each platform.
                "Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift": 2,
                "Cadence/iOS/iOSCalendarBoardView.swift": 2,
            ]
        )
    }

    /// The other half, and the half that stops the knob spreading by copy: a rail is an inbox and a
    /// section column is a list, so neither has stated a day and neither may claim to have.
    @Test func theRailsAndTheSectionColumnsStateNoDayAndClaimNone() throws {
        try expectOccurrences(
            of: "dayAlreadyStatedBySurface",
            at: [
                "Cadence/macOS/Views/CalendarBoardRailSupportViews.swift": 0,
                "Cadence/macOS/Views/KanbanColumnSupportViews.swift": 0,
                "Cadence/iOS/iOSListSupportViews.swift": 0,
            ]
        )
    }

    // MARK: - T-173: what a board card lists beneath the task

    private func task(unfinished: Int, finished: Int = 0, isDone: Bool = false) -> AppTask {
        let task = AppTask(title: "T")
        task.status = isDone ? .done : .todo
        task.subtasks = (0..<unfinished).map { index in
            let subtask = Subtask(title: "open \(index)")
            subtask.order = index
            return subtask
        } + (0..<finished).map { index in
            let subtask = Subtask(title: "done \(index)")
            subtask.order = unfinished + index
            subtask.isDone = true
            return subtask
        }
        return task
    }

    /// **macOS's card listed every subtask it had, uncapped, done ones included.** One task with
    /// twelve of them was taller than the column. The cap is not a new opinion — it is
    /// `rowSubtaskLimit`, already measured on a phone for the task rows — and the answer is a named
    /// list with a count of the remainder, not a `3/5` chip, which is the spelling that rule
    /// explicitly rejects for stating a number of things to do without stating one of them.
    @Test func aCardListsTheUnfinishedSubtasksUpToTheSharedCapAndCountsTheRest() {
        let twelve = task(unfinished: 12)

        #expect(
            CadenceTaskPresentationSupport.listedSubtasks(for: twelve).count
                == CadenceTaskPresentationSupport.rowSubtaskLimit
        )
        #expect(CadenceTaskPresentationSupport.listedSubtasks(for: twelve).allSatisfy { !$0.isDone })
        #expect(
            CadenceTaskPresentationSupport.unlistedSubtaskCount(for: twelve)
                == 12 - CadenceTaskPresentationSupport.rowSubtaskLimit
        )

        let two = task(unfinished: 2, finished: 4)
        #expect(CadenceTaskPresentationSupport.listedSubtasks(for: two).map(\.title) == ["open 0", "open 1"])
        #expect(CadenceTaskPresentationSupport.unlistedSubtaskCount(for: two) == nil)
    }

    /// Nothing under a finished task, and nothing counted either. A completed card's leftover
    /// checklist items are not work any more, and a board column's Completed footer would otherwise
    /// fill with tickable rows belonging to tasks that are over. The gate lived at one call site —
    /// iOS's task row — and the three surfaces that gained a list would each have had to remember it.
    @Test func aFinishedTaskListsNoSubtasksAndHidesNone() {
        let done = task(unfinished: 9, isDone: true)

        #expect(CadenceTaskPresentationSupport.listedSubtasks(for: done).isEmpty)
        #expect(CadenceTaskPresentationSupport.unlistedSubtaskCount(for: done) == nil)
        // The ungated primitive is unchanged: this is the gate, not a new cap.
        #expect(CadenceTaskPresentationSupport.allUnfinishedSubtasks(for: done).count == 9)
    }

    // MARK: - T-173: the call sites

    /// **The T-161 test for T-173.** Both cards must list tags and subtasks through the shared
    /// figures. An exact count per file is what catches one card quietly going back to its own
    /// answer — which is the state this ticket existed to close, in the direction of iOS having
    /// neither and macOS having an uncapped one.
    @Test func bothBoardCardsListTagsAndSubtasksFromTheSharedFigures() throws {
        try expectCallSites(
            of: "CompactTagStrip",
            at: [
                "Cadence/macOS/Views/KanbanCardMetaSupportViews.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
            ]
        )
        try expectOccurrences(
            of: "CadenceTaskPresentationSupport.rowTagLimit",
            at: [
                "Cadence/macOS/Views/KanbanCardMetaSupportViews.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
            ]
        )
        try expectCallSites(
            of: "CadenceTaskPresentationSupport.listedSubtasks",
            at: [
                "Cadence/macOS/Views/KanbanCardView.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
                // The row the shared pair was extracted from, which must keep reading it rather
                // than re-deriving the finished-task gate beside it.
                "Cadence/iOS/iOSTaskViews.swift": 1,
            ]
        )
        try expectCallSites(
            of: "CadenceTaskPresentationSupport.unlistedSubtaskCount",
            at: [
                "Cadence/macOS/Views/KanbanCardView.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1,
            ]
        )
    }

    /// The uncapped spelling may not come back. macOS's card read `task.subtasks` directly and
    /// sorted the lot; a card that touches the relationship at all is a card deciding for itself how
    /// much of a checklist fits in a column.
    @Test func neitherBoardCardReachesPastTheCapIntoTheRelationship() throws {
        for path in ["Cadence/macOS/Views/KanbanCardView.swift", "Cadence/iOS/iOSBoardCards.swift"] {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("task.subtasks"), "\(path) reads the subtask relationship directly again")
            #expect(!code.contains("limit: 3"), "\(path) spells the tag cap itself again")
        }
    }

    /// `CompactTagStrip` was inside `#if os(macOS)`, which is why a *shared* file carried a private
    /// line-for-line copy of it with a comment asking for this move. One strip, declared once.
    @Test func thereIsOneReadOnlyTagStripAndItIsShared() throws {
        try expectNoLiveMention(of: "NoteRowTagStrip")

        let declarations = try swiftFiles(under: "Cadence").filter { path in
            try! strippingComments(sourceFile(path)).contains("struct CompactTagStrip")
        }
        #expect(declarations == ["Cadence/Shared/Components/CadenceTagChip.swift"])
    }

    // MARK: - Bundle member row: the figures

    /// 13pt, which all three rows already drew, and `.medium`, which two of the three did. A member
    /// of a bundle is a row in a list; the bundle's own title is the heading above it, and the
    /// timeline inspector's `.semibold` made every row compete with it.
    @Test func theBundleRowsTitleIsARowNotAHeading() {
        #expect(CadenceBundleTaskRowMetrics.titleSize == 13)
        #expect(CadenceBundleTaskRowMetrics.titleWeight == .medium)
    }

    /// **Two, and iOS had it.** The two macOS rows clamped a bundle member's title to one line.
    /// This is not a second opinion about line limits — it is the app's existing answer for a task
    /// row, read from the same constant, so the two cannot drift apart again.
    @Test func theBundleRowWrapsATitleLikeEveryOtherTaskRow() {
        #expect(CadenceBundleTaskRowMetrics.titleLineLimit == 2)
        #expect(CadenceBundleTaskRowMetrics.titleLineLimit == CadenceTaskRowMetrics.titleLineLimit)
    }

    // MARK: - Bundle member row: what the second line says

    /// The estimate in the app's duration vocabulary, and **nothing** when there is no estimate.
    /// The timeline inspector's row said `max(estimatedMinutes, 5)m`, which spelled a value the
    /// rest of the app renders `1h 30m` in raw minutes and floored it at five — the exact spelling
    /// `AppTask.timelineDurationMinutes` documents as rejected, because a floor "cannot tell 'no
    /// estimate' from 'a deliberate short estimate'".
    ///
    /// `estimatedMinutes = 0` is written out rather than left to the initializer: the stored
    /// default is **30**, and zero is the app's only "unset" sentinel. A fresh task has a real
    /// half-hour estimate and the row states it.
    @Test func theBundleRowStatesARealEstimateOrNone() {
        let none = AppTask(title: "T")
        none.estimatedMinutes = 0
        #expect(CadenceBundleTaskRowSupport.leadLabel(for: none, includesLoggedTime: false) == nil)

        let fresh = AppTask(title: "T")
        #expect(fresh.estimatedMinutes == AppTask.defaultTimelineDurationMinutes)
        #expect(CadenceBundleTaskRowSupport.leadLabel(for: fresh, includesLoggedTime: false) == "30m")

        let ninety = AppTask(title: "T")
        ninety.estimatedMinutes = 90
        #expect(
            CadenceBundleTaskRowSupport.leadLabel(for: ninety, includesLoggedTime: false)
                == CadenceTaskPresentationSupport.estimateLabel(minutes: 90)
        )
        #expect(CadenceBundleTaskRowSupport.leadLabel(for: ninety, includesLoggedTime: false)?.contains("1h") == true)
    }

    /// The one difference that is earned: the Focus panel hands the session's minutes to the tasks
    /// you tick, so logged-against-estimate is the number that panel is about.
    @Test func onlyTheFocusPanelStatesLoggedTime() {
        let task = AppTask(title: "T")
        task.estimatedMinutes = 60
        task.actualMinutes = 45

        #expect(
            CadenceBundleTaskRowSupport.leadLabel(for: task, includesLoggedTime: true)
                == TimeFormatters.durationLabel(actual: 45, estimated: 60)
        )
        #expect(CadenceBundleTaskRowSupport.leadLabel(for: task, includesLoggedTime: false)?.contains("45") == false)
    }

    /// **The bug this unification closes.** iOS's bundle member row spent its second line on
    /// priority and had nowhere left to say a task in the block was overdue. Every bundle member
    /// row states the deadline now, and the overdue flag rides with it so the due segment can go
    /// red without staining the estimate beside it.
    @Test func everyBundleMemberRowCanSayTheWorkIsLate() {
        let late = AppTask(title: "T")
        late.dueDate = "2026-08-19"
        late.estimatedMinutes = 30

        let parts = CadenceBundleTaskRowSupport.detailParts(for: late, todayKey: "2026-08-20")

        #expect(parts.due != nil)
        #expect(parts.isOverdue)
        #expect(parts.lead != nil)

        let done = AppTask(title: "T")
        done.dueDate = "2026-08-19"
        done.status = .done
        #expect(!CadenceBundleTaskRowSupport.detailParts(for: done, todayKey: "2026-08-20").isOverdue)
    }

    // MARK: - Bundle member row: the call sites

    /// **The T-161 test for the bundle row.** All three rows — two macOS, one iOS — must read the
    /// one detail line. The iOS entry is the one that matters most: that row is the reason
    /// `TaskDetailLineLabel` had to leave `#if os(macOS)`.
    @Test func allThreeBundleMemberRowsReadTheOneDetailLine() throws {
        try expectCallSites(
            of: "CadenceBundleTaskRowSupport.detailParts",
            at: [
                "Cadence/macOS/Views/TimelineBundleBlockSupportViews.swift": 1,
                "Cadence/macOS/Views/FocusBundleTaskSupportViews.swift": 1,
                "Cadence/iOS/iOSCalendarBundleDetailSheet.swift": 1,
            ]
        )
        try expectCallSites(
            of: "CadenceTaskDetailLineLabel",
            at: [
                "Cadence/macOS/Views/TimelineBundleBlockSupportViews.swift": 1,
                "Cadence/macOS/Views/FocusBundleTaskSupportViews.swift": 1,
                "Cadence/iOS/iOSCalendarBundleDetailSheet.swift": 1,
                // The focus rows and the bundle picker, which already used it under its old name.
                "Cadence/macOS/Views/FocusSidebarSupportViews.swift": 1,
                "Cadence/macOS/Views/FocusPickerSupportViews.swift": 1,
                "Cadence/macOS/Views/TaskBundlePickerSupportViews.swift": 1,
            ]
        )
    }

    /// The macOS-guarded spelling may not come back. `excludingPrefixes` lets the shared name
    /// through and nothing else, so re-declaring `TaskDetailLineLabel` beside it fails here.
    @Test func theMacOSOnlyDetailLineSpellingIsGone() throws {
        try expectNoLiveMention(of: "TaskDetailLineLabel", excludingPrefixes: ["Cadence"])
    }

    /// **The leading glyph collision.** The Focus panel's row uses its leading control to include a
    /// task in the session's time log — not to finish it — and it drew that with
    /// `checkmark.circle.fill` in `Theme.green`: the app's completion glyph, in the app's completion
    /// colour, two clicks away from two other bundle member rows where the same glyph *is*
    /// completion state. A square reads as a checkbox.
    @Test func theFocusPanelsSelectionControlDoesNotWearTheCompletionGlyph() throws {
        let code = try strippingComments(sourceFile("Cadence/macOS/Views/FocusBundleTaskSupportViews.swift"))

        #expect(!code.contains("checkmark.circle.fill"), "the time-log selection control looks like completion again")
        #expect(code.contains("checkmark.square.fill"))
    }

    // MARK: - T-175: the primary row's metrics, and the macOS reader that was missing

    /// **The thing T-175 was actually about.** `CadenceTaskRowMetrics` had five iOS readers and
    /// zero macOS ones while `MacTaskRow` hardcoded the same figures inline — a shared metrics type
    /// that one platform never adopted, which is precisely the shape `iOSPageHeaderMetrics` had
    /// before `5aa11dc` renamed it and gave macOS a third tier.
    @Test func thereIsAThirdRowTierAndItIsNotRegularRelabelled() {
        #expect(CadenceTaskRowSurface.allCases.count == 3)
        #expect(CadenceTaskRowMetrics.metrics(for: .compact) == .compactWidth)
        #expect(CadenceTaskRowMetrics.metrics(for: .regular) == .regularWidth)
        #expect(CadenceTaskRowMetrics.metrics(for: .desktop) == .desktop)

        // iOS's boolean spelling still resolves to the two width tiers and never to desktop.
        #expect(CadenceTaskRowMetrics.metrics(isRegularWidth: true) == .regularWidth)
        #expect(CadenceTaskRowMetrics.metrics(isRegularWidth: false) == .compactWidth)
        #expect(CadenceTaskRowMetrics.metrics(isRegularWidth: true) != .desktop)
    }

    /// The two figures that had to stay split, and the reason each is a real difference rather than
    /// drift: a pointer can land on a row a finger cannot, and each platform's row title is tuned to
    /// its own type scale. Averaging either would read as a tidy-up and ship a regression.
    @Test func theTwoSplitFiguresStaySplitInTheDirectionThatIsEarned() {
        // Tighter than *both* touch tiers, not a point on a compact→regular ramp.
        #expect(CadenceTaskRowMetrics.desktop.verticalPadding == 8)
        #expect(CadenceTaskRowMetrics.desktop.verticalPadding < CadenceTaskRowMetrics.compactWidth.verticalPadding)
        #expect(CadenceTaskRowMetrics.desktop.verticalPadding < CadenceTaskRowMetrics.regularWidth.verticalPadding)

        // Louder than either iOS width, and one size across both of those.
        #expect(CadenceTaskRowMetrics.desktop.titleFontSize == 15)
        #expect(CadenceTaskRowMetrics.compactWidth.titleFontSize == CadenceTaskRowMetrics.regularWidth.titleFontSize)
        #expect(CadenceTaskRowMetrics.desktop.titleFontSize > CadenceTaskRowMetrics.regularWidth.titleFontSize)
    }

    /// And the figures that turned out to be one number after all — the payoff for stating three
    /// tiers in one place rather than two of them in a shared type and one set inline.
    @Test func desktopAndRegularAgreeWhereThereWasNothingToDisagreeAbout() {
        #expect(CadenceTaskRowMetrics.desktop.horizontalPadding == CadenceTaskRowMetrics.regularWidth.horizontalPadding)
        #expect(CadenceTaskRowMetrics.desktop.badgeSpacing == CadenceTaskRowMetrics.regularWidth.badgeSpacing)

        // The three the macOS row cannot use are stated at compact's answers — a narrow pane's — so
        // the tier is total rather than holed. Nothing reads them; the test below pins that.
        #expect(CadenceTaskRowMetrics.desktop.summarySpacing == CadenceTaskRowMetrics.compactWidth.summarySpacing)
        #expect(CadenceTaskRowMetrics.desktop.secondaryLineLimit == CadenceTaskRowMetrics.compactWidth.secondaryLineLimit)
        #expect(CadenceTaskRowMetrics.desktop.notesPreviewLimit == CadenceTaskRowMetrics.compactWidth.notesPreviewLimit)
    }

    /// **The call-site half, and the reason this file exists.** T-161 is the standing example: a
    /// committed fix was revertible with the whole suite green because the tests pinned a helper
    /// while nothing observed the call site. Exact counts, so restoring *one* inline literal fails.
    @Test func theMacRowDrawsItselfFromTheSharedFiguresRatherThanItsOwn() throws {
        try expectOccurrences(
            of: "CadenceTaskRowMetrics { .desktop }",
            // The row and its estimate chip. The chip is its own `View` struct so its popover
            // `@State` cannot invalidate the row; it reads the tier directly for the same reason.
            at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 2]
        )

        for (figure, count) in [
            ("metrics.horizontalPadding", 1),
            ("metrics.verticalPadding", 1),
            ("metrics.contentSpacing", 3),
            ("metrics.badgeSpacing", 7),
            ("metrics.titleFontSize", 1),
            ("metrics.secondaryFontSize", 5)
        ] {
            try expectOccurrences(of: figure, at: ["Cadence/macOS/Views/TasksPanelComponents.swift": count])
        }
    }

    /// The inline literals the row used to carry. Zero expectations are the point: this is what
    /// fails if someone "simplifies" a `metrics.` read back to the number it resolves to.
    @Test func theMacRowsOwnCopiesOfThoseFiguresAreGone() throws {
        for literal in [
            ".font(.system(size: 15))",
            ".padding(.vertical, 8)",
            ".padding(.leading, 14)",
            "size: 11, weight: .medium"
        ] {
            try expectOccurrences(of: literal, at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 0])
        }
    }

    /// The three figures macOS deliberately does **not** read, pinned so the exception cannot decay
    /// into an oversight — and pinned positively on iOS so a zero here means "macOS abstains", not
    /// "the scan found nothing".
    ///
    /// `titleLineLimit`: the macOS row is one `HStack` with a `Spacer` and trailing metadata, so its
    /// height is fixed; iOS's is a `VStack` built to grow. `completionGlyphSize`: not the same
    /// measurement — iOS's is a layout box around a 16pt disc, expanded to a 44pt touch target,
    /// while macOS's would also be an SF Symbol point size, and its four macOS call sites already
    /// use that as a per-surface type ramp (12 / 13 / 15 / 18).
    @Test func theMacRowAbstainsFromTheThreeFiguresThatAreNotItsMeasurements() throws {
        for figure in ["titleLineLimit", "completionGlyphSize", "completionCircleDiameter", "summarySpacing", "secondaryLineLimit", "notesPreviewLimit"] {
            try expectOccurrences(of: figure, at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 0])
        }

        try expectOccurrences(
            of: "CadenceTaskRowMetrics.titleLineLimit",
            at: ["Cadence/iOS/iOSTaskViews.swift": 1, "Cadence/iOS/iOSInboxRemindersSection.swift": 1]
        )
        try expectOccurrences(
            of: "metrics.completionGlyphSize",
            at: ["Cadence/iOS/iOSTaskViews.swift": 3, "Cadence/iOS/iOSInboxRemindersSection.swift": 3]
        )
    }

    /// Both iOS rows had the title size typed out too, in the file that reads the metrics for
    /// everything else. One figure, three readers.
    @Test func bothIOSRowsTakeTheirTitleSizeFromTheSharedFigureAsWell() throws {
        try expectOccurrences(
            of: "metrics.titleFontSize",
            at: ["Cadence/iOS/iOSTaskViews.swift": 1, "Cadence/iOS/iOSInboxRemindersSection.swift": 1]
        )
        try expectOccurrences(
            of: "size: 13, weight: .medium",
            at: ["Cadence/iOS/iOSTaskViews.swift": 0, "Cadence/iOS/iOSInboxRemindersSection.swift": 0]
        )
    }

    /// The hard constraint that predates T-175 and survives it. `MacTaskRow` gained a `metrics`
    /// property and lost five literals; neither it nor the estimate chip may start observing the
    /// animation manager, because a `TimelineView(.animation)` tick in the row body re-renders every
    /// visible row rather than one glyph. `CadenceTodayUnificationTests` pins the environment count;
    /// this pins that the extraction the property depends on is still there to hold it.
    @Test func theRowsAnimatedPartsAreStillExtractedIntoTheirOwnSubViews() throws {
        let code = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))

        #expect(code.contains("private struct TaskCompletionButton: View"))
        #expect(code.contains("private struct TaskRowBackground: View"))

        // **Per-declaration, not per-file (T-161).** The whole-file count of two was the whole
        // assertion, and two observations in one sub-view with none in the other satisfies it — the
        // background would then repaint from a plain `isCompleting` flag it no longer holds, or the
        // glyph would, and the file would still read `2`. So each extracted sub-view is asked for
        // its own, and the two views that must never hold one are asked for zero here as well as in
        // `CadenceTodayUnificationTests`.
        let observers = [
            "struct TaskCompletionButton: View": 1,
            "struct TaskRowBackground: View": 1,
            "struct MacTaskRow: View": 0,
            "struct MacTaskRowEstimateChip: View": 0
        ]
        for (declaration, expected) in observers {
            let body = try cadenceFunctionBody(declaration, in: code)
            let actual = body.components(separatedBy: "@Environment(TaskCompletionAnimationManager.self)").count - 1
            #expect(
                actual == expected,
                "\(declaration) observes the completion animation manager \(actual) times, expected \(expected)"
            )
        }

        // And nowhere else in the file: a fifth reader would be a third view re-rendering on every
        // display-link tick, and every count above would still hold.
        #expect(code.components(separatedBy: "@Environment(TaskCompletionAnimationManager.self)").count - 1 == 2)
    }

    // MARK: - The scan itself

    /// The absence assertions above are only worth anything if the scan actually reads files, and a
    /// scan that silently returns nothing passes every one of them. This is the test that stops them
    /// going vacuous — the exact failure mode that let a `/tmp` against `/private/tmp` path mismatch
    /// look like real regressions while the scan was reading nothing at all.
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/macOS/Views/KanbanCardView.swift"))
        #expect(files.contains("Cadence/iOS/iOSBoardCards.swift"))
        #expect(files.contains("Cadence/iOS/iOSCalendarBundleDetailSheet.swift"))
        #expect(files.contains("Cadence/Shared/CadenceBoardCardMetadata.swift"))
        #expect(files.contains("Cadence/Shared/CadenceBundleTaskRowSupport.swift"))
        #expect(files.contains("Cadence/Shared/Components/CadenceTaskDetailLineLabel.swift"))
        // T-173 / T-174 reach these four; a scan that cannot see them makes every absence
        // assertion above vacuous.
        #expect(files.contains("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/CalendarBoardRailSupportViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSCalendarBoardView.swift"))
        #expect(files.contains("Cadence/Shared/Components/CadenceTagChip.swift"))
        // T-175 reaches these three; without them its zero expectations are vacuous.
        #expect(files.contains("Cadence/macOS/Views/TasksPanelComponents.swift"))
        #expect(files.contains("Cadence/iOS/iOSTaskViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSInboxRemindersSection.swift"))

        // And it must be reading *code*, not an empty string: a positive assertion over the same
        // reader the absence checks use.
        let card = try strippingComments(sourceFile("Cadence/iOS/iOSBoardCards.swift"))
        #expect(card.contains("struct iOSBoardTaskCard"))

        let macRow = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        #expect(macRow.contains("struct MacTaskRow: View"))
    }

    /// T-136's method: strip the platform prefix from every top-level type in `Cadence/iOS/` and
    /// intersect with `Cadence/macOS/`. Neither job unified here may re-enter that set.
    @Test func neitherUnifiedJobIsForkedAcrossPlatformsAgain() throws {
        let iosTypes = try topLevelTypeNames(in: "Cadence/iOS")
        let macTypes = try topLevelTypeNames(in: "Cadence/macOS")
        let intersection = Set(iosTypes.compactMap(stripPlatformPrefix)).intersection(macTypes)

        #expect(!intersection.contains("TaskDetailLineLabel"))
        #expect(!intersection.contains("BoardCardMetadata"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** `CadenceSharedBoardChromeTests` documents why: a mutation run
/// caught a version of that file asserting only that each file mentioned the shared component
/// somewhere, and reverting *one* of four call sites left it green.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
///
/// `expectCallSites` appends `(` and so only sees function and initializer calls. A *parameter* is
/// passed, not called, and a zero expectation is the whole point for the rails: this is the spelling
/// that can assert both "these two files pass the knob twice each" and "these three never do".
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails if `name` appears anywhere in `Cadence/` as live code rather than inside a comment.
///
/// Comments are exempt deliberately — the tombstone left where the macOS-only label used to be
/// declared says what was there and why, and a test that forbade the *word* would force the next
/// agent to delete the explanation along with the code.
private func expectNoLiveMention(
    of name: String,
    excludingPrefixes prefixes: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let negativeLookbehind = prefixes.isEmpty ? "" : "(?<!" + prefixes.joined(separator: ")(?<!") + ")"
    let pattern = "(?<![A-Za-z0-9_])\(negativeLookbehind)\(name)(?![A-Za-z0-9_])"

    for path in try swiftFiles(under: "Cadence") {
        let code = try strippingComments(sourceFile(path))
        #expect(
            code.range(of: pattern, options: .regularExpression) == nil,
            "\(path) still refers to the retired type \(name)",
            sourceLocation: sourceLocation
        )
    }
}

private func topLevelTypeNames(in directory: String) throws -> Set<String> {
    var names: Set<String> = []
    let pattern = "^(?:public |private |internal |fileprivate |final |nonisolated )*(?:struct|class|enum|actor|protocol)\\s+([A-Za-z_][A-Za-z0-9_]*)"

    for path in try swiftFiles(under: directory) {
        for line in try sourceFile(path).split(separator: "\n", omittingEmptySubsequences: false) {
            guard let first = line.first, first != " ", first != "\t" else { continue }
            guard let range = line.range(of: pattern, options: .regularExpression) else { continue }
            if let name = line[range].split(separator: " ").last {
                names.insert(String(name))
            }
        }
    }
    return names
}

private func stripPlatformPrefix(_ name: String) -> String? {
    for prefix in ["iOSCompact", "iOSRegular", "iPadMacStyle", "iOS", "iPad", "iPhone"] where name.hasPrefix(prefix) && name.count > prefix.count {
        return String(name.dropFirst(prefix.count))
    }
    return nil
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
