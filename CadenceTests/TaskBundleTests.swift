import SwiftData
import Testing
@testable import Cadence

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
        #expect(bundle.durationMinutes == 25)
        #expect(bundle.sortedTasks.map(\.title) == ["A", "B"])
        #expect(target.scheduledDate == "2026-05-01")
        #expect(target.scheduledStartMin == -1)
        #expect(dragged.scheduledDate == "2026-05-01")
        #expect(dragged.scheduledStartMin == -1)
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
