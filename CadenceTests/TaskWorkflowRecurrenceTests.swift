import Foundation
import SwiftData
import Testing
@testable import Cadence

#if os(macOS)
@MainActor
struct TaskWorkflowRecurrenceTests {
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

    // MARK: - 1. Subtasks carry to the next occurrence as a fresh, unchecked template

    @Test func completingRecurringTaskCopiesSubtasksFreshWithoutMutatingOriginal() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let task = makeRecurringTask(scheduledDate: "2026-08-04")
        let doneSubtask = Subtask(title: "Packed lunch")
        doneSubtask.isDone = true
        doneSubtask.order = 0
        let openSubtask = Subtask(title: "Check weather")
        openSubtask.order = 1
        task.subtasks = [doneSubtask, openSubtask]
        doneSubtask.parentTask = task
        openSubtask.parentTask = task

        context.insert(task)
        try context.save()

        TaskWorkflowService.markDone(task, in: context)
        try context.save()

        // Original task's own subtasks are untouched history.
        let originalSubtasks = (task.subtasks ?? []).sorted { $0.order < $1.order }
        #expect(originalSubtasks.count == 2)
        #expect(originalSubtasks[0].isDone == true)
        #expect(originalSubtasks[1].isDone == false)

        guard let next = try spawnedTask(for: task, in: context) else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        let nextSubtasks = (next.subtasks ?? []).sorted { $0.order < $1.order }
        #expect(nextSubtasks.count == 2)
        #expect(nextSubtasks.map(\.title) == ["Packed lunch", "Check weather"])
        // The new occurrence always starts clean, regardless of the old subtasks' completion state.
        #expect(nextSubtasks.allSatisfy { !$0.isDone })
        // Copies must be distinct model instances, not shared/re-parented originals.
        #expect(Set(nextSubtasks.map(\.id)).isDisjoint(with: Set(originalSubtasks.map(\.id))))
    }

    // MARK: - 2. Linked calendar event: old event preserved as history, new occurrence starts unlinked

    @Test func completingRecurringTaskPreservesOldCalendarLinkAndLeavesNextOccurrenceUnlinked() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let task = makeRecurringTask(scheduledDate: "2026-08-04")
        task.calendarEventID = "event-abc-123"

        context.insert(task)
        try context.save()

        TaskWorkflowService.markDone(task, in: context)
        try context.save()

        // The completed occurrence keeps its historical calendar link.
        #expect(task.calendarEventID == "event-abc-123")

        guard let next = try spawnedTask(for: task, in: context) else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        // The new occurrence must not collide with or inherit the old event.
        #expect(next.calendarEventID.isEmpty)
    }

    // MARK: - 3. Goal progress updates once per completed occurrence, without double-counting the spawned one

    @Test func completingRecurringTaskUpdatesGoalProgressWithoutDoubleCountingSpawnedOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Weekly Rituals", context: context)
        let goal = Goal(title: "Stay on top of admin", context: context)
        let link = GoalListLink(goal: goal, area: area)

        let task = makeRecurringTask(title: "Weekly review", rule: .weekly, dueDate: "2026-08-04")
        task.area = area
        task.context = context
        task.goal = goal

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(goal)
        modelContext.insert(link)
        modelContext.insert(task)
        try modelContext.save()

        let before = GoalContributionResolver.summary(for: goal, now: DateFormatters.date(from: "2026-08-04") ?? Date())
        #expect(before.totalTasks == 1)
        #expect(before.completedTasks == 0)

        TaskWorkflowService.markDone(task, in: modelContext)
        try modelContext.save()

        guard let next = try spawnedTask(for: task, in: modelContext) else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        // The spawned occurrence should stay linked to the same goal (continuity), just like area/project/context.
        #expect(next.goal?.id == goal.id)

        let after = GoalContributionResolver.summary(for: goal, now: DateFormatters.date(from: "2026-08-04") ?? Date())
        // One more total task (the new occurrence) and exactly one completed — no double-counting.
        #expect(after.totalTasks == 2)
        #expect(after.completedTasks == 1)
        #expect(after.progress == 0.5)
    }

    // MARK: - 4. Long-overdue recurring completion catches up to today instead of producing a stale date

    @Test func recurrenceWorkflowSupportAnchorsOverdueCompletionToProvidedNow() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let task = makeRecurringTask(rule: .daily, dueDate: "2026-07-28", scheduledDate: "2026-07-28")
        context.insert(task)
        try context.save()

        let fixedNow = DateFormatters.date(from: "2026-08-04")!
        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: fixedNow)
        try context.save()

        guard let next = try spawnedTask(for: task, in: context) else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        // Anchored to "now" (2026-08-04), the next daily occurrence should be tomorrow, not last-week+1.
        #expect(next.dueDate == "2026-08-05")
        #expect(next.scheduledDate == "2026-08-05")
    }

    @Test func completingRecurringTaskOnScheduleAdvancesFromOriginalDateNotFromToday() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        // Due date is in the future relative to "now" — completing early shouldn't collapse the cadence to today.
        let task = makeRecurringTask(rule: .daily, dueDate: "2026-08-10")
        context.insert(task)
        try context.save()

        let fixedNow = DateFormatters.date(from: "2026-08-04")!
        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: fixedNow)
        try context.save()

        guard let next = try spawnedTask(for: task, in: context) else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        #expect(next.dueDate == "2026-08-11")
    }

    // MARK: - 5. Cancelling a recurring occurrence still advances the series instead of silently killing it

    @Test func cancellingRecurringTaskSpawnsNextOccurrenceSoSeriesContinues() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let task = makeRecurringTask(scheduledDate: "2026-08-04")
        context.insert(task)
        try context.save()

        TaskWorkflowService.markCancelled(task, in: context)
        try context.save()

        #expect(task.status == .cancelled)
        #expect(task.completedAt == nil)
        #expect(task.recurrenceSpawnedTaskID != nil)

        guard let next = try spawnedTask(for: task, in: context) else {
            Issue.record("Cancelling a recurring task must still spawn the next occurrence, or the whole future series dies")
            return
        }
        #expect(next.status == .todo)
        #expect(next.recurrenceSourceTaskID == task.id)
        #expect(next.recurrenceSeriesID == task.recurrenceSeriesID)
    }

    @Test func cancellingNonRecurringTaskDoesNotSpawnAnything() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let task = AppTask(title: "One-off task")
        context.insert(task)
        try context.save()

        TaskWorkflowService.markCancelled(task, in: context)
        try context.save()

        #expect(task.status == .cancelled)
        #expect(task.recurrenceSpawnedTaskID == nil)

        let allTasks = try context.fetch(FetchDescriptor<AppTask>())
        #expect(allTasks.count == 1)
    }

    // MARK: - 6. Rapid/duplicate completion attempts must not spawn two next-occurrences

    @Test func duplicateMarkDoneCallsOnlySpawnOneNextOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let task = makeRecurringTask(scheduledDate: "2026-08-04")
        context.insert(task)
        try context.save()

        // Simulate a double-click / double-shortcut race calling completion twice in quick succession.
        TaskWorkflowService.markDone(task, in: context)
        TaskWorkflowService.markDone(task, in: context)
        try context.save()

        let spawnedFromTask = try context.fetch(FetchDescriptor<AppTask>())
            .filter { $0.recurrenceSourceTaskID == task.id }
        #expect(spawnedFromTask.count == 1)
    }

    @Test func completingThenCancellingAlreadySpawnedTaskDoesNotSpawnASecondOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let task = makeRecurringTask(scheduledDate: "2026-08-04")
        context.insert(task)
        try context.save()

        TaskWorkflowService.markDone(task, in: context)
        // Re-toggling status on an already-spawned task (e.g. done -> cancelled via a stray shortcut)
        // must not spawn a second occurrence.
        TaskWorkflowService.markCancelled(task, in: context)
        try context.save()

        let spawnedFromTask = try context.fetch(FetchDescriptor<AppTask>())
            .filter { $0.recurrenceSourceTaskID == task.id }
        #expect(spawnedFromTask.count == 1)
    }

    // MARK: - 7. Series identity and occurrence index stay correct across a long chain, never colliding between series

    @Test func recurrenceSeriesIdentityAndOccurrenceIndexStayConsistentAcrossChainAndAcrossSeries() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let seriesARoot = makeRecurringTask(title: "Series A", scheduledDate: "2026-08-01")
        let seriesBRoot = makeRecurringTask(title: "Series B", scheduledDate: "2026-08-01")
        context.insert(seriesARoot)
        context.insert(seriesBRoot)
        try context.save()

        TaskWorkflowService.markDone(seriesBRoot, in: context)
        try context.save()
        guard let seriesBNext = try spawnedTask(for: seriesBRoot, in: context) else {
            Issue.record("Expected series B to spawn its next occurrence")
            return
        }

        var chain = [seriesARoot]
        var current = seriesARoot
        for _ in 0..<3 {
            TaskWorkflowService.markDone(current, in: context)
            try context.save()
            guard let next = try spawnedTask(for: current, in: context) else {
                Issue.record("Expected series A to keep spawning occurrences")
                return
            }
            chain.append(next)
            current = next
        }

        // All four generations share one series identity, rooted at the first task's own id.
        let expectedSeriesID = seriesARoot.recurrenceSeriesID
        for (index, occurrence) in chain.enumerated() {
            #expect(occurrence.recurrenceSeriesID == expectedSeriesID)
            #expect(occurrence.recurrenceOccurrenceIndex == index)
        }

        // Series B must never collide with series A's identity or membership.
        #expect(seriesBRoot.recurrenceSeriesID != expectedSeriesID)
        #expect(seriesBNext.recurrenceSeriesID == seriesBRoot.recurrenceSeriesID)
        #expect(!chain.contains { $0.id == seriesBRoot.id || $0.id == seriesBNext.id })

        // "This and future" targeting from the series A root must walk the whole chain and nothing from series B.
        let allTasks = try context.fetch(FetchDescriptor<AppTask>())
        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: seriesARoot,
            allTasks: allTasks,
            scope: .thisAndFuture
        )
        #expect(Set(targets.map(\.id)) == Set(chain.map(\.id)))
    }
}
#endif
