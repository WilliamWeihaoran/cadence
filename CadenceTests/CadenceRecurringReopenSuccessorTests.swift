import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-14824]]: reopening a settled occurrence of a repeating task left the successor its settle
/// had already spawned, so the series had two open occurrences, and the predecessor's
/// `recurrenceSpawnedTaskID` kept pointing at the copy, so ticking again spawned nothing.
///
/// **The keeper's call was to fix it, conservatively.** A reopen takes the successor back only
/// while it is still the spawn's untouched copy — the fork collapse's own `isUntouchedClone` gate,
/// reached through `CadenceTaskRecurrenceWorkflowSupport.untouchedSpawnedSuccessor` — and clears
/// the link so the next tick spawns afresh. A successor that has been edited or ticked is left, and
/// so is the link.
///
/// Both doors are exercised: the completion circle (`toggleCompletion`) and the status menus
/// (`setStatus(.todo)`), which share `CadenceTaskMutationSupport.reopen`. Fixtures are in-memory
/// containers; nothing here reaches a real store. What is asserted is counts and relations, never a
/// pinned date (T-1279, T-1296).
@MainActor
struct CadenceRecurringReopenSuccessorTests {

    private struct CommitRefused: Error {}
    private let refuseTheCommit: (ModelContext) throws -> Void = { _ in throw CommitRefused() }
    private let noWidgets = CadenceTaskReopenWidgetEffects { _ in }

    private func makeContainer() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    /// A live daily occurrence, dated in the past so the settle takes the late-completion catch-up.
    private func makeDailyOccurrence(in context: ModelContext, dateKey: String = "2026-10-25") -> AppTask {
        let task = AppTask(title: "Water the plants")
        task.recurrenceRule = .daily
        task.scheduledDate = dateKey
        task.dueDate = dateKey
        context.insert(task)
        return task
    }

    private func allTasks(in context: ModelContext) throws -> [AppTask] {
        try context.fetch(FetchDescriptor<AppTask>())
    }

