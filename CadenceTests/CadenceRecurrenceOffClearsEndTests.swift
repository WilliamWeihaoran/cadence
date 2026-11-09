import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-14731]] — Repeat -> Never drops the series' end, at the one writer every row door uses.**
///
/// The task editor's save cleared the end when repeat was switched off
/// (`CadenceTaskEditDraftCommit.apply`), but the Mac row's Repeat menu and chip popover, the note
/// embed card and the iOS row menu all write through
/// `CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule` alone, which left the end behind. So
/// Never-then-Weekly from a row re-armed an old bound, and a series whose bound was already reached
/// minted nothing on its next completion although its row wore the repeat glyph again.
@MainActor
struct CadenceRecurrenceOffClearsEndTests {

    /// A count-bounded series' last occurrence: occurrence 3 of "After 3", so its end is reached.
    private func lastOccurrence(in context: ModelContext) throws -> AppTask {
        let task = AppTask(title: "Water the plants")
        task.recurrenceRule = .weekly
        task.recurrenceSeriesIDRaw = UUID().uuidString
        task.recurrenceOccurrenceIndex = 2
        task.recurrenceEndMode = .afterCount
        task.recurrenceEndCount = 3
        task.scheduledDate = "2026-11-09"
        context.insert(task)
        try context.save()
        return task
    }

    @Test func aRowsRepeatNeverClearsTheSeriesEnd() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = try lastOccurrence(in: context)

        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(.none, to: task, allTasks: [task], scope: .thisTask)

        #expect(task.recurrenceRule == TaskRecurrenceRule.none)
        #expect(task.recurrenceEndMode == .never, "a task that no longer repeats kept its series end")
        #expect(task.recurrenceEndCount == 0)
        #expect(task.recurrenceEndDate.isEmpty)
    }

    /// The user-visible path: Never, then Weekly again from a row, then complete it. The series must
    /// go on -- the old "After 3" it already reached must not come back and stop it.
    @Test func neverThenWeeklyFromARowRepeatsAgainOnCompletion() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = try lastOccurrence(in: context)

        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(.none, to: task, allTasks: [task], scope: .thisTask)
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(.weekly, to: task, allTasks: [task], scope: .thisTask)
        #expect(task.recurrenceEndMode == .never, "re-picking a rule re-armed the old bound")

        let successor = CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: Date())
        #expect(successor != nil, "the re-enabled weekly task spawned no next occurrence")
    }

    /// A passed "Until" date is the other bound that silently stopped a re-enabled series.
    @Test func aPassedUntilDateDoesNotComeBackEither() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = try lastOccurrence(in: context)
        task.recurrenceEndMode = .onDate
        task.recurrenceEndCount = 0
        task.recurrenceEndDate = "2026-10-01"

        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(.none, to: task, allTasks: [task], scope: .thisTask)
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(.daily, to: task, allTasks: [task], scope: .thisTask)

        #expect(task.recurrenceEndDate.isEmpty)
        #expect(CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: Date()) != nil)
    }

    /// Changing one rule for another is not turning repeat off: the bound the user set stays.
    @Test func switchingBetweenRulesKeepsTheEnd() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = try lastOccurrence(in: context)

        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(.daily, to: task, allTasks: [task], scope: .thisTask)

        #expect(task.recurrenceEndMode == .afterCount)
        #expect(task.recurrenceEndCount == 3)
    }

    /// This-and-future reaches the later occurrences with the rule, so it reaches them with the
    /// cleared end too, and a refused commit puts every bound back.
    @Test func thisAndFutureClearsEveryLaterOccurrenceAndARefusalRestoresIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seriesID = UUID().uuidString
        let tasks = (0..<2).map { index -> AppTask in
            let task = AppTask(title: "Occurrence \(index)")
            task.recurrenceRule = .daily
            task.recurrenceSeriesIDRaw = seriesID
            task.recurrenceOccurrenceIndex = index
            task.recurrenceEndMode = .afterCount
            task.recurrenceEndCount = 5
            task.scheduledDate = "2026-11-1\(index)"
            context.insert(task)
            return task
        }
        tasks[0].recurrenceSpawnedTaskID = tasks[1].id
        try context.save()

        struct Refused: Error {}
        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(from: tasks[0], allTasks: tasks, scope: .thisAndFuture)
        let refused = CadenceTaskFieldEditCommit.commit(
            tasks[0], alsoRestoring: targets, in: context, commit: { _ in throw Refused() }
        ) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(.none, to: tasks[0], allTasks: tasks, scope: .thisAndFuture)
        }
        #expect(!refused)
        #expect(tasks.map(\.recurrenceEndCount) == [5, 5], "a refused Never left the bounds cleared")

        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(.none, to: tasks[0], allTasks: tasks, scope: .thisAndFuture)
        #expect(tasks.map(\.recurrenceEndMode) == [.never, .never])
        #expect(tasks.map(\.recurrenceEndCount) == [0, 0])
    }
}
