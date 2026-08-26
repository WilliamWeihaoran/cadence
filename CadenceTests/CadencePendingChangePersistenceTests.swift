import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-319 / T-320: "commit this pending change, and undo the pending change if the commit throws",
/// stated once.
///
/// The rule had been written twice before this — `CadenceTaskMutationSupport.insertTask` and
/// `CadenceSavedLinkPersistence` — and neither copy was actually about the model it named. These
/// tests exercise the generalised version directly, on both directions and on both outcomes.
///
/// **Every success assertion fetches from a second `ModelContext` on the same container.** The
/// editing context reports the change either way; only the store answers whether it would survive
/// the process, which is the entire difference the tickets turn on. The failure assertions read
/// the *editing* context for the mirror-image reason: after an undo, the pending change must be
/// gone from the place the UI reads.
@MainActor
struct CadencePendingChangePersistenceTests {

    /// A commit that refuses. `ModelContext.save()` cannot be made to throw out of an in-memory
    /// container, which is why the helper takes its commit as a parameter at all.
    private struct CommitRefused: Error {}

    private func refuse(_ modelContext: ModelContext) throws {
        throw CommitRefused()
    }

    // MARK: - Insert

    /// The success half: after `commitInsert` the store holds the object, not just the context.
    @Test func acommittedInsertReachesTheStoreAndNotOnlyTheContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Write the rule down")
        task.priority = .high
        modelContext.insert(task)

        try CadencePendingChangePersistence.commitInsert(of: task, in: modelContext)

        #expect(!modelContext.hasChanges, "the insert was left pending in the context")
        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(stored.count == 1)
        #expect(stored.first?.title == "Write the rule down")
        #expect(stored.first?.priority == .high)
    }

    /// The failure half, and the reason `models` is a list: a creation is a small graph, and
    /// undoing only its root leaves the rest of the graph in the context attached to nothing.
    @Test func afailedInsertTakesEveryInsertedObjectBackOut() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Unsaveable")
        let subtask = Subtask(title: "Its only step")
        subtask.parentTask = task
        modelContext.insert(task)
        modelContext.insert(subtask)

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitInsert(
                of: [task, subtask],
                in: modelContext,
                commit: refuse
            )
        }

        #expect(
            try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty,
            "the context still holds a task the commit refused"
        )
        #expect(
            try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty,
            "the subtask outlived the task it was inserted with"
        )
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Subtask>()).isEmpty)
    }

    /// The undo is scoped to what was handed in, and `rollback()` is the **wrong** tool for it.
    ///
    /// A view's `modelContext` is the app's, not the sheet's. Somewhere else on screen an edit can
    /// be sitting in it uncommitted — a renamed row, a retyped note — and rolling the context back
    /// to undo one failed insert would silently throw that away too. So the pending edit below is
    /// the assertion that matters: it is untouched by an insert that failed beside it, and it is
    /// the only thing here that a `rollback()` in the catch would break.
    @Test func afailedInsertUndoesItsOwnInsertAndNotTheRestOfTheContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let kept = AppTask(title: "Already saved")
        modelContext.insert(kept)
        try modelContext.save()

        // Somebody else's uncommitted edit, still open in the same context.
        kept.title = "Renamed, not yet saved"

        let doomed = AppTask(title: "Never saved")
        modelContext.insert(doomed)
        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitInsert(
                of: doomed,
                in: modelContext,
                commit: refuse
            )
        }

        #expect(
            kept.title == "Renamed, not yet saved",
            "the failed insert rolled the context back and discarded an unrelated pending edit"
        )
        #expect(
            try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Renamed, not yet saved"],
            "the failed insert left something other than its own object behind"
        )
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Already saved"])
    }

    // MARK: - Delete

    /// The success half: the row leaves the store, not just the context.
    @Test func acommittedDeleteReachesTheStoreAndNotOnlyTheContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Going away")
        modelContext.insert(task)
        try modelContext.save()

        modelContext.delete(task)
        try CadencePendingChangePersistence.commitDelete(in: modelContext)

        #expect(!modelContext.hasChanges, "the delete was left pending in the context")
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// The failure half. A delete has no object to hand back, so the undo is a rollback — and the
    /// point of it is that the row becomes **visible again**, rather than staying hidden in a
    /// context that never committed it.
    @Test func afailedDeletePutsTheRowBackWhereItCanBeSeen() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Still here")
        modelContext.insert(task)
        try modelContext.save()

        modelContext.delete(task)
        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: refuse)
        }

        #expect(!modelContext.hasChanges, "the failed delete was left pending in the context")
        #expect(
            try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Still here"],
            "the row is hidden from the list and undeleted in the store — the worst of both"
        )
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Still here"])
    }

    /// A cascade is many pending deletes, and the rollback has to undo all of them. This is the
    /// shape `deleteContext` produces.
    @Test func afailedDeleteRollsBackEveryRowTheCascadeMarked() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        let area = Area(name: "Operations", context: context)
        let tasks = (0..<3).map { AppTask(title: "Task \($0)") }
        modelContext.insert(context)
        modelContext.insert(area)
        for task in tasks {
            task.area = area
            modelContext.insert(task)
        }
        try modelContext.save()

        modelContext.delete(context)
        modelContext.delete(area)
        for task in tasks {
            modelContext.delete(task)
        }
        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: refuse)
        }

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<Context>()).count == 1)
        #expect(try store.fetch(FetchDescriptor<Area>()).count == 1)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).count == 3)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 3)
    }

    // MARK: - The two callers that were written first

    /// `CadenceSavedLinkPersistence` now delegates both directions, and still behaves as T-327
    /// pinned it. Its own suite covers the success paths; this is the failure path it had no seam
    /// to reach.
    @Test func theSavedLinkHelperStillUndoesBothDirections() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let link = SavedLink(title: "Docs", url: "https://example.com")

        try CadenceSavedLinkPersistence.insert(link, in: modelContext)
        #expect(try ModelContext(container).fetch(FetchDescriptor<SavedLink>()).count == 1)

        try CadenceSavedLinkPersistence.delete(link, in: modelContext)
        #expect(try ModelContext(container).fetch(FetchDescriptor<SavedLink>()).isEmpty)
    }

    /// The helper is stated once and the two earlier copies are gone from the files that had them.
    @Test func theTwoOriginalCopiesNowDelegate() throws {
        let saved = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/Shared/CadenceSavedLinkPersistence.swift")
        )
        #expect(saved.contains("CadencePendingChangePersistence.commitInsert("))
        #expect(saved.contains("CadencePendingChangePersistence.commitDelete("))
        #expect(
            CadenceSourceScan.matchCount(#"modelContext\.rollback\(\)"#, in: saved) == 0,
            "the link helper still spells its own undo"
        )
        #expect(CadenceSourceScan.matchCount(#"try modelContext\.save\(\)"#, in: saved) == 0)
    }
}