    private func tick(_ task: AppTask, in context: ModelContext) throws -> AppTask {
        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)
        #expect(task.status == .done)
        let successorID = try #require(task.recurrenceSpawnedTaskID, "the tick spawned nothing, so this test proves nothing")
        let successor = try #require(try allTasks(in: context).first { $0.id == successorID })
        return successor
    }

    // MARK: - An untouched successor is taken back

    /// The defect itself, through the completion circle: tick, untick, and the series has one open
    /// occurrence again; tick once more and a fresh successor is spawned.
    @Test func uncheckingAFreshTickTakesBackTheUntouchedSuccessor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = makeDailyOccurrence(in: context)
        try context.save()

        let first = try tick(task, in: context)
        let firstID = first.id
        #expect(try allTasks(in: context).count == 2)

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
        #expect(task.recurrenceSpawnedTaskID == nil, "the link survived, so the next tick cannot spawn")
        let remaining = try allTasks(in: context)
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == task.id)

        // In the STORE, not only the context that deleted it.
        let readback = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(readback.count == 1)
        #expect(readback.first?.recurrenceSpawnedTaskIDRaw == "")

        let second = try tick(task, in: context)
        #expect(second.id != firstID)
        #expect(task.recurrenceSpawnedTaskID == second.id)
        #expect(try allTasks(in: context).count == 2)
    }

    /// The status menus' door gives the same answer as the circle's.
    @Test func settingStatusToTodoTakesBackTheUntouchedSuccessor() throws {
        let context = ModelContext(try makeContainer())
        let task = makeDailyOccurrence(in: context)
        try context.save()

        try CadenceTaskMutationSupport.setStatus(.done, for: task, modelContext: context, widgetEffects: noWidgets)
        #expect(task.recurrenceSpawnedTaskID != nil)
        #expect(try allTasks(in: context).count == 2)

        try CadenceTaskMutationSupport.setStatus(.todo, for: task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(try allTasks(in: context).map(\.id) == [task.id])
    }

    /// A cancellation advances the series too (T-202), so restoring a cancelled occurrence takes
    /// its successor back exactly as restoring a done one does.
    @Test func restoringACancelledOccurrenceTakesBackItsSuccessor() throws {
        let context = ModelContext(try makeContainer())
        let task = makeDailyOccurrence(in: context, dateKey: "2099-01-10")
        try context.save()

        try CadenceTaskMutationSupport.setStatus(.cancelled, for: task, modelContext: context, widgetEffects: noWidgets)
        #expect(task.recurrenceSpawnedTaskID != nil)
        #expect(try allTasks(in: context).count == 2)

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(try allTasks(in: context).count == 1)
    }

    /// Every field the spawn copies or transforms, at once: a monthly task with a list, a tag,
    /// subtasks, a short estimate and a start minute, completed late. If the reopen's idea of the
    /// spawned copy drifts from `makeNextRecurringTask` on any of them, the fresh successor reads as
    /// touched and is kept, and this reds.
    @Test func aRichOccurrenceFreshlySpawnedStillReadsAsUntouched() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(name: "Home")
        let tag = Tag(name: "chores")
        context.insert(project)
        context.insert(tag)
        let task = AppTask(title: "Pay rent")
        task.notes = "Transfer before noon"
        task.priority = .high
        task.recurrenceRule = .monthly
        task.recurrenceEndMode = .afterCount
        task.recurrenceEndCount = 12
        task.dueDate = "2026-08-31"
        task.scheduledDate = "2026-08-31"
        task.scheduledStartMin = 540
        task.estimatedMinutes = 10
        task.sectionName = "Bills"
        task.project = project
        task.tags = [tag]
        context.insert(task)
        for (index, title) in ["Open banking app", "Confirm amount"].enumerated() {
            let subtask = Subtask(title: title)
            subtask.order = index
            subtask.parentTask = task
            context.insert(subtask)
        }
        try context.save()

        let successor = try tick(task, in: context)
        #expect(successor.project?.id == project.id, "non-vacuity: the copy carried the list")
        #expect((successor.subtasks ?? []).count == 2, "non-vacuity: the copy carried the subtasks")
        #expect(successor.scheduledStartMin == 540)
        #expect(successor.estimatedMinutes == 10)

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(try allTasks(in: context).map(\.id) == [task.id])
        #expect(try context.fetch(FetchDescriptor<Subtask>()).count == 2, "the copy's subtasks went with it and the predecessor's stayed")
    }

    /// A dateless occurrence with no estimate. Since [[T-14823]] the copy is no longer dateless —
    /// it carries a do date one period on — but it still carries no due date, no time (the
    /// predecessor's stray start minute is a leftover, not a plan) and no estimate (None stays
    /// None, T-14231). The reopen has to recognise that copy as the spawn's and take it back.
    @Test func aDatelessOccurrenceWithNoEstimateIsTakenBack() throws {
        let context = ModelContext(try makeContainer())
        let task = AppTask(title: "Stretch")
        task.recurrenceRule = .weekly
        task.estimatedMinutes = 0
        task.scheduledStartMin = 600
        context.insert(task)
        try context.save()

        let successor = try tick(task, in: context)
        #expect(!successor.scheduledDate.isEmpty, "[[T-14823]]: an undated series' successor is dated")
        #expect(successor.dueDate.isEmpty)
        #expect(successor.scheduledStartMin == -1)
        #expect(successor.estimatedMinutes == 0)

        try CadenceTaskMutationSupport.setStatus(.todo, for: task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(try allTasks(in: context).count == 1)
    }

    /// Unticked days after the tick: the copy's dates were planned at the settle's `now`, which is
    /// the predecessor's `completedAt`, not at the moment of the untick. A reopen that planned from
    /// "now" would see a daily copy dated one day off and keep it.
    @Test func aSuccessorSpawnedDaysAgoIsStillRecognisedAsTheSpawnsCopy() throws {
        let context = ModelContext(try makeContainer())
        let task = makeDailyOccurrence(in: context)
        try context.save()
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        let spawned = try #require(
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context, now: threeDaysAgo),
            "the settle spawned nothing, so this test proves nothing"
        )
        try context.save()
        #expect(task.recurrenceSpawnedTaskID == spawned.id)

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(try allTasks(in: context).map(\.id) == [task.id])
    }

    // MARK: - A touched successor is kept, and so is the link

    /// Renamed after the tick: someone has acted on it, so both rows stay and the link stays.
    @Test func anEditedSuccessorIsKeptWithItsLink() throws {
        let context = ModelContext(try makeContainer())
        let task = makeDailyOccurrence(in: context)
        try context.save()
        let successor = try tick(task, in: context)
        successor.title = "Water the plants and the herbs"
        try context.save()

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == successor.id)
        #expect(try allTasks(in: context).count == 2)
    }

    /// Rescheduled after the tick: a date the user chose is work, even though it is the only change.
    @Test func aRescheduledSuccessorIsKeptWithItsLink() throws {
        let context = ModelContext(try makeContainer())
        let task = makeDailyOccurrence(in: context)
        try context.save()
        let successor = try tick(task, in: context)
        successor.scheduledDate = "2099-12-31"
        try context.save()

        try CadenceTaskMutationSupport.setStatus(.todo, for: task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.recurrenceSpawnedTaskID == successor.id)
        #expect(try allTasks(in: context).count == 2)
    }

    /// Ticked itself: the successor is settled and has spawned its own, so reopening the first
    /// occurrence touches neither of them.
    @Test func aTickedSuccessorIsKeptWithItsLink() throws {
        let context = ModelContext(try makeContainer())
        let task = makeDailyOccurrence(in: context)
        try context.save()
        let successor = try tick(task, in: context)
        _ = try tick(successor, in: context)
        #expect(try allTasks(in: context).count == 3)

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == successor.id)
        #expect(successor.status == .done)
        #expect(try allTasks(in: context).count == 3)
    }

    // MARK: - A refused reopen puts everything back

    /// The commit is refused: the occurrence is still settled, the successor is still there, and
    /// the link still points at it — in the context and in the store.
    @Test func aRefusedReopenLeavesTheOccurrenceSettledAndItsSuccessorLinked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = makeDailyOccurrence(in: context)
        try context.save()
        let successor = try tick(task, in: context)
        let successorID = successor.id
        let completedAt = task.completedAt

        #expect(throws: CommitRefused.self) {
            try CadenceTaskMutationSupport.toggleCompletion(
                task,
                modelContext: context,
                widgetEffects: noWidgets,
                commit: refuseTheCommit
            )
        }

        #expect(task.status == .done)
        #expect(task.completedAt == completedAt)
        #expect(task.recurrenceSpawnedTaskID == successorID)
        #expect(try allTasks(in: context).contains { $0.id == successorID })
        let readback = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(readback.count == 2)
    }

    /// The status undo is held in the cascade's own queue, so it runs before `commitCascade`'s
    /// `rollback()` on a refusal. The behaviour test above cannot see it on Xcode 27, where
    /// `rollback()` refreshes the materialised reference by itself; on the toolchain that does not
    /// ([[T-1279]], [[T-1296]]) the refused reopen would leave the occurrence open over a store
    /// that still says done. The same construction, and the same reason for a source scan, as
    /// `CadenceDeleteSurvivorRestoreTests` states for the delete core.
    @Test func theReopenHoldsItsStatusUndoInTheCascadesQueue() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift")
        )
        let body = try #require(CadenceSourceScan.functionBody(named: "reopen", in: source))
        #expect(body.contains("CadencePendingChangePersistence.commitCascade("), "non-vacuity: this is the reopen's body")
        #expect(body.contains("effects.holdUndo(restore)"), "a refused reopen-with-delete no longer puts the status back")
        #expect(body.contains("effects: effects"), "the held undo is not the queue the cascade runs")
    }

    /// A non-repeating task has nothing to take back: the reopen is the two-field edit it was.
    @Test func reopeningAPlainTaskStillReopensIt() throws {
        let context = ModelContext(try makeContainer())
        let task = AppTask(title: "Call the dentist")
        context.insert(task)
        try context.save()
        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)
        #expect(task.status == .done)

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: noWidgets)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
        #expect(try allTasks(in: context).count == 1)
    }
}
