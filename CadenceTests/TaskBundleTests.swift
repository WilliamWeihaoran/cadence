import SwiftData
import Testing
@testable import Cadence

#if os(macOS)
@MainActor
struct TaskBundleTests {
    @Test func addingTaskToBundleUsesBundleDateWithoutTaskTime() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Five minute follow-up")
        task.scheduledDate = "2026-05-02"
        task.scheduledStartMin = 540
        task.calendarEventID = "event-1"
        let bundle = TaskBundle(title: "Admin sweep", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)

        SchedulingActions.addTask(task, to: bundle)

        #expect(task.bundle?.id == bundle.id)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
        #expect(task.calendarEventID.isEmpty)
        #expect(bundle.sortedTasks.map(\.id) == [task.id])
    }

    @Test func reassigningTaskBetweenBundlesRemovesOldMembership() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Tiny thing")
        let first = TaskBundle(title: "First", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        let second = TaskBundle(title: "Second", dateKey: "2026-05-02", startMin: 900, durationMinutes: 45)
        context.insert(task)
        context.insert(first)
        context.insert(second)

        SchedulingActions.addTask(task, to: first)
        SchedulingActions.addTask(task, to: second)

        #expect(task.bundle?.id == second.id)
        #expect(task.scheduledDate == "2026-05-02")
        #expect(first.sortedTasks.isEmpty)
        #expect(second.sortedTasks.map(\.id) == [task.id])
    }

    @Test func droppingBundledTaskOntoTimelineRemovesBundleMembership() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Pull report")
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.dropTask(task, to: "2026-05-03", startMin: 720)

        #expect(task.bundle == nil)
        #expect(bundle.sortedTasks.isEmpty)
        #expect(task.scheduledDate == "2026-05-03")
        #expect(task.scheduledStartMin == 720)
    }

    @Test func deletingBundleKeepsTasksOnBundleDate() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Keep me")
        let bundle = TaskBundle(title: "Delete me", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.deleteBundle(bundle, in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
    }

    @Test func deletingBundleAlsoDetachesCancelledHiddenMembers() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Hidden member")
        task.status = .cancelled
        let bundle = TaskBundle(title: "Delete me", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.deleteBundle(bundle, in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
    }

    @Test func completingBundleMarksMemberTasksDoneAndRemovesBundle() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        let bundle = TaskBundle(title: "Finish me", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        [first, second].forEach(context.insert)
        context.insert(bundle)
        [first, second].forEach { SchedulingActions.addTask($0, to: bundle) }

        SchedulingActions.completeBundle(bundle, in: context)

        #expect(first.isDone)
        #expect(second.isDone)
        #expect(first.completedAt != nil)
        #expect(second.completedAt != nil)
        #expect(first.bundle == nil)
        #expect(second.bundle == nil)
        #expect(first.scheduledDate == "2026-05-01")
        #expect(first.scheduledStartMin == -1)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    @Test func rollingOverLastActiveBundledTaskDetachesItAndRemovesOldBundle() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Carry me")
        let bundle = TaskBundle(title: "Yesterday", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.rollOverTaskToToday(task, todayKey: "2026-05-02", in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-02")
        #expect(task.scheduledStartMin == -1)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    @Test func rollingOverOneBundledTaskKeepsBundleWhenOtherActiveTasksRemain() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "Carry me")
        let second = AppTask(title: "Stay bundled")
        let bundle = TaskBundle(title: "Yesterday", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        [first, second].forEach(context.insert)
        context.insert(bundle)
        [first, second].forEach { SchedulingActions.addTask($0, to: bundle) }

        SchedulingActions.rollOverTaskToToday(first, todayKey: "2026-05-02", in: context)

        #expect(first.bundle == nil)
        #expect(first.scheduledDate == "2026-05-02")
        #expect(first.scheduledStartMin == -1)
        #expect(second.bundle?.id == bundle.id)
        #expect(bundle.sortedTasks.map(\.id) == [second.id])
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).map(\.id) == [bundle.id])
    }

    @Test func removingTaskFromBundleKeepsItOnBundleDateWithoutCalendarSlot() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Loose item")
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.removeTaskFromBundle(task)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
        #expect(bundle.sortedTasks.isEmpty)
    }

    @Test func bundleOrderCanBeChangedManually() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        let third = AppTask(title: "Third")
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        [first, second, third].forEach(context.insert)
        context.insert(bundle)
        [first, second, third].forEach { SchedulingActions.addTask($0, to: bundle) }

        SchedulingActions.moveTaskInBundle(third, direction: -1)

        #expect(bundle.sortedTasks.map(\.title) == ["First", "Third", "Second"])
        #expect(bundle.sortedTasks.map(\.bundleOrder) == [0, 1, 2])
    }

    @Test func creatingBundleFromTwoTimedTasksUsesTargetSlotAndMembersLoseIndividualTimes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = AppTask(title: "A")
        target.scheduledDate = "2026-05-01"
        target.scheduledStartMin = 600
        target.estimatedMinutes = 25
        let dragged = AppTask(title: "B")
        dragged.scheduledDate = "2026-05-01"
        dragged.scheduledStartMin = 630
        dragged.estimatedMinutes = 10
        context.insert(target)
        context.insert(dragged)

        let bundle = try #require(SchedulingActions.createBundle(from: target, adding: dragged, in: context))

        #expect(bundle.dateKey == "2026-05-01")
        #expect(bundle.startMin == 600)
        #expect(bundle.durationMinutes == 35)
        #expect(bundle.sortedTasks.map(\.title) == ["A", "B"])
        #expect(target.scheduledDate == "2026-05-01")
        #expect(target.scheduledStartMin == -1)
        #expect(dragged.scheduledDate == "2026-05-01")
        #expect(dragged.scheduledStartMin == -1)
    }

    @Test func unbundlingKeepsTasksOnBundleDateAndPreservesListMetadata() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "General", colorHex: "#8b5cf6", icon: "globe")
        let tag = Tag(name: "enhancement", colorHex: "#22c55e")
        let task = AppTask(title: "Keep metadata")
        task.area = area
        task.sectionName = "Backlog"
        task.dueDate = "2026-05-10"
        task.notes = "Original notes"
        task.tags = [tag]
        task.order = 42
        task.priority = .high
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(area)
        context.insert(tag)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.unbundle(bundle, in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
        #expect(task.area?.id == area.id)
        #expect(task.sectionName == "Backlog")
        #expect(task.dueDate == "2026-05-10")
        #expect(task.notes == "Original notes")
        #expect(task.tags?.map(\.id) == [tag.id])
        #expect(task.order == 42)
        #expect(task.priority == .high)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    @Test func bundleTimesAreClampedInsideOneDay() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = SchedulingActions.createBundle(title: "", dateKey: "2026-05-01", startMin: 1438, endMin: 1510, in: context)

        #expect(bundle.title == "Task Bundle")
        #expect(bundle.startMin == 1435)
        #expect(bundle.durationMinutes == 5)
        #expect(bundle.endMin == 1440)
    }

    /// `AppTask.calendarEventID` is documented as write-only-empty: attaching a task to a calendar
    /// event is not a feature that exists, the readers that remain are there to *clear* values an
    /// earlier build left on disk, and the field survives only because removing a stored SwiftData
    /// property with no migration plan would drop data. That invariant was held purely by
    /// convention — nothing asserted it, so the first entry point to start writing an identifier
    /// would have reintroduced half a feature silently.
    @Test func noSchedulingEntryPointEverGivesATaskACalendarEventID() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Ops")
        context.insert(area)

        // 1. Drag-to-create on the timeline, with no container.
        SchedulingActions.createTask(title: "Dragged out", dateKey: "2026-05-01", startMin: 600, endMin: 660, in: context)
        // 2. Drag-to-create routed into a list/section through the quick popover.
        SchedulingActions.createTask(
            title: "Dragged into a list",
            dateKey: "2026-05-01",
            startMin: 700,
            endMin: 760,
            containerSelection: .area(area.id),
            sectionName: TaskSectionDefaults.defaultName,
            areas: [area],
            projects: [],
            in: context
        )
        // 3. The shared creation sheet / quick capture path.
        TaskCreationService(areas: [area], projects: []).insertTask(
            from: TaskCreationDraft(
                title: "From the sheet",
                notes: "",
                priority: .none,
                container: .area(area.id),
                sectionName: TaskSectionDefaults.defaultName,
                dueDateKey: "",
                scheduledDateKey: "2026-05-01",
                subtaskTitles: [],
                tags: [],
                scheduledStartMin: 800
            ),
            into: context
        )
        // 4. The generic scheduled-insert helper the shared surfaces use.
        _ = try CadenceTaskMutationSupport.insertScheduledTask(
            title: "Inserted",
            allTasks: try context.fetch(FetchDescriptor<AppTask>()),
            modelContext: context,
            scheduledDate: "2026-05-01",
            scheduledStartMin: 900,
            estimatedMinutes: 30
        )

        let created = try context.fetch(FetchDescriptor<AppTask>())
        #expect(created.count == 4)
        #expect(created.allSatisfy { $0.calendarEventID.isEmpty })

        // And every path that *moves* a task must clear an identifier an older build left behind,
        // rather than carrying it onto the new slot.
        func stale(_ title: String) -> AppTask {
            let task = AppTask(title: title)
            task.scheduledDate = "2026-05-01"
            task.scheduledStartMin = 540
            task.estimatedMinutes = 30
            task.calendarEventID = "legacy-event-id"
            context.insert(task)
            return task
        }

        let rolled = stale("Rolled over")
        SchedulingActions.rollOverTaskToToday(rolled, todayKey: "2026-05-02", in: context)
        #expect(rolled.calendarEventID.isEmpty)

        let detached = stale("Detached")
        SchedulingActions.removeFromCalendar(detached)
        #expect(detached.calendarEventID.isEmpty)

        let bundled = stale("Bundled")
        let bundle = SchedulingActions.createBundle(title: "Sweep", dateKey: "2026-05-01", startMin: 600, endMin: 660, in: context)
        SchedulingActions.addTask(bundled, to: bundle)
        #expect(bundled.calendarEventID.isEmpty)

        let moved = stale("Moved with its bundle")
        moved.calendarEventID = "legacy-event-id"
        SchedulingActions.addTask(moved, to: bundle)
        moved.calendarEventID = "legacy-event-id" // re-arm: the move below is the site under test
        SchedulingActions.dropBundle(bundle, to: "2026-05-03", startMin: 660)
        #expect(moved.calendarEventID.isEmpty)

        let unbundled = stale("Unbundled")
        SchedulingActions.addTask(unbundled, to: bundle)
        unbundled.calendarEventID = "legacy-event-id"
        SchedulingActions.unbundle(bundle, in: context)
        #expect(unbundled.calendarEventID.isEmpty)

        // Duplicating must not hand a second task the same event identifier.
        let source = stale("Original")
        let copy = try CadenceTaskMutationSupport.duplicate(
            source,
            allTasks: try context.fetch(FetchDescriptor<AppTask>()),
            modelContext: context
        )
        #expect(copy.calendarEventID.isEmpty)
    }

    @Test func bundleFocusLoggingDistributesByEstimate() throws {
        let short = AppTask(title: "Short")
        short.estimatedMinutes = 10
        let long = AppTask(title: "Long")
        long.estimatedMinutes = 20

        FocusSessionSupport.distributeBundleMinutes(30, across: [short, long])

        #expect(short.actualMinutes == 10)
        #expect(long.actualMinutes == 20)
    }
}
#endif
