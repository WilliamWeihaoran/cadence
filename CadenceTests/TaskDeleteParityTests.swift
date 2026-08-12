import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Deleting a task used to mean two different things depending on which app you were holding.
/// macOS went through `ModelContext.deleteTasks(withIDs:)`; iOS's only delete path was
/// `CadenceTaskMutationSupport.delete`, which disposed of no emptied bundle, detached no
/// relationships, cancelled no pending notification, and fed the recurrence repair from
/// `(try? fetch(…)) ?? []`.
///
/// They are now one implementation with two thin platform wrappers. These tests pin the
/// behaviours that were missing, and — on macOS — that both entry points leave the store in the
/// same state.
@MainActor
struct TaskDeleteParityTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    // MARK: - Bundles

    /// Deleting the last member of a bundle must dispose of the bundle.
    /// `CadenceCalendarPlanningSupport.bundlesByDate` does not filter empty bundles, so a survivor
    /// renders an empty block on the Mac timeline indefinitely.
    @Test func deletingTheLastTaskInABundleDisposesOfTheBundle() throws {
        let modelContext = try makeContext()

        let bundle = TaskBundle(title: "Morning block", dateKey: "2026-08-11", startMin: 540, durationMinutes: 60)
        let task = AppTask(title: "Only member")
        task.bundle = bundle
        bundle.tasks = [task]
        modelContext.insert(bundle)
        modelContext.insert(task)
        try modelContext.save()

        CadenceTaskMutationSupport.delete(task, modelContext: modelContext)

        #expect(try modelContext.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    /// The other half of the same rule: a bundle that still has members must survive, and the
    /// survivors must keep their membership.
    @Test func deletingOneOfSeveralBundledTasksKeepsTheBundle() throws {
        let modelContext = try makeContext()

        let bundle = TaskBundle(title: "Morning block", dateKey: "2026-08-11", startMin: 540, durationMinutes: 60)
        let doomed = AppTask(title: "Doomed")
        let survivor = AppTask(title: "Survivor")
        doomed.bundle = bundle
        survivor.bundle = bundle
        bundle.tasks = [doomed, survivor]
        modelContext.insert(bundle)
        modelContext.insert(doomed)
        modelContext.insert(survivor)
        try modelContext.save()

        CadenceTaskMutationSupport.delete(doomed, modelContext: modelContext)

        let bundles = try modelContext.fetch(FetchDescriptor<TaskBundle>())
        #expect(bundles.count == 1)
        #expect(bundles.first?.tasks?.map(\.title) == ["Survivor"])
    }

    // MARK: - Recurrence

    /// A mid-series occurrence's predecessor must stop believing it has a live successor, or the
    /// series silently stalls: nothing ever spawns the next occurrence.
    @Test func deletingAMidSeriesOccurrenceRepairsThePredecessorLink() throws {
        let modelContext = try makeContext()

        let seriesID = UUID()
        let first = AppTask(title: "Water plants")
        first.recurrenceRule = .weekly
        first.recurrenceSeriesIDRaw = seriesID.uuidString
        let second = AppTask(title: "Water plants")
        second.recurrenceRule = .weekly
        second.recurrenceSeriesIDRaw = seriesID.uuidString
        second.recurrenceSourceTaskID = first.id
        first.recurrenceSpawnedTaskID = second.id

        modelContext.insert(first)
        modelContext.insert(second)
        try modelContext.save()

        CadenceTaskMutationSupport.delete(second, modelContext: modelContext)

        let remaining = try modelContext.fetch(FetchDescriptor<AppTask>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.recurrenceSpawnedTaskID == nil)
    }

    // MARK: - Cascade and detachment

    @Test func deletingATaskRemovesItsSubtasksAndLeavesNoOrphans() throws {
        let modelContext = try makeContext()

        let task = AppTask(title: "Plan trip")
        let flight = Subtask(title: "Book flight")
        flight.parentTask = task
        let hotel = Subtask(title: "Book hotel")
        hotel.parentTask = task
        modelContext.insert(task)
        modelContext.insert(flight)
        modelContext.insert(hotel)
        try modelContext.save()

        CadenceTaskMutationSupport.delete(task, modelContext: modelContext)

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
    }

    /// `AppTask.calendarEventID` has no writer any more, but rows written by an earlier build can
    /// still carry one. The delete path clears it rather than leaving a dangling identifier
    /// mid-teardown.
    @Test func deletingATaskClearsALegacyCalendarEventIdentifier() throws {
        let modelContext = try makeContext()

        let task = AppTask(title: "Standup")
        task.calendarEventID = "legacy-event-id"
        modelContext.insert(task)
        try modelContext.save()

        CadenceTaskMutationSupport.detachRelationships(for: task)

        #expect(task.calendarEventID.isEmpty)
    }

    // MARK: - Contract

    @Test func deletingAnEmptyIDSetSucceedsWithoutTouchingAnything() throws {
        let modelContext = try makeContext()

        let task = AppTask(title: "Untouched")
        modelContext.insert(task)
        try modelContext.save()

        #expect(CadenceTaskMutationSupport.deleteTasks(withIDs: [], modelContext: modelContext))
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    /// The teardown hook must not fire when the delete turns out to be a no-op. On macOS it tears
    /// down focus/hover/subtask-entry state, and the cascade callers proceed regardless of whether
    /// any task actually matched.
    @Test func theTeardownHookOnlyFiresWhenThereIsRealWorkToDo() throws {
        let modelContext = try makeContext()

        var firedFor: [Set<UUID>] = []
        let missing = UUID()

        #expect(
            CadenceTaskMutationSupport.deleteTasks(
                withIDs: [missing],
                modelContext: modelContext,
                willDelete: { firedFor.append($0) }
            )
        )
        #expect(firedFor.isEmpty)

        let task = AppTask(title: "Real")
        modelContext.insert(task)
        try modelContext.save()

        CadenceTaskMutationSupport.deleteTasks(
            withIDs: [task.id],
            modelContext: modelContext,
            willDelete: { firedFor.append($0) }
        )
        #expect(firedFor == [[task.id]])
    }

    /// The bundle-disposal hook is how macOS learns that the focus session's bundle just went
    /// away. It reports exactly the bundles that were deleted.
    @Test func theBundleDisposalHookReportsTheBundlesItDeleted() throws {
        let modelContext = try makeContext()

        let emptied = TaskBundle(title: "Emptied", dateKey: "2026-08-11", startMin: 540, durationMinutes: 60)
        let kept = TaskBundle(title: "Kept", dateKey: "2026-08-11", startMin: 660, durationMinutes: 60)
        let only = AppTask(title: "Only member")
        only.bundle = emptied
        emptied.tasks = [only]
        let doomed = AppTask(title: "Doomed")
        let survivor = AppTask(title: "Survivor")
        doomed.bundle = kept
        survivor.bundle = kept
        kept.tasks = [doomed, survivor]

        for model in [emptied, kept, only, doomed, survivor] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        var reported = Set<UUID>()
        CadenceTaskMutationSupport.deleteTasks(
            withIDs: [only.id, doomed.id],
            modelContext: modelContext,
            didDeleteBundles: { reported = $0 }
        )

        #expect(reported == [emptied.id])
    }

    // MARK: - Cross-platform parity

    #if os(macOS)
    /// The parity assertion proper: deleting an identically-shaped task through each entry point
    /// leaves an identically-shaped store.
    @Test func bothPlatformDeletePathsLeaveTheSameStore() throws {
        func seedAndDelete(_ delete: (AppTask, ModelContext) -> Void) throws -> (tasks: Int, subtasks: Int, bundles: Int, spawned: UUID?) {
            let modelContext = try makeContext()

            let bundle = TaskBundle(title: "Block", dateKey: "2026-08-11", startMin: 540, durationMinutes: 60)
            let seriesID = UUID()
            let predecessor = AppTask(title: "Water plants")
            predecessor.recurrenceRule = .weekly
            predecessor.recurrenceSeriesIDRaw = seriesID.uuidString

            let doomed = AppTask(title: "Water plants")
            doomed.recurrenceRule = .weekly
            doomed.recurrenceSeriesIDRaw = seriesID.uuidString
            doomed.recurrenceSourceTaskID = predecessor.id
            predecessor.recurrenceSpawnedTaskID = doomed.id
            doomed.bundle = bundle
            doomed.calendarEventID = "legacy-event-id"
            bundle.tasks = [doomed]

            let step = Subtask(title: "Fill the can")
            step.parentTask = doomed

            for model in [bundle, predecessor, doomed, step] as [any PersistentModel] {
                modelContext.insert(model)
            }
            try modelContext.save()

            delete(doomed, modelContext)
            try modelContext.save()

            return (
                tasks: try modelContext.fetch(FetchDescriptor<AppTask>()).count,
                subtasks: try modelContext.fetch(FetchDescriptor<Subtask>()).count,
                bundles: try modelContext.fetch(FetchDescriptor<TaskBundle>()).count,
                spawned: try modelContext.fetch(FetchDescriptor<AppTask>()).first?.recurrenceSpawnedTaskID
            )
        }

        let shared = try seedAndDelete { task, modelContext in
            CadenceTaskMutationSupport.delete(task, modelContext: modelContext)
        }
        let mac = try seedAndDelete { task, modelContext in
            modelContext.deleteTask(task)
        }

        #expect(shared == mac)
        #expect(shared.tasks == 1)
        #expect(shared.subtasks == 0)
        #expect(shared.bundles == 0)
        #expect(shared.spawned == nil)
    }
    #endif
}
