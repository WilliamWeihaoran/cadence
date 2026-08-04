import Foundation
import SwiftData
import Testing
@testable import Cadence

// Deep regression coverage for the task/list deletion paths in
// Cadence/macOS/Services/TaskDeleteHelpers.swift and ListDeleteHelpers.swift, which AGENTS.md
// flags as "crash-sensitive because of SwiftData inverse relationships." Each test below maps to
// one audited deletion scenario. Singleton managers touched by deletion (FocusManager,
// HoveredTaskManager, TaskSubtaskEntryManager) are reset before and after every test so state
// never leaks across the suite.
#if os(macOS)
@MainActor
struct TaskDeleteHelpersScenarioTests {
    private func resetSharedManagers() {
        FocusManager.shared.activeSession = nil
        FocusManager.shared.selectedBundleTaskIDs = []
        FocusManager.shared.reset()
        HoveredTaskManager.shared.clear()
        TaskSubtaskEntryManager.shared.requestedTaskID = nil
    }

    // MARK: - 1. Deleting a task with subtasks leaves no dangling reference

    @Test func deletingTaskWithSubtasksRemovesSubtasksAndLeavesNoOrphans() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Plan trip")
        let subtaskA = Subtask(title: "Book flight")
        subtaskA.parentTask = task
        let subtaskB = Subtask(title: "Book hotel")
        subtaskB.parentTask = task

        modelContext.insert(task)
        modelContext.insert(subtaskA)
        modelContext.insert(subtaskB)
        try modelContext.save()

