import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-19057]]: a REFUSED settle of a repeating task with a checklist un-inserted the successor it
/// minted and left the successor's copied subtasks pending, parentless, for the next unrelated
/// save to commit as orphan `Subtask` rows.
///
/// Every door below settles a weekly task carrying two subtasks under a commit that throws, then
/// makes an unrelated committed save, then reads the store from a fresh context. The store must
/// hold exactly the predecessor's two subtasks, both still parented. Each door reaches one of the
/// sites that now reads `CadenceTaskRecurrenceWorkflowSupport.insertedGraph(of:)`:
/// `CadenceTaskMutationSupport.commitSettle` (toggle, cancel, focus complete),
/// `CadenceTaskFieldEditCommit`'s undo (the Today shortcut), and the MCP complete, cancel and
/// bulk-cancel arms of `CadenceWriteService`.
@MainActor
struct CadenceRefusedSettleChecklistTests {

    private struct CommitRefused: Error {}

    private static let todayKey = "2026-05-10"

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let task: AppTask
    }

    /// Weekly, do date two days before `todayKey` (so the Today shortcut mints early), two subtasks.
    private func fixture(title: String = "Weekly review") throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: title)
        task.recurrenceRule = .weekly
        task.scheduledDate = "2026-05-08"
        context.insert(task)
        let subtasks = ["A", "B"].enumerated().map { index, title -> Subtask in
            let subtask = Subtask(title: title)
            subtask.order = index
            subtask.parentTask = task
            context.insert(subtask)
            return subtask
        }
        task.subtasks = subtasks
        try context.save()
        return Fixture(container: container, context: context, task: task)
    }

    /// The unrelated committed save the orphans used to ride in on, then the store's own answer.
    private func expectOnlyThePredecessorsChecklist(_ f: Fixture, door: String) throws {
        f.context.insert(AppTask(title: "Unrelated"))
        try f.context.save()

        let store = ModelContext(f.container)
        let subtasks = try store.fetch(FetchDescriptor<Subtask>())
        #expect(subtasks.count == 2, "\(door): the store holds \(subtasks.count) subtasks after a refused settle")
        #expect(subtasks.allSatisfy { $0.parentTask?.id == f.task.id }, "\(door): a subtask is not the predecessor's")
        #expect(try store.fetch(FetchDescriptor<AppTask>()).count == 2, "\(door): a successor survived the refusal")
    }

    @Test func aRefusedToggleLeavesNoOrphanedChecklist() throws {
        let f = try fixture()
        #expect(throws: (any Error).self) {
            try CadenceTaskMutationSupport.toggleCompletion(f.task, modelContext: f.context) { _ in throw CommitRefused() }
        }
        try expectOnlyThePredecessorsChecklist(f, door: "toggle")
    }

    @Test func aRefusedCancelLeavesNoOrphanedChecklist() throws {
        let f = try fixture()
        #expect(throws: (any Error).self) {
            try CadenceTaskMutationSupport.setStatus(.cancelled, for: f.task, modelContext: f.context) { _ in throw CommitRefused() }
        }
        try expectOnlyThePredecessorsChecklist(f, door: "setStatus(.cancelled)")
    }

    @Test func aRefusedFocusCompleteLeavesNoOrphanedChecklist() throws {
        let f = try fixture()
        #expect(throws: (any Error).self) {
            try CadenceFocusSupport.complete(f.task, elapsedSeconds: 0, modelContext: f.context) { _ in throw CommitRefused() }
        }
        try expectOnlyThePredecessorsChecklist(f, door: "focus complete")
    }

    /// The field-edit commit's undo: an overdue repeating task sent to Today mints its successor
    /// inside the commit ([[T-19050]]).
    @Test func aRefusedTodayShortcutLeavesNoOrphanedChecklist() throws {
        let f = try fixture()
        let landed = CadenceTaskDateEditing.scheduleToday(
            f.task, in: f.context, todayKey: Self.todayKey, commit: { _ in throw CommitRefused() }
        )
        #expect(!landed)
        try expectOnlyThePredecessorsChecklist(f, door: "scheduleToday")
    }

    /// The accepted Today shortcut does mint a successor with a copied checklist, so the refusal
    /// above is not green over a shortcut that never spawned anything.
    @Test func anAcceptedTodayShortcutCommitsTheSuccessorsChecklist() throws {
        let f = try fixture()
        #expect(CadenceTaskDateEditing.scheduleToday(f.task, in: f.context, todayKey: Self.todayKey))
        let store = ModelContext(f.container)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).count == 2)
        let subtasks = try store.fetch(FetchDescriptor<Subtask>())
        #expect(subtasks.count == 4)
        #expect(subtasks.allSatisfy { $0.parentTask != nil })
    }

    @Test func aRefusedMCPCompleteLeavesNoOrphanedChecklist() throws {
        let f = try fixture()
        let refusing = CadenceWriteService(context: f.context, preparesStore: false, commit: { _ in throw CommitRefused() })
        #expect(throws: CommitRefused.self) {
            _ = try refusing.completeTask(taskID: f.task.id.uuidString)
        }
        try expectOnlyThePredecessorsChecklist(f, door: "MCP complete_task")
    }

    @Test func aRefusedMCPCancelLeavesNoOrphanedChecklist() throws {
        let f = try fixture()
        let refusing = CadenceWriteService(context: f.context, preparesStore: false, commit: { _ in throw CommitRefused() })
        #expect(throws: CommitRefused.self) {
            _ = try refusing.cancelTask(taskID: f.task.id.uuidString)
        }
        try expectOnlyThePredecessorsChecklist(f, door: "MCP cancel_task")
    }

    @Test func aRefusedMCPBulkCancelLeavesNoOrphanedChecklist() throws {
        let f = try fixture()
        let refusing = CadenceWriteService(context: f.context, preparesStore: false, commit: { _ in throw CommitRefused() })
        #expect(throws: CommitRefused.self) {
            _ = try refusing.bulkCancelTasks(options: .init(taskIds: [f.task.id.uuidString]))
        }
        try expectOnlyThePredecessorsChecklist(f, door: "MCP bulk_cancel_tasks")
    }

    /// The accepted settle commits the copies under the successor, so every refusal above is
    /// measured against a spawn that really does copy the checklist.
    @Test func anAcceptedToggleCommitsTheSuccessorsChecklist() throws {
        let f = try fixture()
        try CadenceTaskMutationSupport.toggleCompletion(f.task, modelContext: f.context)
        let store = ModelContext(f.container)
        let subtasks = try store.fetch(FetchDescriptor<Subtask>())
        #expect(subtasks.count == 4)
        #expect(subtasks.allSatisfy { $0.parentTask != nil })
        #expect(!f.context.hasChanges)
    }
}
