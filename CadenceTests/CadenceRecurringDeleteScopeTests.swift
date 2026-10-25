import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-6115]]: deleting the live occurrence of a repeating task used to end the whole series in
/// silence, and neither platform's confirmation said so.
///
/// **The defect.** `spawnNextOccurrenceIfNeeded` is the only thing that mints a next occurrence and
/// it was reached from exactly two places, `markDone` and `markCancelled`. A delete ran
/// `repairDanglingRecurrenceLinks`, which tidies the *predecessor's* pointer — and tidying a
/// predecessor is not the same as having a next occurrence. So a user who deleted today's
/// occurrence to skip it lost every future one, while the confirmation promised only that this task
/// would be removed.
///
/// **The owner's decision was to offer the choice**, Calendar's shape, with "this occurrence"
/// genuinely leaving the repeat alive. That makes the occurrence arm the one with real work behind
/// it, and most of what follows is about it.
///
/// **What is asserted is counts and relations, never a pinned date.** The successor's dates come
/// out of `plannedNextDates` against a real `now`; what this suite pins is that a successor exists,
/// that it is the one the predecessor points at, that its date is *after* the deleted occurrence's,
/// and that the other arm mints nothing. CI pins Xcode 26.0.1 and this Mac runs 27 (T-1279,
/// T-1296), so a pinned figure here would redden one of them.
@MainActor
struct CadenceRecurringDeleteScopeTests {

    private struct CommitRefused: Error {}
    private let refuseTheCommit: (ModelContext) throws -> Void = { _ in throw CommitRefused() }

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    /// A live daily occurrence: recurring, dated, nothing spawned from it yet.
    private func makeDailyOccurrence(
        in modelContext: ModelContext,
        title: String = "Water the plants",
        dateKey: String = "2026-10-25"
    ) -> AppTask {
        let task = AppTask(title: title)
        task.recurrenceRule = .daily
        task.scheduledDate = dateKey
        task.dueDate = dateKey
        modelContext.insert(task)
        return task
    }

    private func openTasks(in modelContext: ModelContext) throws -> [AppTask] {
        try modelContext.fetch(FetchDescriptor<AppTask>())
    }

    // MARK: - The occurrence arm actually keeps the series alive

