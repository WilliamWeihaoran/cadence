import Foundation
import SwiftData
import Testing
@testable import Cadence

/// One question asked twice: is `Subtask.parentTask` trustworthy at the moment somebody reads it?
///
/// `CadenceTaskMutationSupport.deleteTasks` already answers "no" — it writes `subtask.parentTask = nil`
/// before deleting rather than letting SwiftData tear the inverse down on its own. T-296 and T-294
/// are the two places that answered "yes": two surfaces deleted a subtask without severing either
/// side, and the recurrence spawn built its subtask copies with only the parent's array assigned.
///
/// Every behavioural assertion below reads through a **second `ModelContext` on the same container**.
/// A first-context read cannot tell "the inverse is in the store" from "the inverse is a pointer
/// this context happens to be holding", which is the entire distinction both tickets turn on.
@MainActor
struct CadenceSubtaskInverseParityTests {
    private func makeContainer() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    private func fetchSubtasks(in container: ModelContainer) throws -> [Subtask] {
        try ModelContext(container).fetch(FetchDescriptor<Subtask>())
    }

    // MARK: - T-296: one shared subtask delete

    /// The shared helper must leave the store with no row *and* no surviving back-reference, and
    /// must not take the sibling with it.
    @Test func deletingASubtaskThroughTheSharedHelperLeavesNoRowAndNoBackReference() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Pack for the trip")
        let doomed = Subtask(title: "Find the passport")
        doomed.order = 0
        let survivor = Subtask(title: "Charge the camera")
        survivor.order = 1
        task.subtasks = [doomed, survivor]
        doomed.parentTask = task
        survivor.parentTask = task
        modelContext.insert(task)
        try modelContext.save()

        // Non-vacuity: the fixture really is two persisted subtasks before anything is deleted.
        #expect(try fetchSubtasks(in: container).count == 2)

        CadenceTaskMutationSupport.deleteSubtask(doomed, parent: task, modelContext: modelContext)

        // Read before any flush. This is the moment the surface that just called the helper
        // re-renders its subtask list from `task.subtasks`, and it is the only moment where the
        // strict path and the loose one differ: `modelContext.delete` alone leaves the deleted row
        // in the parent's array until `processPendingChanges` reconciles the inverse, so the row is
        // drawn from a model object that is already gone. Severing both sides by hand is what makes
        // the array correct immediately rather than eventually.
        #expect((task.subtasks ?? []).map(\.title) == ["Charge the camera"])

        modelContext.processPendingChanges()
        try modelContext.save()

        let remaining = try fetchSubtasks(in: container)
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Charge the camera")
        // The survivor keeps its own back-reference: the detach was aimed at one row, not the pair.
        #expect(remaining.first?.parentTask?.id == task.id)

