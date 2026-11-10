import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-14823]]: a repeating task with **no date at all** came straight back the moment it was
/// ticked. `plannedNextDates` only ever advanced a date the predecessor already had, so a daily
/// Inbox task with neither a due nor a do date minted an identical, equally undated open copy in
/// the same list: it could be ticked again at once, as often as you liked, and the series never
/// read as done for the day.
///
/// **The owner's call ([[T-15000]]) was option (a): the successor of a dateless series gets a do
/// date one period after the completion day.** Not a seeded do date of today when the repeat rule
/// is set, and not "keep it as an always-available checklist". It is the smallest change and it is
/// the arithmetic the dated path already performs on a late completion — one period off the
/// completion day — so the successor leaves the Inbox for Scheduled and returns on its day.
///
/// **The hard constraint is that the dated path does not move.** Only a series with neither a due
/// date nor a do date is in scope; `aSeriesWithOnlyADueDateStillSpawnsASuccessorWithNoDoDate` and
/// `aSeriesWithOnlyADoDateStillSpawnsASuccessorWithNoDueDate` are the two that red if the seed
/// escapes its guard, and `aDatedSeriesKeepsTheTimeItWasPlannedAt` holds the time half.
///
/// The last section is the seam with [[T-14824]], which landed minutes before this and takes an
/// untouched successor back on a reopen by reconstructing what the spawn would have written: a
/// successor that now carries a seeded do date must still be recognised and reclaimed, and a
/// rescheduled one must still be kept.
///
/// Fixtures are in-memory containers; nothing here reaches a real store. The `TestAction` pins
/// `TZ=UTC`, so the date keys below are fixed by the fixture's own `now`, not by this machine.
@MainActor
struct CadenceDatelessRecurringSuccessorTests {

    private let noWidgets = CadenceTaskReopenWidgetEffects { _ in }

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private func day(_ key: String) -> Date {
        guard let date = DateFormatters.date(from: key) else { fatalError("Bad test date key \(key)") }
        return date
    }

    /// A live occurrence of a repeating series carrying whichever dates the caller names.
    @discardableResult
    private func makeSeries(
        _ title: String = "Stretch",
        rule: TaskRecurrenceRule = .daily,
        dueDate: String = "",
        scheduledDate: String = "",
        scheduledStartMin: Int = -1,
        in context: ModelContext
    ) -> AppTask {
        let task = AppTask(title: title)
        task.recurrenceRule = rule
        task.dueDate = dueDate
        task.scheduledDate = scheduledDate
        task.scheduledStartMin = scheduledStartMin
        context.insert(task)
        return task
    }

    private func allTasks(in context: ModelContext) throws -> [AppTask] {
        try context.fetch(FetchDescriptor<AppTask>())
    }

