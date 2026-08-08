import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Covers the recurring-series *end condition* (`TaskRecurrenceEndMode`): a series can now stop
/// on a calendar date or after N occurrences instead of only repeating forever.
@MainActor
struct TaskRecurrenceEndConditionTests {
    private func makeRecurringTask(
        title: String = "Recurring task",
        rule: TaskRecurrenceRule = .daily,
        dueDate: String = "",
        scheduledDate: String = ""
    ) -> AppTask {
        let task = AppTask(title: title)
        task.recurrenceRule = rule
        task.dueDate = dueDate
        task.scheduledDate = scheduledDate
        return task
    }

    private func spawnedTask(for task: AppTask, in context: ModelContext) throws -> AppTask? {
        guard let spawnedID = task.recurrenceSpawnedTaskID else { return nil }
        let descriptor = FetchDescriptor<AppTask>()
        return try context.fetch(descriptor).first { $0.id == spawnedID }
    }

    private func day(_ key: String) -> Date {
        guard let date = DateFormatters.date(from: key) else {
            fatalError("Bad test date key \(key)")
        }
        return date
    }

    /// Completes `task` and returns its successor, or nil if the series stopped.
    @discardableResult
    private func completeAndSpawn(
        _ task: AppTask,
        in context: ModelContext,
        now: Date
    ) throws -> AppTask? {
        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: now)
        try context.save()
        return try spawnedTask(for: task, in: context)
    }

    // MARK: - 1. `.never` is the default and still repeats forever (no regression)

    @Test func defaultEndModeIsNeverAndSeriesKeepsRepeating() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        context.insert(root)
        try context.save()

        #expect(root.recurrenceEndMode == .never)
        #expect(root.recurrenceEndDate.isEmpty)
        #expect(root.recurrenceEndCount == 0)
        #expect(root.recurrenceHasEnded == false)

        var current = root
        for hop in 0..<5 {
            guard let next = try completeAndSpawn(current, in: context, now: day("2026-08-04")) else {
                Issue.record("A `.never` series must keep spawning — stopped at hop \(hop)")
                return
            }
            #expect(next.recurrenceEndMode == .never)
            current = next
        }
    }

    // MARK: - 2. `.onDate` stops exactly at the boundary, never overshooting it

    @Test func onDateSeriesSpawnsUpToTheEndDateAndStopsExactlyThere() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        // Daily, do date 2026-08-04, ending 2026-08-06.
        // Allowed successors: 08-05, 08-06. The one that would be 08-07 must never exist.
        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        root.recurrenceEndMode = .onDate
        root.recurrenceEndDate = "2026-08-06"
        context.insert(root)
        try context.save()

        guard let second = try completeAndSpawn(root, in: context, now: day("2026-08-04")) else {
            Issue.record("Expected an occurrence on 2026-08-05")
            return
        }
        #expect(second.scheduledDate == "2026-08-05")

        guard let third = try completeAndSpawn(second, in: context, now: day("2026-08-05")) else {
            Issue.record("The occurrence landing exactly ON the end date must still be created")
            return
        }
        // Boundary day itself is inclusive.
        #expect(third.scheduledDate == "2026-08-06")

        // Completing the boundary occurrence must not produce 2026-08-07.
        let overshoot = try completeAndSpawn(third, in: context, now: day("2026-08-06"))
        #expect(overshoot == nil)
        #expect(third.isDone)
        #expect(third.recurrenceSpawnedTaskID == nil)

        let allTasks = try context.fetch(FetchDescriptor<AppTask>())
        #expect(allTasks.count == 3)
        #expect(allTasks.allSatisfy { $0.scheduledDate <= "2026-08-06" })
    }

    @Test func onDateSeriesWithEndDateOnTheStartingOccurrenceSpawnsNothingAtAll() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        // End date == this occurrence's own date, so the very next one (08-05) already overshoots.
        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        root.recurrenceEndMode = .onDate
        root.recurrenceEndDate = "2026-08-04"
        context.insert(root)
        try context.save()

        let next = try completeAndSpawn(root, in: context, now: day("2026-08-04"))
        #expect(next == nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    /// The `.onDate` comparison uses the *do date* (`scheduledDate`) when the task has one, falling
    /// back to the due date otherwise — the same precedence `recurrenceSortDateKey` already uses.
    @Test func onDateComparisonUsesDoDateWhenBothDatesArePresent() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        // Do date advances 08-04 -> 08-05 (inside the limit); due date advances 08-20 -> 08-21
        // (outside it). Do date wins, so the occurrence is allowed.
        let root = makeRecurringTask(dueDate: "2026-08-20", scheduledDate: "2026-08-04")
        root.recurrenceEndMode = .onDate
        root.recurrenceEndDate = "2026-08-06"
        context.insert(root)
        try context.save()

        guard let next = try completeAndSpawn(root, in: context, now: day("2026-08-04")) else {
            Issue.record("The do date is inside the limit, so this occurrence should exist")
            return
        }
        #expect(next.scheduledDate == "2026-08-05")
        #expect(next.dueDate == "2026-08-21")
    }

    @Test func onDateComparisonFallsBackToDueDateWhenThereIsNoDoDate() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(rule: .weekly, dueDate: "2026-08-04")
        root.recurrenceEndMode = .onDate
        root.recurrenceEndDate = "2026-08-11"
        context.insert(root)
        try context.save()

        guard let second = try completeAndSpawn(root, in: context, now: day("2026-08-04")) else {
            Issue.record("Expected a due-dated occurrence on 2026-08-11")
            return
        }
        #expect(second.dueDate == "2026-08-11")   // exactly on the boundary — allowed

        // Next would be 2026-08-18, past the limit.
        let overshoot = try completeAndSpawn(second, in: context, now: day("2026-08-11"))
        #expect(overshoot == nil)
    }

    // MARK: - 3. `.afterCount` produces exactly N occurrences

    @Test func afterCountSeriesProducesExactlyNOccurrences() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        root.recurrenceEndMode = .afterCount
        root.recurrenceEndCount = 4
        context.insert(root)
        try context.save()

        var chain = [root]
        var current = root
        // Try to run well past the limit; the engine should refuse after the 4th.
        for _ in 0..<8 {
            guard let next = try completeAndSpawn(current, in: context, now: day("2026-08-04")) else { break }
            chain.append(next)
            current = next
        }

        #expect(chain.count == 4)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 4)
        // `recurrenceOccurrenceIndex` is 0-based, so the 4th occurrence is index 3.
        #expect(chain.map(\.recurrenceOccurrenceIndex) == [0, 1, 2, 3])
        #expect(chain.map(\.recurrenceOccurrenceNumber) == [1, 2, 3, 4])
        #expect(chain.last?.recurrenceHasEnded == true)
        #expect(chain.first?.recurrenceHasEnded == false)
    }

    @Test func afterCountOfOneNeverSpawnsASecondOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        root.recurrenceEndMode = .afterCount
        root.recurrenceEndCount = 1
        context.insert(root)
        try context.save()

        #expect(root.recurrenceHasEnded == true)
        let next = try completeAndSpawn(root, in: context, now: day("2026-08-04"))
        #expect(next == nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    // MARK: - 4. The end condition is inherited across hops (the series must not forget its limit)

    @Test func endConditionIsInheritedAcrossAtLeastThreeHops() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-01")
        root.recurrenceEndMode = .onDate
        root.recurrenceEndDate = "2026-09-30"
        context.insert(root)
        try context.save()

        var current = root
        for hop in 1...3 {
            guard let next = try completeAndSpawn(current, in: context, now: day("2026-08-01")) else {
                Issue.record("Series died early at hop \(hop)")
                return
            }
            #expect(next.recurrenceEndMode == .onDate)
            #expect(next.recurrenceEndDate == "2026-09-30")
            #expect(next.recurrenceEndModeRaw == root.recurrenceEndModeRaw)
            current = next
        }
        #expect(current.recurrenceOccurrenceIndex == 3)
    }

    @Test func afterCountIsInheritedSoTheLimitStillBitesSeveralHopsLater() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        root.recurrenceEndMode = .afterCount
        root.recurrenceEndCount = 4
        context.insert(root)
        try context.save()

        var current = root
        for hop in 1...3 {
            guard let next = try completeAndSpawn(current, in: context, now: day("2026-08-04")) else {
                Issue.record("Series died early at hop \(hop)")
                return
            }
            // If the successor forgot the limit, it would read back as `.never` / 0 and the series
            // would silently become endless — that's the bug this test exists for.
            #expect(next.recurrenceEndMode == .afterCount)
            #expect(next.recurrenceEndCount == 4)
            current = next
        }

        // 4th occurrence: the inherited limit must stop it here, three hops from where it was set.
        #expect(current.recurrenceOccurrenceNumber == 4)
        let overshoot = try completeAndSpawn(current, in: context, now: day("2026-08-04"))
        #expect(overshoot == nil)
    }

    // MARK: - 5. The final occurrence completes normally, with no dangling spawn pointer

    @Test func finalOccurrenceCompletesNormallyAndLeavesNoDanglingSpawnPointer() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        root.recurrenceEndMode = .afterCount
        root.recurrenceEndCount = 2
        context.insert(root)
        try context.save()

        guard let last = try completeAndSpawn(root, in: context, now: day("2026-08-04")) else {
            Issue.record("Expected a second occurrence")
            return
        }

        let fixedNow = day("2026-08-05")
        CadenceTaskRecurrenceWorkflowSupport.markDone(last, in: context, now: fixedNow)
        try context.save()

        // Ending the series must not block completion.
        #expect(last.status == .done)
        #expect(last.completedAt == fixedNow)
        // ...and must not leave a pointer to an occurrence that was never created.
        #expect(last.recurrenceSpawnedTaskID == nil)
        #expect(last.recurrenceSpawnedTaskIDRaw.isEmpty)
        // Series identity is still intact on the terminal occurrence.
        #expect(last.recurrenceSeriesID == root.recurrenceSeriesID)

        let allTasks = try context.fetch(FetchDescriptor<AppTask>())
        #expect(allTasks.count == 2)
        // No task points at something that isn't in the store.
        let ids = Set(allTasks.map(\.id))
        for task in allTasks {
            if let spawnedID = task.recurrenceSpawnedTaskID {
                #expect(ids.contains(spawnedID))
            }
        }
    }

    @Test func cancellingTheFinalOccurrenceAlsoEndsCleanly() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        root.recurrenceEndMode = .afterCount
        root.recurrenceEndCount = 1
        context.insert(root)
        try context.save()

        CadenceTaskRecurrenceWorkflowSupport.markCancelled(root, in: context, now: day("2026-08-04"))
        try context.save()

        #expect(root.status == .cancelled)
        #expect(root.recurrenceSpawnedTaskID == nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    // MARK: - 6. Stray / unusable end values degrade to `.never` instead of breaking anything

    @Test func nonRecurringTaskWithStrayEndValuesStillCompletesAndSpawnsNothing() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let task = AppTask(title: "One-off with leftover recurrence-end config")
        task.recurrenceRule = .none
        task.recurrenceEndMode = .afterCount
        task.recurrenceEndCount = 3
        task.recurrenceEndDate = "2026-01-01"
        task.scheduledDate = "2026-08-04"
        context.insert(task)
        try context.save()

        // A task that doesn't recur has no end condition to speak of.
        #expect(task.effectiveRecurrenceEndMode == .never)
        #expect(task.recurrenceHasEnded == false)
        #expect(task.shouldSpawnNextOccurrence(nextDateKey: "2026-08-05") == false)

        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: day("2026-08-04"))
        try context.save()

        #expect(task.status == .done)
        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    @Test func onDateWithNoEndDateAndAfterCountWithNonPositiveCountBothFallBackToNever() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let missingDate = makeRecurringTask(title: "onDate, no date", scheduledDate: "2026-08-04")
        missingDate.recurrenceEndMode = .onDate
        missingDate.recurrenceEndDate = ""

        let zeroCount = makeRecurringTask(title: "afterCount, zero", scheduledDate: "2026-08-04")
        zeroCount.recurrenceEndMode = .afterCount
        zeroCount.recurrenceEndCount = 0

        context.insert(missingDate)
        context.insert(zeroCount)
        try context.save()

        #expect(missingDate.effectiveRecurrenceEndMode == .never)
        #expect(zeroCount.effectiveRecurrenceEndMode == .never)
        #expect(zeroCount.recurrenceHasEnded == false)

        // An unusable end configuration must not silently kill the series.
        #expect(try completeAndSpawn(missingDate, in: context, now: day("2026-08-04")) != nil)
        #expect(try completeAndSpawn(zeroCount, in: context, now: day("2026-08-04")) != nil)
    }

    @Test func datelessRecurringTaskWithPastEndDateStopsUsingTodayAsTheAnchor() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        // No do date and no due date: the successor's effective date is the day it appears.
        let stillOpen = makeRecurringTask(title: "Dateless, limit in the future")
        stillOpen.recurrenceEndMode = .onDate
        stillOpen.recurrenceEndDate = "2026-08-31"

        let expired = makeRecurringTask(title: "Dateless, limit already passed")
        expired.recurrenceEndMode = .onDate
        expired.recurrenceEndDate = "2026-07-01"

        context.insert(stillOpen)
        context.insert(expired)
        try context.save()

        #expect(try completeAndSpawn(stillOpen, in: context, now: day("2026-08-04")) != nil)
        #expect(try completeAndSpawn(expired, in: context, now: day("2026-08-04")) == nil)
    }

    // MARK: - 7. `applyRecurrenceEnd` normalizes and propagates across the series

    @Test func applyRecurrenceEndNormalizesValuesAndPropagatesToFutureOccurrences() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        context.insert(root)
        try context.save()

        guard let second = try completeAndSpawn(root, in: context, now: day("2026-08-04")),
              let third = try completeAndSpawn(second, in: context, now: day("2026-08-05")) else {
            Issue.record("Expected a three-occurrence chain to configure")
            return
        }

        let allTasks = try context.fetch(FetchDescriptor<AppTask>())
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
            mode: .afterCount,
            endDateKey: "2026-12-31",   // irrelevant for .afterCount — must be normalized away
            endCount: 5,
            to: root,
            allTasks: allTasks,
            scope: .thisAndFuture
        )
        try context.save()

        for task in [root, second, third] {
            #expect(task.recurrenceEndMode == .afterCount)
            #expect(task.recurrenceEndCount == 5)
            #expect(task.recurrenceEndDate.isEmpty)
        }

        // Switching back to `.never` must not leave a stray limit behind.
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
            mode: .never,
            to: root,
            allTasks: try context.fetch(FetchDescriptor<AppTask>()),
            scope: .thisAndFuture
        )
        try context.save()

        for task in [root, second, third] {
            #expect(task.recurrenceEndMode == .never)
            #expect(task.recurrenceEndCount == 0)
            #expect(task.recurrenceEndDate.isEmpty)
        }
    }

    @Test func applyRecurrenceEndClampsNonPositiveCountsToOne() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let root = makeRecurringTask(scheduledDate: "2026-08-04")
        context.insert(root)
        try context.save()

        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
            mode: .afterCount,
            endCount: 0,
            to: root,
            allTasks: [root],
            scope: .thisTask
        )
        #expect(root.recurrenceEndCount == 1)
        #expect(root.effectiveRecurrenceEndMode == .afterCount)
    }
}