        guard let storedTask = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first(where: { $0.id == task.id }) else {
            Issue.record("The parent task itself should have survived a subtask delete")
            return
        }
        #expect((storedTask.subtasks ?? []).map(\.title) == ["Charge the camera"])
    }

    /// The unpropagated-inverse case the helper exists for. macOS's `addSubtask` writes only
    /// `subtask.parentTask = task` and never appends to `task.subtasks`, so a caller that trusts the
    /// parent's array to know its own children is trusting back-population. Passing the owner in
    /// explicitly has to work when the array has not learned about the child yet.
    @Test func theSharedHelperDetachesASubtaskItsParentArrayNeverLearnedAbout() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Ship the release")
        modelContext.insert(task)
        let orphanedSide = Subtask(title: "Tag the build")
        orphanedSide.parentTask = task
        modelContext.insert(orphanedSide)
        try modelContext.save()

        #expect(try fetchSubtasks(in: container).count == 1)

        CadenceTaskMutationSupport.deleteSubtask(orphanedSide, parent: task, modelContext: modelContext)

        // Again before the flush: the owner was supplied by the caller rather than read back off
        // `subtask.parentTask`, and the parent's array must be right the instant the call returns.
        #expect((task.subtasks ?? []).isEmpty)

        modelContext.processPendingChanges()
        try modelContext.save()

        #expect(try fetchSubtasks(in: container).isEmpty)
        guard let storedTask = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first(where: { $0.id == task.id }) else {
            Issue.record("The parent task itself should have survived a subtask delete")
            return
        }
        #expect((storedTask.subtasks ?? []).isEmpty)
    }

    /// The two surfaces that used to open-code the delete now route through the shared helper.
    ///
    /// Source-scanned rather than called: both are `private func`s inside SwiftUI views, and
    /// `Cadence/iOS/` is not compiled into this macOS test target at all.
    @Test func theTwoSubtaskDeleteCallSitesRouteThroughTheSharedHelper() throws {
        let callSites = [
            "Cadence/iOS/iOSTaskDetailSheet.swift": "private func deleteSubtask(_ subtask: Subtask) {",
            "Cadence/macOS/Views/SchedulePanelComponents.swift": "onDeleteSubtask: { subtask in"
        ]

        for (relativePath, anchor) in callSites {
            let raw = try subtaskSourceFile(relativePath)
            let code = strippingSwiftComments(raw)

            // Non-vacuity: a missing or empty read, and a stripper that silently did nothing or
            // changed the file's length, all have to be red rather than quietly green.
            #expect(raw.count > 500, "\(relativePath) read back as \(raw.count) characters")
            #expect(code != raw, "\(relativePath) has no comments to strip; the stripper did nothing")
            #expect(code.count == raw.count, "\(relativePath) changed length under the stripper")
            #expect(code.contains(anchor), "\(relativePath) no longer contains \(anchor)")

            let routed = occurrences(
                of: "CadenceTaskMutationSupport.deleteSubtask(subtask, parent: task, modelContext: modelContext)",
                in: code
            )
            #expect(routed == 1, "\(relativePath) routes through the shared helper \(routed) times, expected 1")

            let openCoded = occurrences(of: "modelContext.delete(subtask)", in: code)
            #expect(openCoded == 0, "\(relativePath) still deletes a subtask directly \(openCoded) times")
        }
    }

    // MARK: - T-294: recurrence copies own their back-reference

    /// The assertion the old recurrence test could not make. It read `next.subtasks` — the parent's
    /// array, which the spawn assigns by hand — so it stayed green whether or not the inverse was
    /// ever written. This fetches the `Subtask` rows themselves, from a second context, and reads
    /// `parentTask`.
    @Test func recurrenceCopiesCarryTheirParentBackReferenceIntoTheStore() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Water the plants")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-08-04"
        let first = Subtask(title: "Kitchen windowsill")
        first.order = 0
        let second = Subtask(title: "Balcony pots")
        second.order = 1
        task.subtasks = [first, second]
        first.parentTask = task
        second.parentTask = task
        modelContext.insert(task)
        try modelContext.save()

        let originalIDs = Set([first.id, second.id])

        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        modelContext.processPendingChanges()
        try modelContext.save()

        guard let spawnedID = task.recurrenceSpawnedTaskID else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        #expect(spawnedID != task.id)

        let stored = try fetchSubtasks(in: container)
        #expect(stored.count == 4)

        let copies = stored.filter { !originalIDs.contains($0.id) }
        #expect(copies.count == 2)
        #expect(copies.map(\.title).sorted() == ["Balcony pots", "Kitchen windowsill"])
        // The point of the ticket: read the copy's own field, not the parent's array.
        #expect(copies.allSatisfy { $0.parentTask?.id == spawnedID })

        // And the originals still belong to the occurrence that was completed.
        let originals = stored.filter { originalIDs.contains($0.id) }
        #expect(originals.count == 2)
        #expect(originals.allSatisfy { $0.parentTask?.id == task.id })
    }

    /// The invariant itself, scanned rather than measured — and deliberately so.
    ///
    /// Measured, there is nothing to see: by the time the spawned occurrence reaches the store,
    /// SwiftData has back-populated `parentTask` on every copy on its own, so the test above passes
    /// with or without the explicit write (verified by mutation). The write is not there because
    /// the store currently needs it; it is there because every other subtask path in this codebase
    /// declines to depend on that back-population — `deleteTasks` nils the inverse before deleting,
    /// and `deleteSubtask` severs both sides — and one path quietly trusting it is how the two
    /// answers drift apart again. That makes this a convention with no observable consequence, which
    /// is exactly the kind of thing only a scan can hold.
    @Test func theRecurrenceSpawnWritesBothSidesOfTheSubtaskInverse() throws {
        let relativePath = "Cadence/Shared/CadenceTaskRecurrenceWorkflowSupport.swift"
        let raw = try subtaskSourceFile(relativePath)
        let code = strippingSwiftComments(raw)

        #expect(raw.count > 500, "\(relativePath) read back as \(raw.count) characters")
        #expect(code != raw, "\(relativePath) has no comments to strip; the stripper did nothing")
        #expect(code.count == raw.count, "\(relativePath) changed length under the stripper")
        #expect(code.contains("nextTask.subtasks = copies"), "the spawn no longer assigns the copies to the parent")

        let inverseWrites = occurrences(of: "copy.parentTask = nextTask", in: code)
        #expect(inverseWrites == 1, "the spawn writes the subtask inverse \(inverseWrites) times, expected 1")
    }

    /// Why the back-reference matters rather than being cosmetic. `Subtask.parentTask` has SwiftData's
    /// default nullify rule, so deleting a task does not take its subtasks with it — the shared
    /// delete path finds them by fetching every `Subtask` and matching `parentTask`. A copy the
    /// inverse never reached is a row that sweep cannot see, left behind forever.
    @Test func theSharedDeleteSweepFindsRecurrenceCopiesByTheirParentBackReference() throws {
        let container = try makeContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Weekly review")
        task.recurrenceRule = .weekly
        task.scheduledDate = "2026-08-04"
        let step = Subtask(title: "Clear the inbox")
        step.order = 0
        task.subtasks = [step]
        step.parentTask = task
        modelContext.insert(task)
        try modelContext.save()

        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        modelContext.processPendingChanges()
        try modelContext.save()

        guard let spawnedID = task.recurrenceSpawnedTaskID else {
            Issue.record("Expected a spawned next occurrence")
            return
        }
        #expect(try fetchSubtasks(in: container).count == 2)

        #expect(CadenceTaskMutationSupport.deleteTasks(withIDs: [spawnedID], modelContext: modelContext))

        let survivors = try fetchSubtasks(in: container)
        #expect(survivors.count == 1)
        #expect(survivors.first?.parentTask?.id == task.id)
    }
}

// MARK: - Source access

private func occurrences(of needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

/// `enumerator`-free sibling of the helper in `CadenceCancelledTaskReachabilityTests`: this file
/// sits directly under `CadenceTests/`, so the repository root is two levels up from `#filePath`.
private func subtaskRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func subtaskSourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: subtaskRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks `//` line comments and `/* */` block comments with spaces of equal length, so the scanned
/// string is never shorter than the raw one and a length check is a real check.
private func strippingSwiftComments(_ source: String) -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            let width = result.distance(from: range.lowerBound, to: range.upperBound)
            result.replaceSubrange(range, with: String(repeating: " ", count: width))
        }
    }
    return result
}