    /// Completes `task` on `dayKey` and hands back the successor it spawned.
    private func tickRequiringSuccessor(
        _ task: AppTask,
        on dayKey: String,
        in context: ModelContext
    ) throws -> AppTask {
        let spawned = CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: day(dayKey))
        try context.save()
        return try #require(spawned, "the settle spawned nothing, so this test proves nothing")
    }

    // MARK: - 1. The defect: an undated series' successor is now dated

    /// The reported case. Inbox, daily, no dates, ticked: the copy is no longer sitting open in the
    /// Inbox beside it — it is scheduled for the next day.
    @Test func anUndatedDailySeriesSuccessorIsScheduledTheDayAfterTheCompletion() throws {
        let context = try makeContext()
        let task = makeSeries(in: context)
        try context.save()

        #expect(task.scheduledDate.isEmpty && task.dueDate.isEmpty, "non-vacuity: the predecessor is undated")

        let successor = try tickRequiringSuccessor(task, on: "2026-08-04", in: context)

        #expect(successor.scheduledDate == "2026-08-05")
        #expect(successor.scheduledDate > "2026-08-04", "the successor lands after the day it was spawned on")
        #expect(successor.dueDate.isEmpty, "the series had no due date, so the successor gets none")
        #expect(successor.scheduledStartMin == -1, "a seeded do date carries no time")
        #expect(successor.isRecurring, "the series carries on")
        #expect(try allTasks(in: context).count == 2)
    }

    /// Every cadence, one period on from the completion day — the same hop `shiftedDateKey` gives
    /// the dated path. Four rules, four relations, no shared arithmetic with the code under test.
    @Test func anUndatedSeriesSuccessorLandsOnePeriodAfterTheCompletionDayForEveryCadence() throws {
        let expected: [(TaskRecurrenceRule, String)] = [
            (.daily, "2026-08-05"),
            (.weekly, "2026-08-11"),
            (.monthly, "2026-09-04"),
            (.yearly, "2027-08-04")
        ]
        for (rule, dateKey) in expected {
            let context = try makeContext()
            let task = makeSeries("Undated \(rule.rawValue)", rule: rule, in: context)
            try context.save()

            let successor = try tickRequiringSuccessor(task, on: "2026-08-04", in: context)
            #expect(successor.scheduledDate == dateKey, "\(rule.rawValue) landed on \(successor.scheduledDate)")
            #expect(successor.dueDate.isEmpty)
        }
    }

    /// A monthly undated series completed on a 31st: the seeded day clamps to the target month's
    /// length, exactly as the dated monthly hop does (T-3103's rule, reached through the same
    /// `shiftedDateKey`). September has 30 days.
    @Test func anUndatedMonthlySeriesCompletedOnAThirtyFirstClampsToTheShorterMonth() throws {
        let context = try makeContext()
        let task = makeSeries("Pay rent", rule: .monthly, in: context)
        try context.save()

        let successor = try tickRequiringSuccessor(task, on: "2026-08-31", in: context)
        #expect(successor.scheduledDate == "2026-09-30")
    }

    /// Cancelling an occurrence advances the series too (T-202), so an undated series skipped
    /// rather than done gets the same dated successor. A cancel that still minted an undated copy
    /// would put the defect straight back through the other door.
    @Test func cancellingAnUndatedOccurrenceAlsoGivesItsSuccessorADoDate() throws {
        let context = try makeContext()
        let task = makeSeries("Water the plants", in: context)
        try context.save()

        let spawned = CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: context, now: day("2026-08-04"))
        try context.save()
        let successor = try #require(spawned, "cancelling stopped the series")
        #expect(successor.scheduledDate == "2026-08-05")
        #expect(task.isCancelled)
    }

    /// The seed happens **once**: the successor has a do date of its own, so its own completion
    /// takes the ordinary dated branch and the series keeps its cadence from there. A seed that
    /// re-applied on every hop would reset the series to the completion day for ever.
    @Test func theSuccessorOfAnUndatedSeriesCarriesOnFromItsOwnDoDate() throws {
        let context = try makeContext()
        let task = makeSeries(rule: .weekly, in: context)
        try context.save()

        let second = try tickRequiringSuccessor(task, on: "2026-08-04", in: context)
        #expect(second.scheduledDate == "2026-08-11")

        // Completed on its own day: the dated path hops one period from the occurrence's own date.
        let third = try tickRequiringSuccessor(second, on: "2026-08-11", in: context)
        #expect(third.scheduledDate == "2026-08-18")
        #expect(third.recurrenceOccurrenceIndex == second.recurrenceOccurrenceIndex + 1)
    }

    // MARK: - 2. The dated path does not move

    /// **The guard.** A series with a due date and no do date keeps minting successors with a due
    /// date and no do date. This is the test that reds if the seed is written without asking
    /// whether the predecessor had *either* date — the single most likely way to get this wrong.
    @Test func aSeriesWithOnlyADueDateStillSpawnsASuccessorWithNoDoDate() throws {
        let context = try makeContext()
        let task = makeSeries("Renew licence", dueDate: "2026-08-04", in: context)
        try context.save()

        let successor = try tickRequiringSuccessor(task, on: "2026-08-04", in: context)
        #expect(successor.dueDate == "2026-08-05", "non-vacuity: the due date advanced as it always did")
        #expect(successor.scheduledDate.isEmpty, "a due-dated series must not gain a do date")
        #expect(successor.scheduledStartMin == -1)
    }

    /// The mirror: a do-dated series keeps its empty due date. Advancing one date never fills the
    /// other, before this change or after it.
    @Test func aSeriesWithOnlyADoDateStillSpawnsASuccessorWithNoDueDate() throws {
        let context = try makeContext()
        let task = makeSeries("Stand-up", scheduledDate: "2026-08-04", in: context)
        try context.save()

        let successor = try tickRequiringSuccessor(task, on: "2026-08-04", in: context)
        #expect(successor.scheduledDate == "2026-08-05")
        #expect(successor.dueDate.isEmpty)
    }

    /// A dated occurrence planned at a time hands that time to its successor, as it always has —
    /// the half of the start-minute rule that is *not* the seed's. The other half, a seeded do
    /// date carrying no time, is held at the model's "not scheduled" default by the first test in
    /// this file and by [[T-14824]]'s own dateless case.
    @Test func aDatedSeriesKeepsTheTimeItWasPlannedAt() throws {
        let context = try makeContext()
        let task = makeSeries(
            "Standing call",
            rule: .weekly,
            dueDate: "2026-08-04",
            scheduledDate: "2026-08-04",
            scheduledStartMin: 540,
            in: context
        )
        try context.save()

        let successor = try tickRequiringSuccessor(task, on: "2026-08-04", in: context)
        #expect(successor.scheduledDate == "2026-08-11")
        #expect(successor.dueDate == "2026-08-11")
        #expect(successor.scheduledStartMin == 540, "the dated path's inherited time moved")
    }

    /// A dateless row that is **not** repeating is not a series and gets nothing: the seed lives
    /// behind `isRecurring`, so nothing about a one-off task changes.
    @Test func aDatelessNonRepeatingTaskStillSpawnsNothingAtAll() throws {
        let context = try makeContext()
        let task = AppTask(title: "One-off")
        task.recurrenceRule = .none
        context.insert(task)
        try context.save()

        let spawned = CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: day("2026-08-04"))
        try context.save()
        #expect(spawned == nil)
        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(try allTasks(in: context).count == 1)
    }

    // MARK: - 3. The end condition now asks about the day the successor really lands on

    /// An `.onDate` limit is compared with the successor's date. An undated series used to anchor
    /// to the completion day, so a limit falling *on* that day still spawned one more occurrence —
    /// dated, now, a period past the limit. The limit is asked about the day the successor appears.
    @Test func anUndatedSeriesEndDateIsMeasuredAgainstTheSuccessorsOwnDay() throws {
        let context = try makeContext()

        let stops = makeSeries("Ends today", in: context)
        stops.recurrenceEndMode = .onDate
        stops.recurrenceEndDate = "2026-08-04"

        let carriesOn = makeSeries("Ends tomorrow", in: context)
        carriesOn.recurrenceEndMode = .onDate
        carriesOn.recurrenceEndDate = "2026-08-05"
        try context.save()

        let ended = CadenceTaskRecurrenceWorkflowSupport.markDone(stops, in: context, now: day("2026-08-04"))
        #expect(ended == nil, "the successor would land on 2026-08-05, past the series' own limit")
        #expect(stops.recurrenceSpawnedTaskID == nil, "no dangling pointer on the final occurrence")

        let last = try #require(
            CadenceTaskRecurrenceWorkflowSupport.markDone(carriesOn, in: context, now: day("2026-08-04")),
            "a limit on the successor's own day must still allow it"
        )
        #expect(last.scheduledDate == "2026-08-05")
    }

    // MARK: - 4. The seam with [[T-14824]]: the reopen still takes the dated successor back

    /// The interaction neither ticket owns alone. [[T-14824]]'s reopen reclaims a successor only
    /// while it is still exactly what the spawn would have written, which it decides by planning
    /// the dates again from the predecessor's `completedAt`. A seeded do date is part of what the
    /// spawn writes, so it has to be part of what the reopen expects — otherwise every undated
    /// series' successor reads as "touched" and the untick silently leaves it behind, which is the
    /// very defect [[T-14824]] closed.
    @Test func untickingAnUndatedSeriesTakesBackTheSuccessorItsSeededDoDateIsOn() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = makeSeries(in: context)
        try context.save()

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)
        let successorID = try #require(task.recurrenceSpawnedTaskID, "the tick spawned nothing")
        let successor = try #require(try allTasks(in: context).first { $0.id == successorID })
        #expect(!successor.scheduledDate.isEmpty, "non-vacuity: this is the seeded-date case")
        #expect(try allTasks(in: context).count == 2)

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == nil, "the link survived, so the next tick cannot spawn")
        #expect(try allTasks(in: context).map(\.id) == [task.id])

        // In the store, not only in the context that deleted it.
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).count == 1)

        // And the series still works: ticking again spawns a fresh, dated successor.
        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)
        let secondID = try #require(task.recurrenceSpawnedTaskID)
        #expect(secondID != successorID)
        let second = try #require(try allTasks(in: context).first { $0.id == secondID })
        #expect(!second.scheduledDate.isEmpty)
    }

    /// The status menus' door reaches the same reopen, so it answers the same way on a seeded
    /// successor.
    @Test func settingAnUndatedOccurrenceBackToTodoTakesBackItsSeededSuccessor() throws {
        let context = try makeContext()
        let task = makeSeries(rule: .weekly, in: context)
        try context.save()

        try CadenceTaskMutationSupport.setStatus(.done, for: task, modelContext: context, widgetEffects: noWidgets)
        #expect(task.recurrenceSpawnedTaskID != nil)
        #expect(try allTasks(in: context).count == 2)

        try CadenceTaskMutationSupport.setStatus(.todo, for: task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(try allTasks(in: context).map(\.id) == [task.id])
    }

    /// The other side of [[T-14824]]'s gate, on the new shape: a seeded successor the user has
    /// **moved** is no longer the spawn's copy, so the untick keeps it and keeps the link. The
    /// reclaim must not become a blanket "delete the successor" just because this series is the
    /// one whose dates the spawn now invents.
    @Test func aRescheduledSeededSuccessorIsKeptWhenTheOccurrenceIsReopened() throws {
        let context = try makeContext()
        let task = makeSeries(in: context)
        try context.save()

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)
        let successorID = try #require(task.recurrenceSpawnedTaskID)
        let successor = try #require(try allTasks(in: context).first { $0.id == successorID })
        let seeded = successor.scheduledDate
        #expect(!seeded.isEmpty, "non-vacuity: this is the seeded-date case")
        successor.scheduledDate = "2099-01-02"
        try context.save()

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == successorID, "the link to a kept successor was cleared")
        #expect(try allTasks(in: context).count == 2)
        #expect(successor.scheduledDate == "2099-01-02", "the user's own date was overwritten")
    }
}
