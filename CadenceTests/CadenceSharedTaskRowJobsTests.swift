import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-172: tasks are rendered by ~13 views doing ~5 jobs. Two of those jobs, unified.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning
/// `CadenceTaskRowMetrics.titleLineLimit == 2` proves the shared figure is right; it proves
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

    /// **[[T-11892]].** A task in a blank-named list is still in that list, so its chip names the
    /// list the way the Mac task row, the sidebar and the pickers do -- "Untitled Area" /
    /// "Untitled Project" -- and says "Inbox" only for a task in no list. The old rule read the raw
    /// name and treated empty as Inbox, and a whitespace-only name drew a blank chip.
    @Test func aBlankNamedListIsNamedLikeEveryOtherSurfaceNamesIt() {
        func chipText(area: String? = nil, project: String? = nil) -> String {
            let task = task()
            task.area = area.map { Area(name: $0) }
            task.project = project.map { Project(name: $0) }
            return CadenceBoardCardMetadata.listChip(for: task).text
        }

        #expect(chipText(area: "") == CadenceTitleNormalization.defaultAreaName)
        #expect(chipText(area: "   \n") == CadenceTitleNormalization.defaultAreaName)
        #expect(chipText(project: "") == CadenceTitleNormalization.defaultProjectName)
        #expect(chipText(project: " \t ") == CadenceTitleNormalization.defaultProjectName)
        #expect(chipText(area: "  Work ") == "Work")
        #expect(chipText(project: "Launch") == "Launch")
        // Project before area, the precedence `AppTask.containerName` and the filing rule use
        // ([[T-15553]]); a blank-named project is still named "Untitled Project".
        #expect(chipText(area: "", project: "Launch") == "Launch")
        #expect(chipText(area: "Work", project: "") == CadenceTitleNormalization.defaultProjectName)
        #expect(chipText() == CadenceBoardCardMetadata.inboxLabel)
    }

    /// The iOS task row's list chip is not a board card, but it is the surface the blank-name
    /// defect was seen on ([[T-11892]]'s sighting), and `Cadence/iOS/` is never compiled on this
    /// host -- so its title is held by source: it reads the one rule above, and no longer the raw
    /// `containerName`.
    @Test func theIOSTaskRowListChipTitlesThroughTheSameRule() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("struct iOSTaskRowContainerChip", in: source),
            "iOSTaskRowContainerChip is gone"
        )
        #expect(body.contains("iOSTaskAttributeChip("), "non-vacuity: the chip's own body")
        #expect(body.contains("title: CadenceBoardCardMetadata.listTitle(for: task)"))
        #expect(!body.contains("containerName"), "the iOS row chip reads the raw list name again")
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

    // MARK: - [[T-12642]]: one do-date emphasis on both task rows

    /// **The rule, by value.** A row's do-date label is the board card's: neutral grey, amber on a
    /// today do date, red once past, and quiet on finished work; the sun is amber whatever the date.
    @Test func theRowDoDateEmphasisIsTheBoardCardsEmphasis() {
        let today = "2026-08-20"
        #expect(CadenceTaskRowDoDateEmphasis.emphasis(for: task(doDate: "2026-08-19"), todayKey: today) == .urgent)
        #expect(CadenceTaskRowDoDateEmphasis.emphasis(for: task(doDate: today), todayKey: today) == .attention)
        #expect(CadenceTaskRowDoDateEmphasis.emphasis(for: task(doDate: "2026-08-21"), todayKey: today) == .neutral)
        #expect(CadenceTaskRowDoDateEmphasis.emphasis(for: task(doDate: "2026-08-19", isDone: true), todayKey: today) == .neutral)

        #expect(CadenceTaskRowDoDateEmphasis.glyphColor == Theme.amber)
        #expect(CadenceTaskRowDoDateEmphasis.labelColor(for: .neutral) == Theme.dim)
        #expect(CadenceTaskRowDoDateEmphasis.labelColor(for: .attention) == Theme.amber)
        #expect(CadenceTaskRowDoDateEmphasis.labelColor(for: .urgent) == Theme.red)

        // And the card's do chip says the same thing, from the same switch.
        let cardChip = CadenceBoardCardMetadata.doDateChip(for: task(doDate: today), todayKey: today)
        #expect(cardChip?.identityColor == CadenceTaskRowDoDateEmphasis.glyphColor)
        #expect(cardChip?.labelColor == CadenceTaskRowDoDateEmphasis.labelColor(for: .attention))
    }

    /// **The call sites.** Both rows ask the shared emphasis for the do date's label and its sun,
    /// and neither keeps the private over-do / do-today pair it used to decide by. iOS's D-02 tint
    /// (`isOverdo ? Theme.red : Theme.dim`, a grey today) is the drift this closed.
    @Test func bothTaskRowsReadTheSharedDoDateEmphasis() throws {
        try expectCallSites(
            of: "CadenceTaskRowDoDateEmphasis.emphasis",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1,
            ]
        )
        try expectCallSites(
            of: "CadenceTaskRowDoDateEmphasis.labelColor",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1,
            ]
        )
        try expectOccurrences(
            of: "CadenceTaskRowDoDateEmphasis.glyphColor",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1,
            ]
        )

        let iOSRow = try strippingComments(sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        #expect(iOSRow.contains("field: .doDate,"), "non-vacuity: wrong file read")
        #expect(!iOSRow.contains("isOverdo"), "the iOS row decides its do-date colour itself again")
        let macRow = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        #expect(macRow.contains("private var doDatePill"), "non-vacuity: wrong file read")
        #expect(!macRow.contains("isDoToday"), "the Mac row decides its do-date colour itself again")
        #expect(!macRow.contains("Theme.amber"), "the Mac row spells the do date's amber itself again")
    }

    // MARK: - [[T-12640]]: a cancelled row says so on both platforms

    /// `MacTaskRow` drew a grey "Canceled" capsule and `iOSTaskRow` drew nothing, so on iPhone a
    /// cancelled task in a Completed section read as a finished one. One view, both rows.
    @Test func bothTaskRowsDrawTheSharedCancelledChip() throws {
        #expect(CadenceTaskCancelledChip.label == TaskStatus.cancelled.label)
        #expect(CadenceTaskCancelledChip.label == "Canceled")

        try expectCallSites(
            of: "CadenceTaskCancelledChip",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1,
            ]
        )
        // Behind the cancelled guard on both, and at each row's own chip metrics.
        let iOSRow = try strippingComments(sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        let iOSChip = try #require(iOSRow.range(of: "CadenceTaskCancelledChip("))
        // The stripper blanks comments to spaces, so the guard is read with whitespace dropped: the
        // chip is the first statement inside `if task.isCancelled {`.
        func guardedByCancelled(_ lead: Substring) -> Bool {
            String(lead.suffix(2000)).filter { !$0.isWhitespace }.hasSuffix("iftask.isCancelled{")
        }
        #expect(guardedByCancelled(iOSRow[..<iOSChip.lowerBound]))
        let iOSArgs = String(iOSRow[iOSChip.lowerBound...].prefix(400))
        #expect(iOSArgs.contains("fontSize: iOSTaskAttributeChipSize.row.fontSize,"))
        #expect(iOSArgs.contains("horizontalPadding: CadenceTaskChipPadding.iOSRowHorizontal,"))
        #expect(iOSArgs.contains("minHeight: iOSTaskAttributeChipSize.row.height(at: dynamicTypeSize, scaling: scaling)"))

        let macRow = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        let macChip = try #require(macRow.range(of: "CadenceTaskCancelledChip(metrics: .desktop)"))
        #expect(guardedByCancelled(macRow[..<macChip.lowerBound]))

        // Neither row spells the word or the capsule itself.
        for path in ["Cadence/macOS/Views/TasksPanelComponents.swift", "Cadence/iOS/iOSTaskViews.swift"] {
            #expect(!(try strippingComments(sourceFile(path))).contains(#""Canceled""#), "\(path) spells the word itself")
        }
    }

    // MARK: - [[T-16461]]: a finished row is dimmed the same on both platforms

    /// `MacTaskRow` dimmed every settled row to 0.5; iOS's folded Completed section and a list's
    /// Completed tab each spelled 0.62, so the same finished task read brighter on an iPhone's
    /// logbook than on the Mac's. One figure, read by all three sites, and no site keeps a literal.
    @Test func everyLogbookRowIsDimmedByTheOneSettledRowFigure() throws {
        #expect(CadenceTaskRowMetrics.settledRowOpacity == 0.5)
        #expect(CadenceTaskRowMetrics.settledRowOpacity > 0 && CadenceTaskRowMetrics.settledRowOpacity < 1)

        // [[T-16463]]: each platform's ROW reads the figure, once, keyed on its own settled state;
        // no container dims on top of it. The two iOS logbook containers used to be the readers,
        // which left a done task drawn by `iOSTaskRow` anywhere else -- the iPad day inspector,
        // the iPhone month agenda -- at full brightness.
        try expectOccurrences(
            of: "CadenceTaskRowMetrics.settledRowOpacity",
            at: [
                // `MacTaskRow`, behind its own settled test.
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                // `iOSTaskRow`, for every iOS surface that draws one.
                "Cadence/iOS/iOSTaskViews.swift": 1,
                // `iOSCompletedTasksSection` and `iOSListCompletedPanel`: dimmed by the row now.
                "Cadence/iOS/iOSTaskGroupSection.swift": 0,
                "Cadence/iOS/iOSListSupportViews.swift": 0,
            ]
        )
        let macRow = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        #expect(macRow.contains(".opacity(task.isDone || task.isCancelled ? CadenceTaskRowMetrics.settledRowOpacity : 1.0)"))
        let iOSRow = try strippingComments(sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        #expect(iOSRow.contains(".opacity(isSettled ? CadenceTaskRowMetrics.settledRowOpacity : 1)"))
        // `isSettled` is the shared done-or-cancelled answer, the Mac row's `isDone || isCancelled`.
        #expect(iOSRow.contains("CadenceTaskCompletionState.resolve(task: task).isSettled"))
        // `iOSTaskListRow` no longer takes an opacity, so no host can dim a row a second time.
        #expect(!iOSRow.contains("var opacity: Double"))
        for path in [
            "Cadence/iOS/iOSTaskGroupSection.swift",
            "Cadence/iOS/iOSListSupportViews.swift",
        ] {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("opacity: CadenceTaskRowMetrics"), "\(path) dims settled rows on top of the row")
        }
        for path in [
            "Cadence/macOS/Views/TasksPanelComponents.swift",
            "Cadence/iOS/iOSTaskViews.swift",
            "Cadence/iOS/iOSTaskGroupSection.swift",
            "Cadence/iOS/iOSListSupportViews.swift",
        ] {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains(".opacity(0.62)"), "\(path) dims finished rows by its own figure again")
            #expect(!code.contains("opacity: 0.62"), "\(path) dims finished rows by its own figure again")
            #expect(!code.contains("isCancelled ? 0.5"), "\(path) dims finished rows by its own figure again")
        }
    }

    /// [[T-16463]]: why the dim had to move into `iOSTaskRow`. Every calendar surface that draws
    /// one admits a DONE task (only cancelled leaves): the iPad day inspector's Timed, Do Date and
    /// Due sections and the iPhone month agenda. Were any of them to drop done tasks, a container
    /// dim would have been enough -- so this pins the admissions the row-level dim answers.
    @Test func everyCalendarSurfaceDrawingAnIOSTaskRowAdmitsADoneTask() {
        let day = "2026-11-11"
        let timed = task(doDate: day, isDone: true)
        timed.scheduledStartMin = 9 * 60
        let doDated = task(doDate: day, isDone: true)
        let dueOnly = task(dueDate: day, isDone: true)
        let all = [timed, doDated, dueOnly]

        #expect(CadenceScheduleSupport.scheduledTasks(on: day, from: all, includeCompleted: true).map(\.id) == [timed.id])
        #expect(CadenceScheduleSupport.items(on: day, in: CadenceScheduleSupport.unscheduledTasksByDate(all)).map(\.id) == [doDated.id])
        #expect(CadenceScheduleSupport.dueOnlyTasks(on: day, from: all).map(\.id) == [dueOnly.id])
        #expect(Set(CadenceScheduleSupport.items(on: day, in: CadenceScheduleSupport.monthTasksByDate(all)).map(\.id)) == Set(all.map(\.id)))
        #expect(all.allSatisfy { CadenceTaskCompletionState.resolve(task: $0).isSettled }, "non-vacuity: every fixture is settled")

        // And those surfaces draw it through `iOSTaskRow`, with no dim of their own.
        for path in ["Cadence/iOS/iOSCalendarInspectorView.swift", "Cadence/iOS/iOSCalendarMonthAgendaViews.swift"] {
            let code = (try? strippingComments(sourceFile(path))) ?? ""
            #expect(code.contains("iOSTaskRow(task: task"), "\(path) no longer draws an iOSTaskRow")
            #expect(!code.contains("settledRowOpacity"), "\(path) dims settled rows on top of the row")
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

    /// **T-1289: the other two iOS panes that name a day, asked one site at a time.**
    ///
    /// The calendar's day inspector and its month agenda drew the sun pill on rows already gathered
    /// under the day the pane names. Four call sites, and the answer is **not** the same at all
    /// four — which is why this pins counts per file rather than sweeping for the argument:
    ///
    /// - The inspector's **Timed** and **Do Date** sections admit on `scheduledDate == dayKey`
    ///   (`timedTasks`' own filter, and `CadenceScheduleSupport.unscheduledTasksByDate`'s bucket),
    ///   so the pill there can only restate the pane. Two sites, suppressed.
    /// - The inspector's **Due** section is the one that must keep it.
    ///   `CadenceScheduleSupport.dueOnlyTasks(on:from:)` admits on
    ///   `dueDate == dateKey && scheduledDate != dateKey`, so a row here is present for its
    ///   deadline and its do date, if any, is a *different* day. The equality could never fire, and
    ///   the pill it would aim at carries the fact the section does not state.
    /// - The month agenda is a scrolling list, but each section carries the board's own day header
    ///   above its rows, so it is the day-column case. `monthTasksByDate` files a task under
    ///   `scheduledDate` first and only falls back to `dueDate` when there is none, so a listed row
    ///   either is do-dated that section's day or has no do date to suppress.
    @Test func theCalendarDayPanesStateTheirOwnDayAndTheDueSectionStillDoesNot() throws {
        // Three `iOSTaskRow(` call sites in the inspector, and exactly two of them suppress.
        let inspector = try strippingComments(sourceFile("Cadence/iOS/iOSCalendarInspectorView.swift"))
        #expect(inspector.contains("struct iOSCalendarDayInspector: View"), "non-vacuity: wrong file read")
        #expect(inspector.components(separatedBy: "iOSTaskRow(").count - 1 == 3)
        #expect(inspector.contains("iOSTaskRow(task: task, todayKey: todayKey)"),
                "the Due section stopped drawing the do-date pill for a day it never named")

        try expectOccurrences(
            of: "dayAlreadyStatedBySurface: dayKey",
            at: [
                "Cadence/iOS/iOSCalendarInspectorView.swift": 2,
                "Cadence/iOS/iOSCalendarMonthAgendaViews.swift": 1,
            ]
        )

        // And the key is the pane's, never the clock's. A day inspector parked on last Tuesday
        // states last Tuesday; `todayKey()` here would suppress the pill on the wrong rows.
        // [[T-14341]]: the pane now holds the page's observed `todayKey`, which every row takes
        // for its lateness -- but never as the day it suppresses its pill against.
        try expectOccurrences(
            of: "dayAlreadyStatedBySurface: todayKey",
            at: [
                "Cadence/iOS/iOSCalendarInspectorView.swift": 0,
            ]
        )
        #expect(!inspector.contains("todayKey()"))
        #expect(inspector.contains("DateFormatters.dateKey(from: date)"))

        let agenda = try strippingComments(sourceFile("Cadence/iOS/iOSCalendarMonthAgendaViews.swift"))
        // The agenda does hold the page's observed `todayKey` since [[T-5010]], for its today mark
        // only. It must never be the key a row suppresses its pill against, and never the clock's.
        #expect(!agenda.contains("dayAlreadyStatedBySurface: todayKey"))
        #expect(!agenda.contains("todayKey()"))
        #expect(agenda.contains("agendaRow(item, dayKey: section.key)"),
                "the month agenda's row no longer reads the day from the section that heads it")
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

    /// [[T-13841]]: a cancelled task is finished too — it is filed under Completed by
    /// `isFinishedTask`, struck through, and wears the "Canceled" chip — so it lists no subtasks and
    /// counts none hidden. The gate read `isDone` alone, and every row and board card listed a
    /// cancelled task's open subtasks with tickable circles under it.
    @Test func aCancelledTaskListsNoSubtasksAndHidesNone() {
        let cancelled = task(unfinished: 9)
        cancelled.status = .cancelled

        #expect(CadenceTaskPresentationSupport.listedSubtasks(for: cancelled).isEmpty)
        #expect(CadenceTaskPresentationSupport.unlistedSubtaskCount(for: cancelled) == nil)
        // Non-vacuity: the subtasks are there and open; only the gate hides them.
        #expect(CadenceTaskPresentationSupport.allUnfinishedSubtasks(for: cancelled).count == 9)
        cancelled.status = .todo
        #expect(!CadenceTaskPresentationSupport.listedSubtasks(for: cancelled).isEmpty)
    }

    // MARK: - T-173: the call sites

    /// **The T-161 test for T-173.** Both cards must list tags and subtasks through the shared
    /// figures. An exact count per file is what catches one card quietly going back to its own
    /// answer — which is the state this ticket existed to close, in the direction of iOS having
    /// neither and macOS having an uncapped one.
    @Test func bothBoardCardsListTagsAndSubtasksFromTheSharedFigures() throws {
        // **[[T-8181]] moved the tag half up a level rather than away.** Neither card draws a
        // `CompactTagStrip` any more: a tag is a `#deep-work` token in the Ledger card's one text
        // run, and the run is built by `CadenceLedgerTagTokens` — which is shared, so the cap is
        // now spelled ONCE for both boards instead of once per card. That is the same claim this
        // test has always made, made somewhere stronger, which is why the expectation moves
        // instead of relaxing.
        try expectCallSites(
            of: "CompactTagStrip",
            at: [
                "Cadence/macOS/Views/KanbanCardMetaSupportViews.swift": 0,
                "Cadence/iOS/iOSBoardCards.swift": 0,
            ]
        )
        try expectOccurrences(
            of: "CadenceTaskPresentationSupport.rowTagLimit",
            at: [
                "Cadence/Shared/CadenceBoardLedgerCard.swift": 1,
                "Cadence/macOS/Views/KanbanCardMetaSupportViews.swift": 0,
                "Cadence/iOS/iOSBoardCards.swift": 0,
            ]
        )
        // And both cards reach it, so a card cannot quietly stop listing tags at all.
        try expectCallSites(
            of: "CadenceLedgerTagTokens.names",
            at: [
                "Cadence/macOS/Views/KanbanCardView.swift": 1,
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

    // [[T-3213]] deleted the bundle member row support file and the six tests that pinned its
    // figures and its second line: no row in the app drew a bundle member any more.

    // MARK: - Bundle member row: the call sites

    /// **The T-161 test for the bundle row.** It was three rows, then two, then one, and is now
    /// none.
    ///
    /// [[T-3170]] deleted the Focus panel's row with Block Focus, then
    /// `iOSCalendarBundleDetailSheet.swift` with the whole iOS Block surface, and its trio pass
    /// deleted the last two Mac files that drew a block member: `TimelineBundleBlockSupportViews`
    /// (the only caller of the bundle row's detail-parts helper, since deleted by [[T-3213]]) and
    /// `TaskBundlePickerSupportViews`. What survives is the shared label the iOS row forced out of
    /// `#if os(macOS)`, read by the two focus rows -- so this now pins those two call sites.
    @Test func theSurvivingDetailLineRowsReadTheSharedLabel() throws {
        try expectCallSites(
            of: "CadenceTaskDetailLineLabel",
            at: [
                // The focus rows, which already used it under its old name.
                "Cadence/macOS/Views/FocusSidebarSupportViews.swift": 1,
                "Cadence/macOS/Views/FocusPickerSupportViews.swift": 1,
            ]
        )
    }

    /// The macOS-guarded spelling may not come back. `excludingPrefixes` lets the shared name
    /// through and nothing else, so re-declaring `TaskDetailLineLabel` beside it fails here.
    @Test func theMacOSOnlyDetailLineSpellingIsGone() throws {
        try expectNoLiveMention(of: "TaskDetailLineLabel", excludingPrefixes: ["Cadence"])
    }

    // [[T-3170]] retired `theFocusPanelsSelectionControlDoesNotWearTheCompletionGlyph`. It pinned
    // that the Focus panel's time-log tick was a square rather than the app's completion circle;
    // the panel it read, FocusBundleTaskSupportViews.swift, went with Block Focus.

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

        // The three notes/subtask-tier figures are stated at compact's answers — a narrow pane's.
        // Nothing read them on macOS until [[T-1467]] gave `MacTaskRow` its notes excerpt and
        // subtask rows; the call-site test above now pins that it reads them exactly once each.
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
            // The row, and only the row. It was two: the estimate chip was its own `View` struct,
            // so its popover `@State` could not invalidate the row, and it read the tier directly
            // for the same reason. [[T-3196]] removed that chip, so the row is the one reader.
            at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 1]
        )

        for (figure, count) in [
            // Three since [[T-1467]]: the row's leading inset, plus the trailing inset the notes
            // excerpt and the subtask list each keep off the row's edge.
            ("metrics.horizontalPadding", 3),
            ("metrics.verticalPadding", 1),
            ("metrics.contentSpacing", 3),
            // Seven until [[T-3170]] took the block badge off the row with the Block feature, and
            // six until [[T-3196]] took the estimate chip off it. Six again since [[T-5015]] (b):
            // the repeat picker keeps itself off the chip before it, as every chip here does.
            ("metrics.badgeSpacing", 6),
            ("metrics.titleFontSize", 1),
            // Four, and the Cancelled chip is one of them: it joined its siblings on this row
            // (T-597) having set its own `size: 10` and `6/3` padding while every other chip beside
            // it read this tier — which is the shape of drift `.desktop` exists to prevent, one
            // chip late. The do-date pill spells the figure twice, once on the hidden `Text`
            // reserving width. It was six until [[T-3170]] removed the block badge and five until
            // [[T-3196]] removed the estimate chip; both are chips that went, not readers that
            // stopped reading. Six since [[T-1467]]: the notes excerpt and the subtask list's
            // "+N more" line both read it — new readers, not copies of a chip's figure. Seven
            // since [[T-5015]] (b): the repeat picker's label, a chip arriving rather than one
            // leaving, and it reads the tier instead of bringing the iOS chip's own figure. Six
            // since [[T-12640]]: the Cancelled chip is the shared `CadenceTaskCancelledChip`, whose
            // `.desktop` metrics read `CadenceTaskRowMetrics.desktop.secondaryFontSize` there.
            ("metrics.secondaryFontSize", 6),
            // [[T-1467]]: the notes/subtask tier. One read each, so a second inline spelling of
            // any of them (or the row dropping back to abstaining) fails here.
            ("metrics.summarySpacing", 1),
            ("metrics.secondaryLineLimit", 1),
            ("metrics.notesPreviewLimit", 1)
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
        // `summarySpacing`, `secondaryLineLimit` and `notesPreviewLimit` left this list with
        // [[T-1467]]; they are pinned positively in `theMacRowDrawsItselfFromTheSharedFiguresRatherThanItsOwn`.
        for figure in ["titleLineLimit", "completionGlyphSize", "completionCircleDiameter"] {
            try expectOccurrences(of: figure, at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 0])
        }

        try expectOccurrences(
            of: "CadenceTaskRowMetrics.titleLineLimit",
            at: ["Cadence/iOS/iOSTaskViews.swift": 1, "Cadence/iOS/iOSInboxRemindersSection.swift": 1]
        )
        try expectOccurrences(
            of: "metrics.completionGlyphSize",
            at: ["Cadence/iOS/iOSTaskViews.swift": 1, "Cadence/iOS/iOSInboxRemindersSection.swift": 1]
        )
        try expectOccurrences(
            of: "CadenceTypeScale.height(metrics.completionGlyphSize, holding: .rowTitle, textBase: CadenceTaskRowMetrics.completionCircleDiameter, at: dynamicTypeSize, scaling: scaling)",
            at: ["Cadence/iOS/iOSTaskViews.swift": 1, "Cadence/iOS/iOSInboxRemindersSection.swift": 1]
        )
        for (path, frame) in [("Cadence/iOS/iOSTaskViews.swift", "completionFrame"),
                              ("Cadence/iOS/iOSInboxRemindersSection.swift", "frame")] {
            try expectOccurrences(of: ".frame(width: \(frame), height: \(frame))", at: [path: 1])
            try expectOccurrences(of: ".iOSExpandedHitArea(max(0, (44 - \(frame)) / 2))", at: [path: 1])
        }
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
    /// property and lost five literals; it may not start observing the animation manager, because a
    /// `TimelineView(.animation)` tick in the row body re-renders every visible row rather than one
    /// glyph. `CadenceTodayUnificationTests` pins the environment count; this pins that the
    /// extraction the property depends on is still there to hold it.
    ///
    /// **The estimate chip was asked for its own zero here until [[T-3196]] removed it.** It is not
    /// replaced in the roster below: the file-wide count at the end of this test is what refuses a
    /// third observer, whatever it is called, so dropping the row carries no coverage with it.
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
            // [[T-8412]]: the background lays the shared `TaskCompletionPendingSweep`, which observes
            // the manager inside its own body -- still off the row, one level further down.
            "struct TaskRowBackground: View": 0,
            "struct MacTaskRow: View": 0
        ]
        for (declaration, expected) in observers {
            let body = try cadenceFunctionBody(declaration, in: code)
            let actual = body.components(separatedBy: "@Environment(TaskCompletionAnimationManager.self)").count - 1
            #expect(
                actual == expected,
                "\(declaration) observes the completion animation manager \(actual) times, expected \(expected)"
            )
        }

        let background = try cadenceFunctionBody("struct TaskRowBackground: View", in: code)
        #expect(background.contains("TaskCompletionPendingSweep(task: task"), "the row's sweep is no longer extracted into the shared host")

        // And nowhere else in the file: a second reader would be a second view re-rendering on
        // every display-link tick, and every count above would still hold.
        #expect(code.components(separatedBy: "@Environment(TaskCompletionAnimationManager.self)").count - 1 == 1)
    }

    // MARK: - The scan itself

    /// The absence assertions above are only worth anything if the scan actually reads files, and a
    /// scan that silently returns nothing passes every one of them. This is the test that stops them
    /// going vacuous — the exact failure mode that let a `/tmp` against `/private/tmp` path mismatch
    /// look like real regressions while the scan was reading nothing at all.
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInSharedTaskRowJobs() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/macOS/Views/KanbanCardView.swift"))
        #expect(files.contains("Cadence/iOS/iOSBoardCards.swift"))
        #expect(files.contains("Cadence/iOS/iOSCalendarInspectorView.swift"))
        #expect(files.contains("Cadence/Shared/CadenceBoardCardMetadata.swift"))
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

    // MARK: - T-304: two dates, one day, one chip

    /// The reported defect, stated as the value it comes from. A task do-dated *and* due on the
    /// same day drew "17 days ago" beside "17 days ago", because the sun and the flag were each
    /// drawn from their own `isEmpty` check with nothing comparing them.
    ///
    /// The flag survives: a deadline is the harder commitment, and it is the chip that already goes
    /// red on both platforms once the day is past.
    @Test func twoDatesOnOneDayAreOneChipAndItIsTheFlag() {
        let plan = CadenceTaskPresentationSupport.rowDatePlan(
            scheduledDate: "2026-08-09",
            dueDate: "2026-08-09"
        )

        #expect(plan == .oneSharedDay)
        #expect(plan.drawsDueDateChip)
        #expect(plan.drawsDoDateChip == false)
        #expect(plan.statesBothFieldsInOneChip)
    }

    /// The other half, and the one a too-eager merge breaks: the fields are genuinely different, so
    /// two days are two facts and each keeps its own chip and its own picker.
    @Test func twoDatesOnDifferentDaysStayTwoChips() {
        let plan = CadenceTaskPresentationSupport.rowDatePlan(
            scheduledDate: "2026-08-09",
            dueDate: "2026-08-10"
        )

        #expect(plan == .separateDays)
        #expect(plan.drawsDoDateChip)
        #expect(plan.drawsDueDateChip)
        #expect(plan.statesBothFieldsInOneChip == false)

        // A day apart is the closest two dates can be without being one, and yesterday/tomorrow
        // around the same do date must not collapse either.
        let earlierDeadline = CadenceTaskPresentationSupport.rowDatePlan(
            scheduledDate: "2026-08-10",
            dueDate: "2026-08-09"
        )
        #expect(earlierDeadline == .separateDays)
        #expect(earlierDeadline.drawsDoDateChip)
    }

    /// One field set draws one chip and merges nothing: an absent date is not a date that agrees.
    @Test func oneFieldSetDrawsThatFieldsChipAlone() {
        let doOnly = CadenceTaskPresentationSupport.rowDatePlan(scheduledDate: "2026-08-09", dueDate: "")
        #expect(doOnly == .doDateOnly)
        #expect(doOnly.drawsDoDateChip)
        #expect(doOnly.drawsDueDateChip == false)
        #expect(doOnly.statesBothFieldsInOneChip == false)

        let dueOnly = CadenceTaskPresentationSupport.rowDatePlan(scheduledDate: "", dueDate: "2026-08-09")
        #expect(dueOnly == .dueDateOnly)
        #expect(dueOnly.drawsDueDateChip)
        #expect(dueOnly.drawsDoDateChip == false)
        #expect(dueOnly.statesBothFieldsInOneChip == false)

        let neither = CadenceTaskPresentationSupport.rowDatePlan(scheduledDate: "", dueDate: "")
        #expect(neither == .none)
        #expect(neither.drawsDoDateChip == false)
        #expect(neither.drawsDueDateChip == false)
        #expect(neither.statesBothFieldsInOneChip == false)
    }

    /// `.oneSharedDay` is the only case that speaks for two fields, and every other case draws at
    /// least one chip for every field it has. Stated over `allCases` so a sixth case cannot be
    /// added without answering both questions.
    @Test func exactlyOneCaseSpeaksForBothFields() {
        #expect(CadenceTaskRowDatePlan.allCases.filter(\.statesBothFieldsInOneChip) == [.oneSharedDay])
        #expect(CadenceTaskRowDatePlan.allCases.filter(\.drawsDoDateChip) == [.doDateOnly, .separateDays])
        #expect(CadenceTaskRowDatePlan.allCases.filter(\.drawsDueDateChip) == [.dueDateOnly, .separateDays, .oneSharedDay])
    }

    /// The task-shaped reader both rows actually call, over the reported row: overdue, do-dated and
    /// due on one past day. One chip, and it is the flag.
    @Test func theRowsReadTheirPlanFromTheTasksTwoFields() {
        let reported = task(doDate: "2026-08-09", dueDate: "2026-08-09")
        #expect(CadenceTaskPresentationSupport.rowDatePlan(for: reported) == .oneSharedDay)

        let split = task(doDate: "2026-08-09", dueDate: "2026-08-26")
        #expect(CadenceTaskPresentationSupport.rowDatePlan(for: split) == .separateDays)

        // Finishing the work does not change what the row *states* about its two dates — only how
        // loudly. The urgency tints are a separate question, asked of `CadenceDueUrgency` and
        // `KanbanCardComputedSupport`.
        let done = task(doDate: "2026-08-09", dueDate: "2026-08-09", isDone: true)
        #expect(CadenceTaskPresentationSupport.rowDatePlan(for: done) == .oneSharedDay)
    }

    /// Compared as **days**, not as strings. `DateFormatter` is lenient enough to have stored
    /// `2026-8-20` (T-299), and two keys that print the same date through `relativeDate(from:)` are
    /// exactly the pair a row would show twice. The first two expectations are the measurement the
    /// third depends on, so a toolchain that stopped parsing the loose key would say so here rather
    /// than silently making this test vacuous.
    @Test func aDaySpelledTwoWaysIsStillOneDay() {
        #expect(DateFormatters.date(from: "2026-8-20") != nil)
        #expect(DateFormatters.relativeDate(from: "2026-8-20") == DateFormatters.relativeDate(from: "2026-08-20"))

        #expect(
            CadenceTaskPresentationSupport.rowDatePlan(scheduledDate: "2026-8-20", dueDate: "2026-08-20")
                == .oneSharedDay
        )
        #expect(CadenceTaskPresentationSupport.namesTheSameDay("2026-8-20", "2026-08-20"))
        #expect(CadenceTaskPresentationSupport.namesTheSameDay("2026-08-20", "2026-08-21") == false)
    }

    /// **The call-site half.** The value above is worth nothing if a row goes back to counting its
    /// own chips — T-161 is the standing example of a fix reverted with the suite green. Exact
    /// counts, both platforms, one guard per chip per row.
    @Test func bothRowsDrawTheirDateChipsFromTheSharedPlan() throws {
        try expectCallSites(
            of: "CadenceTaskPresentationSupport.rowDatePlan",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1
            ]
        )

        for guardText in ["datePlan.drawsDoDateChip", "datePlan.drawsDueDateChip"] {
            try expectOccurrences(
                of: guardText,
                at: [
                    "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                    "Cadence/iOS/iOSTaskViews.swift": 1
                ]
            )
        }
    }

    /// The two independent checks the chips used to be drawn from, gone from the row bodies — this
    /// is what fails if either guard is "simplified" back to the field it reads. Both files still
    /// read the raw fields elsewhere (a popover's starting date, the over-do tint), so these are
    /// the *guard* spellings rather than the field names.
    @Test func neitherRowStillCountsItsDateChipsAlone() throws {
        for guardText in [
            "if style != .todayGrouped && !task.scheduledDate.isEmpty",
            "if !task.dueDate.isEmpty {"
        ] {
            try expectOccurrences(of: guardText, at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 0])
        }

        try expectOccurrences(
            of: "if !task.scheduledDate.isEmpty {",
            at: ["Cadence/iOS/iOSTaskViews.swift": 0]
        )

        // Non-vacuity: the guards that *are* there, in the files this test claims to have read.
        let macRow = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        #expect(macRow.contains("if datePlan.drawsDoDateChip {"))
        let iOSRow = try strippingComments(sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        // [[T-15491]]: the guard also binds the chip's words from the one due-date builder.
        #expect(iOSRow.contains("if datePlan.drawsDueDateChip, let dueUrgency,"))
    }

    /// [[T-7984]]: no Mac row drops its do-date pill for a whole section. `.todayGrouped` did, and
    /// its last caller was All Tasks' Group: By List — sections that are lists, not days — so every
    /// row there lost its do date and the picker it opens. The style is deleted; the one do-date
    /// suppression left is `dayAlreadyStatedBySurface`, an equality with the surface's named day.
    @Test func noMacRowDropsItsDoDateForAWholeSection() throws {
        try expectOccurrences(
            of: "todayGrouped",
            at: [
                "Cadence/macOS/Views/TasksListView.swift": 0,
                "Cadence/macOS/Views/TasksPanelSectionViews.swift": 0,
                "Cadence/macOS/Views/TasksPanelSupport.swift": 0,
                "Cadence/macOS/Views/TasksPanelComponents.swift": 0,
                "Cadence/macOS/Views/ListDetailSupportViews.swift": 0
            ]
        )
        try expectOccurrences(of: "MacTaskRowStyle", at: ["Cadence/macOS/Views/TasksPanelSupport.swift": 0])
        // Nor through the knob that is left: the Tasks page names no day, so it has none to withhold.
        try expectOccurrences(of: "dayAlreadyStatedBySurface", at: ["Cadence/macOS/Views/TasksListView.swift": 0])

        // Non-vacuity: the By List row is still the interactive row, and the row's do date still
        // goes through the one suppression it has.
        let page = try strippingComments(sourceFile("Cadence/macOS/Views/TasksListView.swift"))
        #expect(page.contains("showsContainer: showsContainer && !section.isListGroup"))
        let row = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        #expect(row.contains("dayAlreadyStatedBySurface: dayAlreadyStatedBySurface"))
        #expect(row.contains("return task.scheduledDate"))
    }

    // MARK: - T-10049 (b): a touch card folds a shared day, the Mac card keeps its two pickers

    /// **The rule.** A card whose date chips are only labels states a day the do date and the due
    /// date share once: the flag survives and the sun folds into it, which is `rowDatePlan`'s
    /// `.oneSharedDay` read by the card. Two different days are still two facts, and the Mac card
    /// — whose every token is the picker for its field — keeps both chips in either case.
    @Test func aTouchCardStatesADaySharedByBothDatesOnce() {
        let shared = task(doDate: "2026-08-21", dueDate: "2026-08-21")

        let touch = CadenceBoardCardMetadata.chips(
            for: shared, showsContainer: false, dateChipsArePickers: false, todayKey: "2026-08-20"
        )
        #expect(touch.map(\.kind) == [.dueDate])
        #expect(touch.first?.icon == CadenceBoardCardMetadata.dueDateIcon)

        let mac = CadenceBoardCardMetadata.chips(for: shared, showsContainer: false, todayKey: "2026-08-20")
        #expect(mac.map(\.kind) == [.doDate, .dueDate])

        let split = task(doDate: "2026-08-21", dueDate: "2026-08-25")
        #expect(
            CadenceBoardCardMetadata.chips(
                for: split, showsContainer: true, dateChipsArePickers: false, todayKey: "2026-08-20"
            ).map(\.kind) == [.doDate, .dueDate, .list]
        )
    }

    /// Compared as days through the shared plan, not re-derived: a do date stored loosely
    /// (`2026-8-21`, T-299) still folds into the deadline it names. And the urgency survives the
    /// fold — a late shared day keeps a red flag — while a do date alone keeps its sun.
    @Test func theTouchCardsFoldIsTheRowsPlanNotACopy() {
        let loose = task(doDate: "2026-8-21", dueDate: "2026-08-21")
        #expect(
            CadenceBoardCardMetadata.chips(
                for: loose, showsContainer: false, dateChipsArePickers: false, todayKey: "2026-08-20"
            ).map(\.kind) == [.dueDate]
        )

        let late = CadenceBoardCardMetadata.chips(
            for: task(doDate: "2026-08-19", dueDate: "2026-08-19"),
            showsContainer: false,
            dateChipsArePickers: false,
            todayKey: "2026-08-20"
        )
        #expect(late.map(\.kind) == [.dueDate])
        #expect(late.first?.emphasis == .urgent)

        #expect(
            CadenceBoardCardMetadata.chips(
                for: task(doDate: "2026-08-21"), showsContainer: false, dateChipsArePickers: false, todayKey: "2026-08-20"
            ).map(\.kind) == [.doDate]
        )
    }

    /// **The call sites.** Only the touch card says its chips are not pickers; the Mac card takes
    /// the default and so keeps its do-date picker. And the descriptor asks the rows' plan rather
    /// than comparing the two keys itself.
    @Test func onlyTheTouchCardFoldsASharedDay() throws {
        try expectOccurrences(
            of: "dateChipsArePickers: false",
            at: [
                "Cadence/iOS/iOSBoardCards.swift": 1,
                "Cadence/macOS/Views/KanbanCardView.swift": 0,
            ]
        )
        try expectOccurrences(of: "dateChipsArePickers", at: ["Cadence/macOS/Views/KanbanCardView.swift": 0])
        try expectCallSites(
            of: "CadenceTaskPresentationSupport.rowDatePlan",
            at: ["Cadence/Shared/CadenceBoardCardMetadata.swift": 1]
        )
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
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
