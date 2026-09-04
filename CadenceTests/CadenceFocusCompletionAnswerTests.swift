import Foundation
import SwiftData
import Testing
@testable import Cadence

/// `CadenceTaskStatusEditing.completeFocusSession` is the one entry point on that wrapper that
/// **answers** rather than returning `Void`, and its answer is load-bearing:
/// `iOSFocusView.complete(_:)` reads it as `guard CadenceTaskStatusEditing.completeFocusSession(…)`
/// and only then resets the stopwatch. The elapsed clock exists nowhere else, so `false` on a
/// commit that actually landed strands the timer running over a finished task, and the user's next
/// stop banks the same minutes twice.
///
/// Nothing pinned that answer. `CadenceTaskStatusEditingSurfaceTests` calls the entry point through
/// a `(AppTask, ModelContext, CadenceWindDownReconciler) -> Void` table, which discards it;
/// `CadenceFocusSessionAndBlockCommitTests` and `CadenceSaveCommitDisciplineTests` read the *call
/// site's* `guard` out of the iOS source rather than running the callee. Measured by mutation:
/// flipping the success path's `return true` to `return false` survived every one of those.
@MainActor
struct CadenceFocusCompletionAnswerTests {

    /// The success path says so, and the transition it is reporting on is really in the store.
    ///
    /// The `hasChanges` check is what makes the answer mean "committed" rather than "did not
    /// throw": a `true` handed back over a context still holding the write would be the same lie
    /// with better manners.
    @Test func aBankedFocusSessionAnswersTrue() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = AppTask(title: "Write the section")
        context.insert(task)
        try context.save()

        let answered = CadenceTaskStatusEditing.completeFocusSession(
            task,
            elapsedSeconds: 25 * 60,
            in: context,
            reconciler: .inert
        )

        #expect(answered, "the stopwatch is only reset on a true answer")
        #expect(task.status == .done)
        #expect(task.completedAt != nil)
        #expect(task.actualMinutes == 25, "the elapsed clock was banked, not discarded")
        #expect(!context.hasChanges, "answered true over a write still pending in the context")
    }

    /// A second session on the same task answers true as well, and adds to the ledger rather than
    /// replacing it. This is the shape `iOSFocusView` produces when a task is reopened and worked
    /// again, and it is the case a `return` hard-coded to the *first* call's outcome would miss.
    @Test func aSecondSessionOnTheSameTaskAnswersTrueAndAddsToTheMinutes() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = AppTask(title: "Write the section")
        context.insert(task)
        try context.save()

        #expect(CadenceTaskStatusEditing.completeFocusSession(
            task, elapsedSeconds: 10 * 60, in: context, reconciler: .inert
        ))
        CadenceTaskStatusEditing.setStatus(.todo, for: task, in: context, reconciler: .inert)

        #expect(CadenceTaskStatusEditing.completeFocusSession(
            task, elapsedSeconds: 5 * 60, in: context, reconciler: .inert
        ))
        #expect(task.actualMinutes == 15)
        #expect(task.status == .done)
    }
}