        modelContext.deleteTask(task)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
    }

    // MARK: - 2. Deleting a task with a linked calendar event ID doesn't crash or orphan the field

    @Test func deletingTaskWithLinkedCalendarEventClearsReferenceWithoutCrashing() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        // Note: task-owned Apple Calendar sync was intentionally removed (see commit
        // "Remove calendar sync and refine markdown slash commands"). `calendarEventID` on AppTask
        // is legacy-only now — nothing in the app assigns it a live value anymore, and
        // `SchedulingActions.removeFromCalendar` deliberately only clears the local field rather
        // than reaching into EventKit, since the ID may reference a user's own external event that
        // Cadence never owned. This test locks in that current, intentional behavior.
        let task = AppTask(title: "Standup")
        task.calendarEventID = "legacy-event-identifier"

        modelContext.insert(task)
        try modelContext.save()

        modelContext.deleteTask(task)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    // MARK: - 3. Deleting a task linked to a Goal recalculates progress correctly for both progress types

    @Test func deletingTaskLinkedToGoalRecalculatesProgressForSubtaskAndHourProgressTypes() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        for progressType in [GoalProgressType.subtasks, GoalProgressType.hours] {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let modelContext = ModelContext(container)

            let context = Context(name: "Work")
            let area = Area(name: "Health", context: context)
            let goal = Goal(title: "Get fit", context: context)
            goal.progressType = progressType
            let link = GoalListLink(goal: goal, area: area)

            let doneTask = AppTask(title: "Workout 1")
            doneTask.area = area
            doneTask.goal = goal
            doneTask.status = .done
            doneTask.completedAt = Date()

            let openTask = AppTask(title: "Workout 2")
            openTask.area = area
            openTask.goal = goal

            modelContext.insert(context)
            modelContext.insert(area)
            modelContext.insert(goal)
            modelContext.insert(link)
            modelContext.insert(doneTask)
            modelContext.insert(openTask)
            try modelContext.save()

            let before = GoalContributionResolver.summary(for: goal)
            #expect(before.totalTasks == 2)
            #expect(before.completedTasks == 1)

            // Delete the still-open task; the goal should now read as fully complete with no
            // stale reference to the deleted task.
            modelContext.deleteTask(openTask)
            try modelContext.save()

            #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 1)
            let after = GoalContributionResolver.summary(for: goal)
            #expect(after.totalTasks == 1)
            #expect(after.completedTasks == 1)
            #expect(after.progress == 1.0)

            // Now delete the remaining (done) task too — progress must not crash on an empty set.
            modelContext.deleteTask(doneTask)
            try modelContext.save()
            let empty = GoalContributionResolver.summary(for: goal)
            #expect(empty.totalTasks == 0)
            #expect(empty.progress == 0)
            #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        }
    }

    // MARK: - 4. Deleting an Area cascades through nested Projects, Tasks, Documents, and SavedLinks

    @Test func deletingAreaCascadesThroughNestedProjectsTasksDocumentsAndLinks() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Area", context: context)
        let projectA = Project(name: "Project A", context: context, area: area)
        let projectB = Project(name: "Project B", context: context, area: area)

        let areaTask = AppTask(title: "Area task")
        areaTask.area = area
        let projectATask = AppTask(title: "Project A task")
        projectATask.project = projectA
        let projectBTask = AppTask(title: "Project B task")
        projectBTask.project = projectB
        let subtask = Subtask(title: "Nested")
        subtask.parentTask = projectATask

        let areaDoc = Document(title: "Area doc")
        areaDoc.area = area
        let projectDoc = Document(title: "Project doc")
        projectDoc.project = projectA

        let areaLink = SavedLink(title: "Area link", url: "https://example.com/area")
        areaLink.area = area
        let projectLink = SavedLink(title: "Project link", url: "https://example.com/project")
        projectLink.project = projectB

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(projectA)
        modelContext.insert(projectB)
        modelContext.insert(areaTask)
        modelContext.insert(projectATask)
        modelContext.insert(projectBTask)
        modelContext.insert(subtask)
        modelContext.insert(areaDoc)
        modelContext.insert(projectDoc)
        modelContext.insert(areaLink)
        modelContext.insert(projectLink)
        try modelContext.save()

        modelContext.deleteArea(area)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<Context>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<Area>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Document>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<SavedLink>()).isEmpty)
    }

    // MARK: - 5. Deleting a Project independently of its parent Area keeps both sides consistent

    @Test func deletingProjectIndependentlyOfAreaKeepsInverseRelationshipConsistent() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Area", context: context)
        let project = Project(name: "Project", context: context, area: area)
        let projectTask = AppTask(title: "Project task")
        projectTask.project = project

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(projectTask)
        try modelContext.save()

        #expect((area.projects ?? []).contains { $0.id == project.id })

        modelContext.deleteProject(project)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        // The Area survives and its inverse relationship no longer references the deleted project.
        #expect(try modelContext.fetch(FetchDescriptor<Area>()).count == 1)
        #expect((area.projects ?? []).isEmpty)
    }

    // MARK: - 6. Rapid sequential deletion of multiple tasks doesn't crash on stale context references

    @Test func rapidSequentialDeletionOfMultipleTasksDoesNotCrashOrOrphanData() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        var tasks: [AppTask] = []
        for index in 0..<8 {
            let task = AppTask(title: "Task \(index)")
            task.context = context
            let subtask = Subtask(title: "Sub \(index)")
            subtask.parentTask = task
            modelContext.insert(task)
            modelContext.insert(subtask)
            tasks.append(task)
        }
        modelContext.insert(context)
        try modelContext.save()

        // Simulate rapid one-at-a-time deletion (e.g. Cmd+Delete spammed across several hovered
        // rows) rather than a single batched call, since that's the path most likely to trip over
        // stale fetched references between calls.
        for task in tasks {
            modelContext.deleteTask(task)
        }
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Context>()).count == 1)
    }

    @Test func batchDeletionOfMultipleTasksInOneCallRemovesAllCleanly() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        var ids: Set<UUID> = []
        for index in 0..<5 {
            let task = AppTask(title: "Batch \(index)")
            modelContext.insert(task)
            ids.insert(task.id)
        }
        try modelContext.save()

        modelContext.deleteTasks(withIDs: ids)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    // MARK: - 7. Deleting the active Focus task/bundle clears FocusManager instead of retaining a stale reference

    @Test func deletingActiveFocusTaskClearsFocusManagerSession() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Deep work")
        modelContext.insert(task)
        try modelContext.save()

        FocusManager.shared.startFocus(task: task)
        #expect(FocusManager.shared.activeTask?.id == task.id)

        modelContext.deleteTask(task)
        try modelContext.save()

        #expect(FocusManager.shared.activeSession == nil)
        #expect(FocusManager.shared.activeTask == nil)
        #expect(FocusManager.shared.isRunning == false)
    }

    @Test func deletingAllMembersOfActiveFocusBundleClearsFocusManagerSession() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let bundle = TaskBundle(title: "Morning admin", dateKey: "2026-08-04", startMin: 540, durationMinutes: 30)
        let taskA = AppTask(title: "Reply to emails")
        taskA.bundle = bundle
        let taskB = AppTask(title: "Clear inbox")
        taskB.bundle = bundle
        bundle.tasks = [taskA, taskB]

        modelContext.insert(bundle)
        modelContext.insert(taskA)
        modelContext.insert(taskB)
        try modelContext.save()

        FocusManager.shared.startFocus(bundle: bundle)
        #expect(FocusManager.shared.activeBundle?.id == bundle.id)

        // Deleting every member task empties the bundle, which is then itself deleted by
        // deleteEmptyBundles — FocusManager must not keep pointing at that deleted TaskBundle.
        modelContext.deleteTasks(withIDs: Set([taskA.id, taskB.id]))
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
        #expect(FocusManager.shared.activeSession == nil)
        #expect(FocusManager.shared.activeBundle == nil)
    }

    @Test func deletingOneMemberOfActiveFocusBundleKeepsSessionWhenBundleStillHasTasks() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let bundle = TaskBundle(title: "Morning admin", dateKey: "2026-08-04", startMin: 540, durationMinutes: 30)
        let taskA = AppTask(title: "Reply to emails")
        taskA.bundle = bundle
        let taskB = AppTask(title: "Clear inbox")
        taskB.bundle = bundle
        bundle.tasks = [taskA, taskB]

        modelContext.insert(bundle)
        modelContext.insert(taskA)
        modelContext.insert(taskB)
        try modelContext.save()

        FocusManager.shared.startFocus(bundle: bundle)
        FocusManager.shared.selectedBundleTaskIDs = [taskA.id, taskB.id]

        modelContext.deleteTask(taskA)
        try modelContext.save()

        // The bundle still has taskB, so it must survive and Focus must remain on it.
        #expect(try modelContext.fetch(FetchDescriptor<TaskBundle>()).count == 1)
        #expect(FocusManager.shared.activeBundle?.id == bundle.id)
        // The deleted task's id must be gone from the selection so a later commit doesn't touch it.
        #expect(!FocusManager.shared.selectedBundleTaskIDs.contains(taskA.id))
    }

    // MARK: - 8. Deleting an occurrence of a recurring series doesn't corrupt or kill the rest of the series

    @Test func deletingSpawnedOccurrenceLetsSourceTaskSpawnAFreshOneIfRedoneAndRecompleted() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let sourceTask = AppTask(title: "Daily standup")
        sourceTask.recurrenceRule = .daily
        sourceTask.scheduledDate = "2026-08-04"
        modelContext.insert(sourceTask)
        try modelContext.save()

        // Completing the source spawns occurrence #2.
        TaskWorkflowService.markDone(sourceTask, in: modelContext)
        try modelContext.save()

        guard let spawnedID = sourceTask.recurrenceSpawnedTaskID else {
            Issue.record("Expected completing a recurring task to spawn a next occurrence")
            return
        }
        let allAfterSpawn = try modelContext.fetch(FetchDescriptor<AppTask>())
        guard let occurrence2 = allAfterSpawn.first(where: { $0.id == spawnedID }) else {
            Issue.record("Expected to find the spawned occurrence")
            return
        }

        // The user deletes occurrence #2 before ever completing it (e.g. accidentally scheduled,
        // or just wants it gone) — this must not permanently kill the series.
        modelContext.deleteTask(occurrence2)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 1)
        // The source task's spawned pointer must be cleared, not left dangling at a deleted id —
        // otherwise `spawnNextOccurrenceIfNeeded`'s `recurrenceSpawnedTaskID == nil` guard would
        // permanently block any future occurrence from ever being generated again.
        #expect(sourceTask.recurrenceSpawnedTaskID == nil)

        // Reopen and re-complete the source task (a normal "undo completion" / redo flow) — this
        // must be able to spawn a fresh occurrence rather than silently doing nothing.
        TaskWorkflowService.markTodo(sourceTask)
        TaskWorkflowService.markDone(sourceTask, in: modelContext)
        try modelContext.save()

        #expect(sourceTask.recurrenceSpawnedTaskID != nil)
        let finalTasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        #expect(finalTasks.count == 2)
    }

    @Test func deletingMiddleOccurrenceWithALivingSuccessorLeavesTheChainIntact() throws {
        resetSharedManagers()
        defer { resetSharedManagers() }

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let taskA = AppTask(title: "Weekly review")
        taskA.recurrenceRule = .weekly
        taskA.scheduledDate = "2026-08-04"
        modelContext.insert(taskA)
        try modelContext.save()

        TaskWorkflowService.markDone(taskA, in: modelContext)
        try modelContext.save()
        let taskBID = try #require(taskA.recurrenceSpawnedTaskID)
        let taskB = try #require(try modelContext.fetch(FetchDescriptor<AppTask>()).first { $0.id == taskBID })

        TaskWorkflowService.markDone(taskB, in: modelContext)
        try modelContext.save()
        let taskCID = try #require(taskB.recurrenceSpawnedTaskID)

        // Delete the middle occurrence (B) — the series already continued on to C, so this must
        // not disturb A's or C's state, and no crash should occur walking the chain afterward.
        modelContext.deleteTask(taskB)
        try modelContext.save()

        let remaining = try modelContext.fetch(FetchDescriptor<AppTask>())
        #expect(remaining.count == 2)
        #expect(remaining.contains { $0.id == taskA.id })
        #expect(remaining.contains { $0.id == taskCID })
        // A still (correctly) believes it spawned B — B's replacement (C) already exists and
        // continues the chain, so no repair is needed or attempted here.
        #expect(taskA.recurrenceSpawnedTaskID == taskBID)

        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: taskA,
            allTasks: remaining,
            scope: .thisAndFuture
        )
        // Walking "this and future" from A must not crash even though B (the recorded link) is
        // gone, and must still land on the remaining series member (C) via the seriesID fallback.
        #expect(Set(targets.map(\.id)) == Set([taskA.id, taskCID]))
    }
}
#endif
