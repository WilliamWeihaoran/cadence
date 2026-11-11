import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-13921]] — Duplicate carries the task's checklist.**
///
/// `CadenceTaskMutationSupport.duplicate` is what both row menus' Duplicate call (the Mac's
/// `MacTaskRowContextMenu.duplicate`, iOS's `iOSTaskRowContextMenu.duplicate`). It copied every
/// field but the subtasks, so a task duplicated for its checklist arrived as a bare title. These
/// read the copy back from a second context on the same store, so what they see is what was
/// committed rather than what is merely pending.
@MainActor
struct CadenceTaskDuplicateSubtaskTests {
    private struct CommitRefused: Error {}

    private func makeStore() throws -> (ModelContainer, ModelContext, AppTask) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Pack")
        context.insert(task)
        // Inserted out of order, and one ticked, so the copy's order and tick state are both read.
        for (title, order, done) in [("Charger", 1, true), ("Passport", 0, false), ("Socks", 2, false)] {
            let subtask = try #require(
                CadenceTaskMutationSupport.insertSubtask(titled: title, into: task, order: order, modelContext: context)
            )
            subtask.isDone = done
        }
        try context.save()
        return (container, context, task)
    }

    @Test func aDuplicateCommitsTheChecklistUntickedInItsOrder() throws {
        let (container, context, task) = try makeStore()

        let copy = try CadenceTaskMutationSupport.duplicate(task, allTasks: [task], modelContext: context)

        let copyID = copy.id
        let committed = try #require(
            try ModelContext(container).fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == copyID })).first
        )
        let subtasks = (committed.subtasks ?? []).sorted { $0.order < $1.order }
        #expect(subtasks.map(\.title) == ["Passport", "Charger", "Socks"], "the copy has the source's checklist, in order")
        #expect(subtasks.allSatisfy { !$0.isDone }, "a fresh copy starts with its checklist unticked")
        #expect(subtasks.allSatisfy { $0.parentTask?.id == copyID }, "each copied row belongs to the copy")

        // The source keeps its own three rows, the ticked one still ticked; nothing was moved.
        #expect((task.subtasks ?? []).count == 3)
        #expect((task.subtasks ?? []).filter(\.isDone).map(\.title) == ["Charger"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<Subtask>()).count == 6)
    }

    @Test func aRefusedDuplicateLeavesNoCopiedSubtaskBehind() throws {
        let (container, context, task) = try makeStore()

        #expect(throws: CommitRefused.self) {
            try CadenceTaskMutationSupport.duplicate(
                task, allTasks: [task], modelContext: context, commit: { _ in throw CommitRefused() }
            )
        }

        #expect(try ModelContext(container).fetch(FetchDescriptor<Subtask>()).count == 3)
        #expect(try context.fetch(FetchDescriptor<Subtask>()).count == 3, "a copied subtask is still pending")
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    /// [[T-16531]]: a copy of the list's last task sorts after it by `order`, not level with it.
    /// The source was excluded from the siblings the next `order` is taken over -- the move rule,
    /// where the task is leaving -- so the copy took the source's own `order`.
    @Test func aDuplicateOfTheListsLastTaskTakesTheNextOrderNotTheSourcesOwn() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "First")
        first.order = 0
        let last = AppTask(title: "Last")
        last.order = 1
        context.insert(first)
        context.insert(last)
        try context.save()

        let copy = try CadenceTaskMutationSupport.duplicate(last, allTasks: [first, last], modelContext: context)

        #expect(copy.order == 2, "the copy tied with its source at order \(last.order)")
    }

    @Test func aTaskWithNoChecklistDuplicatesWithNone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Bare")
        context.insert(task)
        try context.save()

        let copy = try CadenceTaskMutationSupport.duplicate(task, allTasks: [task], modelContext: context)

        #expect((copy.subtasks ?? []).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Subtask>()).isEmpty)
    }
}
