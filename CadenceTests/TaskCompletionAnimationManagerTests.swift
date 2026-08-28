#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Covers the delayed green-fill completion/cancellation flow that keeps a
/// hovered task's underlying `status` (and therefore its grouped section)
/// unchanged until the animation finishes — the mechanism that is supposed to
/// stop a row from snapping into a different group mid-animation.
@Suite(.serialized)
@MainActor
struct TaskCompletionAnimationManagerTests {

    @Test func togglingCompletionMarksItPendingWithoutChangingStatusYet() {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")

        manager.toggleCompletion(for: task)

        #expect(manager.isPending(task))
        #expect(task.isDone == false)
        #expect(task.status == .todo)

        manager.cancelPending(for: task.id) // avoid leaking the background timer past the test
    }

    @Test func statusStaysUnchangedPartwayThroughTheCompletionAnimation() {
        // Simulates a hovered row, grouped by e.g. priority, partway through the
        // 2.5s completion animation: the task must still read as "not done" so it
        // does not jump to a different grouped section before the fill finishes.
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")

        manager.toggleCompletion(for: task)
        let midway = Date().addingTimeInterval(1.0)
        let progress = manager.progress(for: task, now: midway)

        #expect(progress > 0)
        #expect(progress < 1)
        #expect(task.isDone == false)

        manager.cancelPending(for: task.id)
    }

    @Test func tappingCompleteAgainWhilePendingCancelsTheAnimationInstead() {
        // Tapping the completion control a second time while the fill is still
        // animating is the "undo" gesture — it must abort cleanly, not toggle
        // straight to done.
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")

        manager.toggleCompletion(for: task)
        #expect(manager.isPending(task))

        manager.toggleCompletion(for: task)

        #expect(!manager.isPending(task))
        #expect(task.isDone == false)
    }

    /// T-341 extended this: it asserted the status and not the timestamp, which is why a restore
    /// that left `completedAt` behind survived it. An open task carrying a completion timestamp is
    /// the invariant break, not the status.
    @Test func togglingCompletionOnAnAlreadyDoneTaskRevertsItSynchronously() {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")
        task.status = .done
        task.completedAt = Date()

        manager.toggleCompletion(for: task)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
        #expect(!manager.isPending(task))
    }

    // MARK: - T-341: restoring must clear the timestamp it was settled with

    /// The bug, stated: `toggleCancellation` wrote `task.status = .todo` directly while the
    /// completion branch sixty lines above called `TaskWorkflowService.markTodo`. Since T-202 a
    /// cancelled task carries a `completedAt`, so restoring one left an **open** task holding a
    /// completion timestamp — which Today's Completed section reads, and which every settled query
    /// assumes only settled work has.
    @Test func restoringACancelledTaskClearsItsCompletionTimestamp() {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")
        task.status = .cancelled
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)

        manager.toggleCancellation(for: task)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
        #expect(!manager.isPendingCancel(task))
    }

    // MARK: - T-344: the completion circle toggles settled, not done

    /// Decided in `CadenceTaskMutationSupport.toggleCompletion` and enforced on both platforms: the
    /// circle un-settles a cancelled task rather than converting it to done. No green fill starts,
    /// and the cancellation timestamp goes with the cancellation.
    @Test func theCompletionCircleRestoresACancelledTaskRatherThanCompletingIt() {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")
        task.status = .cancelled
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)

        manager.toggleCompletion(for: task)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
        #expect(!manager.isPending(task))
        #expect(!manager.isPendingCancel(task))
    }

    // MARK: - T-357: the branch that has no injected context

    /// The manager's `modelContext` is injected on root appear, so the contextless branch is
    /// unlikely in the shipping app and was never unlikely in a unit test. It used to write
    /// `task.completedAt` and `task.status` directly, which skips
    /// `spawnNextOccurrenceIfNeeded` — a recurring task completed through it would have been the
    /// last occurrence of its series.
    ///
    /// The fix is not "assume a context": it falls back to the task's own
    /// `modelContext`, which any task the manager can see has. This waits out the real 2.5s fill
    /// on purpose — the write happens in the timer's continuation, and that continuation is the
    /// code under test.
    @Test func theContextlessCompletionPathStillSpawnsTheNextOccurrence() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let injected = manager.modelContext
        manager.modelContext = nil
        defer { manager.modelContext = injected }

        let task = AppTask(title: "water the plants")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-08-04"
        context.insert(task)
        try context.save()

        manager.toggleCompletion(for: task)
        #expect(manager.isPending(task))

        try await waitOutTheFill()

        #expect(task.status == .done)
        #expect(task.completedAt != nil)
        let next = try spawnedTask(for: task, in: context)
        #expect(next != nil, "the contextless completion path did not spawn the next occurrence")
        #expect(next?.title == "water the plants")
        #expect(next?.status == .todo)
        #expect(next?.completedAt == nil)
    }

    /// The cancellation half. Cancelling one occurrence skips it and the series must keep going —
    /// `CadenceTaskRecurrenceWorkflowSupport.markCancelled` says so in as many words — and the
    /// contextless branch bypassed that too.
    @Test func theContextlessCancellationPathStillSpawnsTheNextOccurrence() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let injected = manager.modelContext
        manager.modelContext = nil
        defer { manager.modelContext = injected }

        let task = AppTask(title: "water the plants")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-08-04"
        context.insert(task)
        try context.save()

        manager.toggleCancellation(for: task)
        #expect(manager.isPendingCancel(task))

        try await waitOutTheFill()

        #expect(task.status == .cancelled)
        // T-202: a cancellation records when the task stopped being open, exactly as a completion does.
        #expect(task.completedAt != nil)
        let next = try spawnedTask(for: task, in: context)
        #expect(next != nil, "the contextless cancellation path did not spawn the next occurrence")
        #expect(next?.status == .todo)
    }

    // MARK: - Helpers

    private func waitOutTheFill() async throws {
        let seconds = TaskCompletionAnimationManager.animationDuration + 1.0
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func spawnedTask(for task: AppTask, in context: ModelContext) throws -> AppTask? {
        guard let spawnedID = task.recurrenceSpawnedTaskID else { return nil }
        return try context.fetch(FetchDescriptor<AppTask>()).first { $0.id == spawnedID }
    }

    @Test func startingCancellationAbortsAnInFlightCompletionPending() {
        // Guards the mutual exclusion between the two pending animations: if a
        // hovered task is mid completion-fill and the user cancels it instead
        // (Cmd+/), the stale completion timer must not also fire later.
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")

        manager.toggleCompletion(for: task)
        #expect(manager.isPending(task))

        manager.toggleCancellation(for: task)

        #expect(!manager.isPending(task))
        #expect(manager.isPendingCancel(task))
        #expect(task.status == .todo)

        manager.cancelCancelPending(for: task.id)
    }

    @Test func togglingCancellationOnAnAlreadyCancelledTaskRevertsItSynchronously() {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")
        task.status = .cancelled

        manager.toggleCancellation(for: task)

        #expect(task.status == .todo)
        #expect(!manager.isPendingCancel(task))
    }
}
#endif