    /// The whole point of the owner's decision: the row goes, and the next occurrence is there.
    @Test func deletingThisOccurrenceLeavesTheSeriesWithAliveNextOccurrence() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)
        let deletedID = task.id
        let deletedDate = task.scheduledDate

        #expect(CadenceTaskMutationSupport.delete(
            task,
            modelContext: modelContext,
            recurrenceScope: .thisOccurrence
        ))

        let survivors = try openTasks(in: modelContext)
        #expect(survivors.count == 1)
        let successor = try #require(survivors.first)
        #expect(successor.id != deletedID)
        #expect(successor.isRecurring)
        #expect(successor.recurrenceRule == .daily)
        // A relation, not a figure: the successor lands later than the occurrence it replaced.
        #expect(successor.scheduledDate > deletedDate)
        #expect(successor.recurrenceSourceTaskID == deletedID)
        #expect(successor.recurrenceOccurrenceIndex == 1)
    }

    /// The second-context readback the safety rules ask for: the successor is in the **store**, not
    /// merely in the context that minted it.
    @Test func theSuccessorAnOccurrenceDeleteMintsIsInTheStore() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = makeDailyOccurrence(in: modelContext)
        try modelContext.save()
        let deletedID = task.id

        #expect(CadenceTaskMutationSupport.delete(
            task,
            modelContext: modelContext,
            recurrenceScope: .thisOccurrence
        ))

        let reader = ModelContext(container)
        let stored = try reader.fetch(FetchDescriptor<AppTask>())
        #expect(stored.count == 1)
        #expect(stored.first?.id != deletedID)
    }

    /// Today's behaviour, now chosen rather than stumbled into. The series arm is unchanged: the
    /// row goes and nothing replaces it.
    @Test func deletingTheWholeSeriesStillMintsNothing() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)

        #expect(CadenceTaskMutationSupport.delete(
            task,
            modelContext: modelContext,
            recurrenceScope: .wholeSeries
        ))

        #expect(try openTasks(in: modelContext).isEmpty)
    }

    /// The default is the series arm, so every caller that existed before the parameter did — the
    /// list cascades, the bulk paths, the MCP write service — keeps minting nothing.
    @Test func thedefaultScopeOfAdeleteIsTheSeriesArm() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)

        #expect(CadenceTaskMutationSupport.delete(task, modelContext: modelContext))

        #expect(try openTasks(in: modelContext).isEmpty)
    }

    /// Subtasks go with the row being deleted, on the occurrence arm as on every other — and the
    /// successor is the spawn's own copy, so it carries the subtask *titles* rather than the rows.
    @Test func anOccurrenceDeleteStillTakesTheRowsSubtasksWithIt() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)
        CadenceTaskMutationSupport.insertSubtask(titled: "Fill the can", into: task, modelContext: modelContext)

        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).count == 1)

        #expect(CadenceTaskMutationSupport.delete(
            task,
            modelContext: modelContext,
            recurrenceScope: .thisOccurrence
        ))

        let remainingSubtasks = try modelContext.fetch(FetchDescriptor<Subtask>())
        let successor = try #require(try openTasks(in: modelContext).first)
        // The deleted row's own subtask is gone; the one left belongs to the successor the spawn
        // copied, which is `makeNextRecurringTask`'s existing behaviour and not this ticket's.
        #expect(remainingSubtasks.allSatisfy { $0.parentTask?.id == successor.id })
    }

    // MARK: - The predecessor's pointer lands on the new successor

    /// Why the spawn sits **above** `repairDanglingRecurrenceLinks`: with the successor already
    /// inserted, the repair walks predecessor → doomed occurrence → fresh successor and re-points
    /// the predecessor at the successor instead of clearing it to nil.
    @Test func thepredecessorOfAdeletedOccurrenceIsRepointedAtTheFreshSuccessor() throws {
        let modelContext = try makeContext()
        let predecessor = makeDailyOccurrence(in: modelContext, title: "Yesterday", dateKey: "2026-10-24")
        let live = makeDailyOccurrence(in: modelContext, title: "Today", dateKey: "2026-10-25")
        predecessor.status = .done
        predecessor.completedAt = Date()
        predecessor.recurrenceSpawnedTaskID = live.id
        let liveID = live.id

        #expect(CadenceTaskMutationSupport.delete(
            live,
            modelContext: modelContext,
            recurrenceScope: .thisOccurrence
        ))

        let survivors = try openTasks(in: modelContext)
        #expect(survivors.count == 2)
        let successor = try #require(survivors.first { $0.id != predecessor.id })
        #expect(successor.id != liveID)
        #expect(predecessor.recurrenceSpawnedTaskID == successor.id)
    }

    // MARK: - A refused commit leaves no successor behind

    /// The insert carries no undo of its own, and this is why that is safe: the commit is
    /// `commitDelete`, whose refusal path is `modelContext.rollback()`, and a row inserted since
    /// the last save is one of the pending changes that discards. A refused occurrence delete
    /// therefore leaves exactly the task the user is still looking at — not that task *and* a
    /// successor minted for a delete that never happened.
    @Test func arefusedOccurrenceDeleteLeavesNoSuccessorBehind() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = makeDailyOccurrence(in: modelContext)
        try modelContext.save()
        let taskID = task.id

        #expect(!CadenceTaskMutationSupport.delete(
            task,
            modelContext: modelContext,
            recurrenceScope: .thisOccurrence,
            commit: refuseTheCommit
        ))

        let survivors = try openTasks(in: modelContext)
        #expect(survivors.count == 1)
        #expect(survivors.first?.id == taskID)
        #expect(!modelContext.hasChanges)

        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    // MARK: - Which tasks are asked at all

    /// A non-repeating task must not grow a second button, and this is the one answer both
    /// platforms ask for it.
    @Test func aplainTaskIsNeverOfferedTheChoice() throws {
        let modelContext = try makeContext()
        let task = AppTask(title: "Renew the domain")
        modelContext.insert(task)

        #expect(!CadenceTaskRecurrenceWorkflowSupport.deleteOffersSeriesChoice(for: task))
    }

    @Test func aliveRepeatingOccurrenceIsOfferedTheChoice() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)

        #expect(CadenceTaskRecurrenceWorkflowSupport.deleteOffersSeriesChoice(for: task))
    }

    /// **The settled-occurrence decision.** A past occurrence that already minted its successor
    /// cannot end the series by being deleted — the repair re-points its predecessor at the
    /// survivor and the live occurrence is some other row — so it is *not* asked. Two buttons that
    /// do the same thing are worse than one.
    @Test func asettledOccurrenceWhoseSuccessorIsAliveIsNotOfferedTheChoice() throws {
        let modelContext = try makeContext()
        let settled = makeDailyOccurrence(in: modelContext, title: "Yesterday", dateKey: "2026-10-24")
        let live = makeDailyOccurrence(in: modelContext, title: "Today", dateKey: "2026-10-25")
        settled.status = .done
        settled.completedAt = Date()
        settled.recurrenceSpawnedTaskID = live.id

        #expect(!CadenceTaskRecurrenceWorkflowSupport.deleteOffersSeriesChoice(for: settled))
        #expect(CadenceTaskRecurrenceWorkflowSupport.deleteOffersSeriesChoice(for: live))
    }

    /// **The last-occurrence decision.** A count-limited series that has already produced its last
    /// occurrence has no successor to keep, so the choice is not offered and the delete behaves as
    /// it always did.
    @Test func thelastOccurrenceOfAcountLimitedSeriesIsNotOfferedTheChoice() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)
        task.recurrenceEndModeRaw = TaskRecurrenceEndMode.afterCount.rawValue
        task.recurrenceEndCount = 3
        task.recurrenceOccurrenceIndex = 2

        #expect(task.recurrenceHasEnded)
        #expect(!CadenceTaskRecurrenceWorkflowSupport.deleteOffersSeriesChoice(for: task))
    }

    /// And if the occurrence arm is reached anyway — a caller passing the scope past the guard —
    /// it mints nothing rather than minting an occurrence past the series' own limit.
    @Test func deletingThelastOccurrenceOfAcountLimitedSeriesMintsNothing() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)
        task.recurrenceEndModeRaw = TaskRecurrenceEndMode.afterCount.rawValue
        task.recurrenceEndCount = 3
        task.recurrenceOccurrenceIndex = 2

        #expect(CadenceTaskMutationSupport.delete(
            task,
            modelContext: modelContext,
            recurrenceScope: .thisOccurrence
        ))

        #expect(try openTasks(in: modelContext).isEmpty)
    }

    // MARK: - Both confirmations carry it, and neither grows a button for a plain task

    /// The Mac overlay. A plain task's request has the title and sentence it always had, one
    /// confirm, and **no** alternate — which is what the overlay reads to decide whether to draw a
    /// third button at all.
    @Test func themacConfirmationIsUnchangedForAplainTask() throws {
        let modelContext = try makeContext()
        let task = AppTask(title: "Renew the domain")
        modelContext.insert(task)

        let manager = DeleteConfirmationManager.shared
        manager.cancel()
        manager.presentTaskDelete(task, in: modelContext)
        defer { manager.cancel() }

        let request = try #require(manager.request)
        #expect(request.title == "Delete Task?")
        #expect(request.message == "This will permanently delete \"Renew the domain\".")
        #expect(request.confirmLabel == "Delete")
        #expect(request.alternate == nil)
    }

    @Test func themacConfirmationOffersBothScopesForArepeatingTask() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)

        let manager = DeleteConfirmationManager.shared
        manager.cancel()
        manager.presentTaskDelete(task, in: modelContext)
        defer { manager.cancel() }

        let request = try #require(manager.request)
        #expect(request.title == CadenceRecurrenceScopeCopy.deleteScopeTitle)
        #expect(request.message.contains(CadenceRecurrenceScopeCopy.deleteScopeMessage))
        #expect(request.message.contains("Water the plants"))
        #expect(request.confirmLabel == CadenceTaskRecurrenceDeleteScope.thisOccurrence.label)
        #expect(request.alternate?.label == CadenceTaskRecurrenceDeleteScope.wholeSeries.label)
    }

    /// The primary button on the Mac is the occurrence arm, and pressing it keeps the repeat alive
    /// end to end — through the manager, the macOS wrapper and the shared core.
    @Test func themacPrimaryConfirmDeletesOnlyTheOccurrence() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)
        let deletedID = task.id

        let manager = DeleteConfirmationManager.shared
        manager.cancel()
        manager.presentTaskDelete(task, in: modelContext)
        manager.confirm()
        defer { manager.cancel() }

        #expect(manager.request == nil)
        let survivors = try openTasks(in: modelContext)
        #expect(survivors.count == 1)
        #expect(survivors.first?.id != deletedID)
    }

    /// The alternate ends the repeat, which is what it says.
    @Test func themacAlternateConfirmEndsTheSeries() throws {
        let modelContext = try makeContext()
        let task = makeDailyOccurrence(in: modelContext)

        let manager = DeleteConfirmationManager.shared
        manager.cancel()
        manager.presentTaskDelete(task, in: modelContext)
        manager.confirmAlternate()
        defer { manager.cancel() }

        #expect(manager.request == nil)
        #expect(try openTasks(in: modelContext).isEmpty)
    }

    /// `confirmAlternate` on a single-button request does nothing at all, so a request with no
    /// second meaning cannot acquire one.
    @Test func confirmAlternateIsAnoOpWhenTherequestHasNoAlternate() throws {
        let modelContext = try makeContext()
        let task = AppTask(title: "Renew the domain")
        modelContext.insert(task)

        let manager = DeleteConfirmationManager.shared
        manager.cancel()
        manager.presentTaskDelete(task, in: modelContext)
        manager.confirmAlternate()
        defer { manager.cancel() }

        #expect(manager.request != nil)
        #expect(try openTasks(in: modelContext).count == 1)
    }

    // MARK: - Source scans

    /// The iOS half cannot be driven from the macOS test target — that target compiles no
    /// `Cadence/iOS/` — so what is pinned here is that **both** phone surfaces raise the one shared
    /// modifier and neither keeps a private copy of the alert. That is the arrangement that would
    /// otherwise let one of them miss the scope question entirely.
    @Test func bothIOStaskSurfacesRaiseTheOneSharedDeleteConfirmation() throws {
        for path in ["Cadence/iOS/iOSTaskViews.swift", "Cadence/iOS/iOSTaskDetailSheet.swift"] {
            let source = try CadenceSourceScan.strippingComments(CadenceSourceScan.sourceFile(path))
            #expect(
                source.contains(".iOSTaskDeleteConfirmation(task: task, isPresented: $showDeleteConfirmation)"),
                "\(path) must raise the shared delete confirmation"
            )
            #expect(
                !source.contains("\"This removes the task and its subtasks.\""),
                "\(path) must not keep its own copy of the delete confirmation's sentence"
            )
        }
    }

    /// The modifier itself: both scopes offered, the plain sentence kept for everything else, and
    /// the choice gated on the shared predicate rather than on a local reading of `isRecurring`.
    @Test func thesharedIOSmodifierGatesTheChoiceOnTheSharedPredicate() throws {
        let source = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift")
        )
        #expect(source.contains("struct iOSTaskDeleteConfirmationModifier: ViewModifier"))
        #expect(source.contains("CadenceTaskRecurrenceWorkflowSupport.deleteOffersSeriesChoice(for: task)"))
        #expect(source.contains("CadenceTaskRecurrenceDeleteScope.thisOccurrence.label"))
        #expect(source.contains("CadenceTaskRecurrenceDeleteScope.wholeSeries.label"))
        #expect(source.contains("\"This removes the task and its subtasks.\""))
    }

    /// The spawn is reached through `CadenceTaskRecurrenceWorkflowSupport` and sits **above** the
    /// pointer repair. A reimplementation beside the delete, or a call below the repair, is the two
    /// ways this fix silently stops working, and neither shows up in a behavioural assertion on a
    /// series with no predecessor.
    @Test func thedeleteCoreSpawnsThroughTheRecurrenceWorkflowAboveThePointerRepair() throws {
        let source = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift")
        )
        let spawn = try #require(
            source.range(of: "CadenceTaskRecurrenceWorkflowSupport.spawnSuccessorBeforeDeletingOccurrence")
        )
        let repair = try #require(
            source.range(of: "CadenceTaskRecurrenceWorkflowSupport.repairDanglingRecurrenceLinks(forDeleted:")
        )
        #expect(spawn.lowerBound < repair.lowerBound)
        #expect(source.contains("if recurrenceScope == .thisOccurrence {"))
    }
}
