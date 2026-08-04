#if os(macOS)
import Foundation
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

    @Test func togglingCompletionOnAnAlreadyDoneTaskRevertsItSynchronously() {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")
        task.status = .done
        task.completedAt = Date()

        manager.toggleCompletion(for: task)

        #expect(task.status == .todo)
        #expect(!manager.isPending(task))
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
