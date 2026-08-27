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

    // MARK: - A refused commit (T-365)

    /// `ModelContext.save()` cannot be made to throw out of an in-memory container, which is why
    /// `deleteTasks` takes its commit as a parameter — the same seam, for the same reason, that
    /// `CadencePendingChangePersistence` documents.
    private struct DeleteCommitRefused: Error {}

    private func refuseTheCommit(_ modelContext: ModelContext) throws {
        throw DeleteCommitRefused()
    }

    /// T-365, the failure half. The delete used to end in `try? modelContext.save()` and `return
    /// true`, so a refused commit was indistinguishable from a real deletion: the rows stayed
    /// marked deleted in the context the list reads from, present in the store the next launch
    /// reads from, and both platforms reported success over it.
    ///
    /// Everything the sweep marked comes back, not just the task — the subtask it unlinked and the
    /// bundle it disposed of are part of the same pending change, and one `rollback()` is what
    /// makes `deleteFailureNotice`'s "Nothing was removed" true rather than approximately true.
    @Test func arefusedTaskDeleteKeepsTheTaskAndReportsFailure() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let bundle = TaskBundle(title: "Block", dateKey: "2026-08-11", startMin: 540, durationMinutes: 60)
        let task = AppTask(title: "Still here")
        task.bundle = bundle
        bundle.tasks = [task]
        let step = Subtask(title: "Its only step")
        step.parentTask = task
        for model in [bundle, task, step] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        let reported = CadenceTaskMutationSupport.delete(
            task,
            modelContext: modelContext,
            commit: refuseTheCommit
        )

        #expect(reported == false, "a delete whose commit was refused reported success")
        #expect(!modelContext.hasChanges, "the refused delete was left pending in the context")
        #expect(
            try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Still here"],
            "the row is hidden from the list and undeleted in the store — the worst of both"
        )
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<TaskBundle>()).count == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Still here"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<Subtask>()).count == 1)
    }

    /// The success half, unchanged by the fix and asserted from a second context: an ordinary
    /// delete still commits itself, because a task swiped away has no enclosing unit of work to
    /// ride and a delete left waiting on autosave is lost by a quit.
    @Test func anOrdinaryTaskDeleteCommitsToTheStoreAndReportsSuccess() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Going away")
        let step = Subtask(title: "Its only step")
        step.parentTask = task
        modelContext.insert(task)
        modelContext.insert(step)
        try modelContext.save()

        #expect(CadenceTaskMutationSupport.delete(task, modelContext: modelContext))

        #expect(!modelContext.hasChanges, "the delete was left pending in the context")
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Subtask>()).isEmpty)
    }

    /// Where the commit goes, and what a refused one skips.
    ///
    /// Two things this target cannot reach behaviourally. The commit is one line inside a function
    /// whose other twenty `try? modelContext.save()` neighbours are not this ticket's, so the
    /// needle is scoped by the gate it sits in rather than counted file-wide. The notification
    /// cancellation is a `Task` against a real `UNUserNotificationCenter`, so its *position* is
    /// what can be pinned: it follows the commit, and the failure branch returns before reaching
    /// it — a delete that promises it removed nothing must not have cancelled the reminder either.
    @Test func theSharedDeleteCommitsThroughThePendingChangeSpineAndCancelsOnlyOnSuccess() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift")
        #expect(raw.count > 400, "the delete core read as \(raw.count) characters")
        let core = CadenceSourceScan.strippingComments(raw)
        #expect(core != raw, "the comment stripper removed nothing")
        #expect(core.count == raw.count, "the stripper changed the length")
        #expect(core.contains("static func deleteTasks("), "the shared task-deletion core moved")

        let spineCommit = #"if commitsImmediately \{\s*do \{\s*try CadencePendingChangePersistence\.commitDelete\(in: modelContext, commit: commit\)\s*\} catch \{\s*return false"#
        #expect(
            CadenceSourceScan.matchCount(spineCommit, in: core) == 1,
            "the ordinary delete no longer commits through the spine that rolls back"
        )
        #expect(
            CadenceSourceScan.matchCount(#"try\? modelContext\.save\(\)\s*\}\s*Task \{ await NotificationManager"#, in: core) == 0,
            "the swallowed save T-365 removed is back"
        )

        let cancelsAfterTheCommit = #"catch \{\s*return false\s*\}\s*\}\s*Task \{ await NotificationManager\.shared\.cancel\(taskIDs: Array\(taskIDs\)\) \}\s*return true"#
        #expect(
            CadenceSourceScan.matchCount(cancelsAfterTheCommit, in: core) == 1,
            "a refused delete now cancels the reminder for a task it just put back"
        )

        // Both needles against the spellings they must and must not accept.
        #expect(
            CadenceSourceScan.matchCount(
                spineCommit,
                in: "if commitsImmediately {\n            do {\n                try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: commit)\n            } catch {\n                return false\n            }\n        }"
            ) == 1,
            "the commit needle does not match the spelling it is hunting"
        )
        #expect(
            CadenceSourceScan.matchCount(
                spineCommit,
                in: "if commitsImmediately {\n            try? modelContext.save()\n        }"
            ) == 0,
            "the commit needle accepts the swallowed save"
        )
        #expect(
            CadenceSourceScan.matchCount(
                cancelsAfterTheCommit,
                in: "catch {\n                return false\n            }\n        }\n\n        Task { await NotificationManager.shared.cancel(taskIDs: Array(taskIDs)) }\n        return true"
            ) == 1,
            "the ordering needle does not match the spelling it is hunting"
        )
        #expect(
            CadenceSourceScan.matchCount(
                cancelsAfterTheCommit,
                in: "if commitsImmediately {\n            try? modelContext.save()\n        }\n\n        Task { await NotificationManager.shared.cancel(taskIDs: Array(taskIDs)) }\n        return true"
            ) == 0,
            "the ordering needle passes on a delete that cancels whatever happened"
        )
    }

    /// One sentence, four objects. The task notice is worded from the same template the three
    /// deletes that could already fail use, and it earns the second half the same way: the commit
    /// rolls back, so the row is back where the user can see it.
    @Test func theTaskDeleteFailureNoticeMakesTheSamePromiseAsItsThreeNeighbours() {
        #expect(CadenceTaskMutationSupport.deleteFailureNotice
                == "Couldn't delete this task. Nothing was removed.")
        #expect(CadenceTaskMutationSupport.deleteFailureNotice.contains("Nothing was removed"))

        let notices = CadenceListDeletionKind.allCases.map(\.deleteFailureNotice)
            + [CadenceNoteDeletionSummary.deleteFailureNotice, CadenceTaskMutationSupport.deleteFailureNotice]
        #expect(Set(notices).count == notices.count, "two screens name the same object")
    }

    /// The iOS half of "propagate the failure", which this target builds on macOS and so cannot
    /// call. The row's `deleteTask()` used to discard the result; it reads it now, and the second
    /// alert is where the sentence lands — an alert dismisses itself on the button tap, so the
    /// row cannot stay open and say why the way the note and list sheets do.
    @Test func theIOSRowReportsADeleteThatDidNotLand() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift")
        #expect(raw.count > 400, "the iOS row read as \(raw.count) characters")
        let row = CadenceSourceScan.strippingComments(raw)
        #expect(row != raw, "the comment stripper removed nothing")
        #expect(row.count == raw.count, "the stripper changed the length")
        #expect(row.contains("struct iOSTaskRow: View"), "the iOS row moved")

        let deleteTask = try #require(
            CadenceSourceScan.functionBody(named: "deleteTask", in: row),
            "iOSTaskViews.swift has no deleteTask()"
        )
        #expect(
            deleteTask.contains("deleteFailed = !CadenceTaskMutationSupport.delete(task, modelContext: modelContext)"),
            "the row still throws away the delete's answer"
        )
        #expect(row.contains("@State private var deleteFailed = false"))
        #expect(
            row.contains(#".alert("Couldn't Delete Task", isPresented: $deleteFailed)"#),
            "the row has nowhere to report a failed delete"
        )
        #expect(
            row.contains("Text(CadenceTaskMutationSupport.deleteFailureNotice)"),
            "the row words the failure itself instead of reading the shared sentence"
        )
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

    /// The macOS side of "propagate the failure". `ModelContext.deleteTask(_:)` returned `Void`,
    /// so the five macOS surfaces that call it had no answer to read even in principle — the
    /// shared core's `false` stopped at the wrapper. It is a `Bool` now, and this is the whole
    /// journey: refuse the commit at the bottom, read the failure at the top, and find the task
    /// still there.
    @Test func themacOSDeleteWrapperHandsARefusedCommitBackToItsCaller() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Still here")
        modelContext.insert(task)
        try modelContext.save()

        #expect(modelContext.deleteTask(task, commit: refuseTheCommit) == false)
        #expect(!modelContext.hasChanges)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Still here"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Still here"])

        // And the ordinary path through the same wrapper still lands. Re-fetched rather than
        // reusing the reference above, because the rollback is what put that row back and the
        // object the list would be holding after one is the one the store hands out now.
        let restored = try #require(modelContext.fetch(FetchDescriptor<AppTask>()).first)
        #expect(modelContext.deleteTask(restored))
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }
    #endif
}
