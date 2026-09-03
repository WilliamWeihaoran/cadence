import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-344 decided, and T-357 pinned.** Two things this file exists to stop.
///
/// The first is a product question the audit filed rather than answered: what does the completion
/// circle *mean* on a cancelled task? The answer implemented here is that the circle toggles
/// **settled**, not **done** — see `CadenceTaskMutationSupport.toggleCompletion` for the reasoning.
/// The behavioural tests pin the transition and the source scan pins that the four labels
/// describing that gesture read the same predicate that decides it, because a label and an action
/// disagreeing is the state T-344 reported.
///
/// The second is structural. `TaskCompletionAnimationManager` had two different direct
/// `task.status =` assignments found by two independent audits ([[T-341]], [[T-357]]). Fixing the
/// two known ones invites a third, so the scan below bans the *shape* rather than the two
/// instances.
@MainActor
struct CadenceTaskStatusLifecycleSurfaceTests {

    /// A commit that always refuses, the way every other save-commit suite here spells it.
    private struct CommitRefused: Error {}

    // MARK: - T-628: the settle has a commit boundary

    /// **The macOS completion funnel had no commit at all.**
    ///
    /// `TaskCompletionAnimationManager.write` → `TaskWorkflowService.markDone(_:in:)` →
    /// `CadenceTaskRecurrenceWorkflowSupport.markDone` → `spawnNextOccurrenceIfNeeded`, which does
    /// `context.insert(nextTask)` — and nothing in that chain saved. Ticking a recurring task's
    /// circle therefore minted its successor as a *pending* row, for the next unrelated `save()`
    /// from any other screen to take or the next unrelated `rollback()` to discard.
    ///
    /// A settle is two changes at once, so this pins both undos: the successor is un-inserted, and
    /// the status, timestamp and `recurrenceSpawnedTaskID` are put back. That is what lets the
    /// alert say "Nothing was changed" and lets the circle re-draw open honestly.
    @Test func aRefusedSettleUnInsertsTheSuccessorAndPutsTheStatusBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(task)
        try context.save()

        #expect(throws: (any Error).self) {
            try TaskWorkflowService.commitMarkDone(task, in: context) { _ in
                throw CommitRefused()
            }
        }

        #expect(task.status == .todo, "the status went back")
        #expect(task.completedAt == nil)
        #expect(task.recurrenceSpawnedTaskID == nil, "and so did the pointer at the successor")
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1, "no successor was left pending")
    }

    /// The same commit, accepted: the successor exists and the pointer names it. Without this the
    /// test above passes on a `commitMarkDone` that settles nothing at all.
    @Test func anAcceptedSettleCommitsTheSuccessorItSpawned() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(task)
        try context.save()

        try TaskWorkflowService.commitMarkDone(task, in: context)

        #expect(task.status == .done)
        #expect(task.recurrenceSpawnedTaskID != nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 2)
    }

    // MARK: - T-636(a): so does the shared spine every other surface reaches

    /// **The macOS funnel was only half the spine.** T-628 gave
    /// `TaskCompletionAnimationManager.write` a commit boundary; the *shared*
    /// `CadenceTaskMutationSupport.toggleCompletion` still ended `try? modelContext.save()` over
    /// the same `spawnNextOccurrenceIfNeeded` insert, and that is the entry point every iOS
    /// checkbox, swipe and card reaches through `CadenceTaskStatusEditing`.
    ///
    /// Same two undos as its macOS sibling, because it is the same sentence now — the body moved
    /// to `CadenceTaskMutationSupport.commitSettle` and the Mac spelling delegates.
    @Test func aRefusedToggleUnInsertsTheSuccessorAndPutsTheStatusBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(task)
        try context.save()

        #expect(throws: (any Error).self) {
            try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context) { _ in
                throw CommitRefused()
            }
        }

        #expect(task.status == .todo, "the status went back")
        #expect(task.completedAt == nil)
        #expect(task.recurrenceSpawnedTaskID == nil, "and so did the pointer at the successor")
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1, "no successor was left pending")
    }

    /// The same toggle, accepted: the successor is in the store and nothing is left pending.
    /// Without this the test above passes on a `toggleCompletion` that settles nothing at all.
    @Test func anAcceptedToggleCommitsTheSuccessorRatherThanLeavingItPending() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(task)
        try context.save()

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

        #expect(task.status == .done)
        #expect(task.recurrenceSpawnedTaskID != nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 2)
        #expect(!context.hasChanges, "the successor was left pending in the context")
    }

    /// The other direction. Restoring inserts nothing, so its undo is an ordinary `commitEdit`
    /// over the two fields `markTodo` writes — and a refused restore must leave the task settled
    /// rather than half-reopened, which is the state a `try?` here produced.
    @Test func aRefusedRestoreLeavesTheTaskSettled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "finished")
        task.status = .done
        let finishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        task.completedAt = finishedAt
        context.insert(task)
        try context.save()

        #expect(throws: (any Error).self) {
            try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context) { _ in
                throw CommitRefused()
            }
        }

        #expect(task.status == .done, "the circle re-drew open over a store that still holds it done")
        #expect(task.completedAt == finishedAt)
    }

    /// One settle-commit, not two agreeing copies. `TaskWorkflowService.commitSettle` was written
    /// for T-628 inside `#if os(macOS)` while importing nothing platform-specific; the iOS spine
    /// needed the identical sentence, so the body moved to `Shared/` and the Mac spelling is the
    /// delegation and nothing else. Stated as the whole body for the reason
    /// `theMacSpellingDelegatesToTheSharedMutation` gives two files over: a second body added
    /// underneath a delegating call leaves a `contains(…)` exactly where it was.
    @Test func theMacSettleCommitDelegatesToTheSharedOne() throws {
        let source = try strippingComments(sourceFile("Cadence/macOS/Services/TaskWorkflowService.swift"))
        let body = try cadenceFunctionBody("private static func commitSettle(", in: source)
        #expect(
            body.trimmingCharacters(in: .whitespacesAndNewlines)
                == "try CadenceTaskMutationSupport.commitSettle(task, in: context, commit: commit, settle)",
            "TaskWorkflowService.commitSettle has grown a body of its own: \(body)"
        )
        // And the shared one really is the body that moved, rather than a third spelling.
        let shared = try strippingComments(sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift"))
        let sharedBody = try cadenceFunctionBody("static func commitSettle(", in: shared)
        #expect(sharedBody.contains("CadencePendingChangePersistence.commitInsert(of: spawned"))
        #expect(sharedBody.contains("task.recurrenceSpawnedTaskID = spawnedTaskID"))
    }

    /// **The refusal is named once, at the shell.** The wrapper catches rather than rethrows
    /// because one of its six callers is `iOSTaskSwipeActions.trailing`, a `static func` returning
    /// closures with no view state at all — so there is no "where the user is already looking" for
    /// it to report into. macOS reached the same answer in T-628 and put the notice on the manager
    /// for `macOSRootView` to show; this is that shape on the other platform.
    @Test func theAppSideWrapperNamesARefusedSettleRatherThanSwallowingIt() throws {
        let wrapper = try strippingComments(sourceFile("Cadence/Shared/CadenceTaskStatusEditing.swift"))
        let body = try cadenceFunctionBody("static func toggleCompletion(", in: wrapper)
        #expect(body.contains("try CadenceTaskMutationSupport.toggleCompletion("))

        // The refusal is recorded, and the reconcile is *skipped* — reconciling a transition that
        // was put back would retire a reminder for work that is still open.
        let record = try #require(body.range(of: "CadenceTaskSettleFailureCenter.shared.record()"))
        let reconcile = try #require(body.range(of: "reconcile(context, reconciler)"))
        #expect(record.lowerBound < reconcile.lowerBound)
        #expect(
            body[record.upperBound..<reconcile.lowerBound].contains("return"),
            "a refused settle falls through to the reconcile"
        )

        // And the one surface that reads it is the shell both iOS layouts pass through.
        let shell = try strippingComments(sourceFile("Cadence/iOS/iOSRootView.swift"))
        #expect(shell.contains("CadenceTaskMutationSupport.settleFailureAlertTitle"))
        #expect(shell.contains("CadenceTaskSettleFailureCenter.shared.settleFailed"))
        #expect(shell.contains("CadencePendingChangePersistence.editFailureNotice"))
    }

    /// The centre is inert until something records, and clearable afterwards — otherwise the alert
    /// above is either always up or never up, and the scan that finds it proves neither.
    @Test func theSettleFailureCentreIsInertUntilARefusalIsRecorded() throws {
        let centre = CadenceTaskSettleFailureCenter.shared
        centre.clear()
        #expect(!centre.settleFailed)

        centre.record()
        #expect(centre.settleFailed)

        centre.clear()
        #expect(!centre.settleFailed)
    }

    // MARK: - T-643: the spine's other half, reached by an explicit status

    /// **`setStatus` is `toggleCompletion`'s other door onto the same insert.** T-636(a) gave the
    /// toggle a commit boundary and left this one, because two of the files that reach it were
    /// owned by another change in flight. It is the same defect through a different door:
    /// `applyStatusCompletion` → `markDone`/`markCancelled` → `spawnNextOccurrenceIfNeeded` →
    /// `context.insert`, under a `try? modelContext.save()`.
    ///
    /// `.cancelled` rather than `.done` here on purpose: it is the transition `toggleCompletion`
    /// cannot spell, so it is the one only this entry point can leave pending, and it spawns the
    /// successor exactly as `markDone` does (T-202's rule — a cancelled occurrence skips, the
    /// series carries on).
    @Test func aRefusedCancelUnInsertsTheSuccessorAndPutsTheStatusBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(task)
        try context.save()

        #expect(throws: (any Error).self) {
            try CadenceTaskMutationSupport.setStatus(.cancelled, for: task, modelContext: context) { _ in
                throw CommitRefused()
            }
        }

        #expect(task.status == .todo, "the status went back")
        #expect(task.completedAt == nil)
        #expect(task.recurrenceSpawnedTaskID == nil, "and so did the pointer at the successor")
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1, "no successor was left pending")
    }

    /// The same transition, accepted: the successor is in the store rather than pending in the
    /// context. Without this the test above passes on a `setStatus` that settles nothing at all.
    @Test func anAcceptedStatusSettleCommitsTheSuccessorRatherThanLeavingItPending() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(task)
        try context.save()

        try CadenceTaskMutationSupport.setStatus(.done, for: task, modelContext: context)

        #expect(task.status == .done)
        #expect(task.recurrenceSpawnedTaskID != nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 2)
        #expect(!context.hasChanges, "the successor was left pending in the context")
    }

    /// **The open half's undo is an edit, not a settle.** `.todo` and `.inProgress` insert nothing
    /// — `applyStatusCompletion` writes two fields and stops — so there is no successor to
    /// un-insert and the undo is an ordinary `commitEdit` over exactly those two fields. A refused
    /// re-open must leave the task settled, which is the state the swallow could not produce: it
    /// left the row reading `.inProgress` over a store that still holds it done.
    @Test func aRefusedReopenThroughSetStatusLeavesTheTaskSettled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "finished")
        task.status = .done
        let finishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        task.completedAt = finishedAt
        context.insert(task)
        try context.save()

        #expect(throws: (any Error).self) {
            try CadenceTaskMutationSupport.setStatus(.inProgress, for: task, modelContext: context) { _ in
                throw CommitRefused()
            }
        }

        #expect(task.status == .done, "the row re-drew in progress over a store that still holds it done")
        #expect(task.completedAt == finishedAt, "and the timestamp it cleared never came back")
    }

    /// The accepted open half, so the refusal above is not green over a `setStatus` that never
    /// reaches `.inProgress` at all.
    @Test func anAcceptedReopenThroughSetStatusClearsTheCompletionTimestamp() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "finished")
        task.status = .done
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(task)
        try context.save()

        try CadenceTaskMutationSupport.setStatus(.inProgress, for: task, modelContext: context)

        #expect(task.status == .inProgress)
        #expect(task.completedAt == nil)
        #expect(!context.hasChanges, "the re-open was left pending in the context")
    }

    /// `applyStatusCompletion` hands the successor back rather than swallowing it, for the reason
    /// `spawnNextOccurrenceIfNeeded` returns it at all: `commitInsert` un-inserts the objects it
    /// was given, so the one object that must come back up the chain is the one that was inserted.
    /// The two open cases have nothing to hand back, and saying so is what makes the branch above
    /// an edit rather than a settle.
    @Test func applyStatusCompletionAnswersWithTheSuccessorItSpawned() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Repeats daily")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-05-01"
        context.insert(task)
        try context.save()

        let spawned = CadenceTaskMutationSupport.applyStatusCompletion(.done, to: task, modelContext: context)
        #expect(spawned != nil, "the settle answered nil over a task that spawned a successor")
        #expect(spawned?.id == task.recurrenceSpawnedTaskID, "the answer is not the row the pointer names")

        let open = AppTask(title: "open")
        context.insert(open)
        #expect(
            CadenceTaskMutationSupport.applyStatusCompletion(.inProgress, to: open, modelContext: context) == nil,
            "an open status inserted something"
        )
    }

    /// The wrapper names this refusal the way it names the toggle's, and for the same reason: the
    /// surface that reaches it is `iOSTaskDetailSheet`'s status well, and a notice owned by one
    /// surface is missing from the rest. One centre, one alert, read at the shell.
    @Test func theAppSideWrapperNamesARefusedStatusChangeRatherThanSwallowingIt() throws {
        let wrapper = try strippingComments(sourceFile("Cadence/Shared/CadenceTaskStatusEditing.swift"))
        let body = try cadenceFunctionBody("static func setStatus(", in: wrapper)
        #expect(body.contains("try CadenceTaskMutationSupport.setStatus("))

        let record = try #require(body.range(of: "CadenceTaskSettleFailureCenter.shared.record()"))
        let reconcile = try #require(body.range(of: "reconcile(context, reconciler)"))
        #expect(record.lowerBound < reconcile.lowerBound)
        #expect(
            body[record.upperBound..<reconcile.lowerBound].contains("return"),
            "a refused status change falls through to the reconcile"
        )
    }

    // MARK: - T-344: the circle toggles settled, not done

    @Test func theCircleRestoresACancelledTaskRatherThanCompletingIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "abandoned")
        task.status = .cancelled
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(task)
        try context.save()

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
    }

    @Test func theCircleStillRestoresADoneTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "finished")
        task.status = .done
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(task)
        try context.save()

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
    }

    @Test func theCircleStillCompletesAnOpenTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        for status in [TaskStatus.todo, .inProgress] {
            let task = AppTask(title: "open \(status.rawValue)")
            task.status = status
            context.insert(task)
            try context.save()

            try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

            #expect(task.status == .done)
            #expect(task.completedAt != nil)
        }
    }

    /// Says the rule instead of listing its cases: the toggle's destination is decided by
    /// `isFinishedTask` and nothing else, so a fifth `TaskStatus` cannot land in a gap.
    @Test func theCircleSendsExactlyTheFinishedStatusesBackToTodo() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        var sawFinished = false
        var sawOpen = false

        for status in TaskStatus.allCases {
            let task = AppTask(title: "task \(status.rawValue)")
            task.status = status
            context.insert(task)
            try context.save()
            let wasFinished = CadenceTaskQuerySupport.isFinishedTask(task)
            sawFinished = sawFinished || wasFinished
            sawOpen = sawOpen || !wasFinished

            try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

            #expect(
                task.status == (wasFinished ? .todo : .done),
                "\(status) is \(wasFinished ? "finished" : "open") and the toggle sent it to \(task.status)"
            )
        }

        // Non-vacuity: the loop must have exercised both halves of the rule.
        #expect(sawFinished)
        #expect(sawOpen)
    }

    /// The reason the decision went this way round rather than the other: `markDone` advances a
    /// recurring series. Under the old rule, a tap meant to un-cancel a recurring task minted a
    /// fresh live occurrence of it; under this one it does not.
    @Test func restoringACancelledRecurringTaskDoesNotMintANewOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "weekly review")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-08-04"
        task.status = .cancelled
        task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(task)
        try context.save()

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)

        let all = try context.fetch(FetchDescriptor<AppTask>())
        #expect(task.status == .todo)
        #expect(task.recurrenceSpawnedTaskID == nil)
        #expect(all.count == 1)
    }

    // MARK: - T-344: the labels describe the gesture they trigger

    /// Four places name what a tap or a swipe on the completion control will do. All four now ask
    /// `isFinishedTask`, so none of them can promise "Done" on a task the tap will restore.
    ///
    /// **`iOSTaskViews` no longer asks the predicate, and that is an upgrade rather than a regression
    /// (T-611).** Its circle now reads `CadenceTaskCompletionState.accessibilityActionLabel`, whose
    /// five branches mirror `handleTap()` — including the two this binary predicate cannot express:
    /// mid-fill, a second tap *cancels*, so `isFinishedTask` would name the wrong action. macOS's
    /// circle made the same move in T-594. The rule this test exists to enforce is "the label names
    /// what the gesture will do"; a state keyed on the gesture serves that strictly better than a
    /// predicate keyed on the outcome, so the file is pinned against the shared property below
    /// instead of being dragged back to the predicate.
    ///
    /// It stays in the `isDone`-branching sweep further down — that half is still exactly right.
    @Test func everyLabelForTheCompletionGestureReadsTheSamePredicate() throws {
        try expectOccurrences(
            of: "CadenceTaskQuerySupport.isFinishedTask(task)",
            at: [
                // One `let isFinished`, read by the swipe's title, image and tint.
                "Cadence/iOS/iOSTaskRowActionViews.swift": 1,
                "Cadence/iOS/iOSTaskDetailComponents.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1
            ]
        )
        // The file that left the predicate must be reading the shared answer, not spelling its own.
        try expectOccurrences(
            of: "glyph.state.accessibilityActionLabel",
            at: ["Cadence/iOS/iOSTaskViews.swift": 1]
        )
        try expectOccurrences(of: "isFinished ?", at: ["Cadence/iOS/iOSTaskRowActionViews.swift": 3])

        // And no label in those files still branches on `isDone` alone. The needle carries a
        // leading non-identifier character on purpose: `subtask.isDone ? "Mark subtask todo"` in
        // the detail components is a *subtask's* control, correct as it stands, and a bare
        // `task.isDone ? "` needle would fail on it.
        for path in [
            "Cadence/iOS/iOSTaskRowActionViews.swift",
            "Cadence/iOS/iOSTaskViews.swift",
            "Cadence/iOS/iOSTaskDetailComponents.swift",
            "Cadence/iOS/iOSBoardCards.swift"
        ] {
            let code = try strippingComments(sourceFile(path))
            #expect(
                code.matchCount(ofPattern: taskLevelDoneLabel) == 0,
                "\(path) still labels a task-level completion control by isDone alone"
            )
        }

        // The needle is not vacuous, and it does not reach the spelling that is fine.
        #expect(#"title: task.isDone ? "Todo" : "Done""#.matchCount(ofPattern: taskLevelDoneLabel) == 1)
        #expect(#"(task.isDone ? "Mark not done" : "Mark done")"#.matchCount(ofPattern: taskLevelDoneLabel) == 1)
        #expect(#"(subtask.isDone ? "Mark subtask todo" : "Complete subtask")"#.matchCount(ofPattern: taskLevelDoneLabel) == 0)
    }

    /// The shared toggle is the one place the decision lives; the macOS animation manager defers to
    /// the same predicate rather than keeping its own copy of the rule.
    @Test func bothToggleEntryPointsReadTheFinishedPredicate() throws {
        try expectOccurrences(
            of: "if CadenceTaskQuerySupport.isFinishedTask(task)",
            at: [
                "Cadence/Shared/CadenceTaskMutationSupport.swift": 1,
                "Cadence/macOS/Services/TaskCompletionAnimationManager.swift": 1
            ]
        )
        try expectOccurrences(
            of: "if task.isDone {",
            at: [
                "Cadence/Shared/CadenceTaskMutationSupport.swift": 0,
                "Cadence/macOS/Services/TaskCompletionAnimationManager.swift": 0
            ]
        )
    }

    // MARK: - T-357: no status write in the animation manager escapes the shared path

    /// Two audits, two different bypasses, one file. This bans the shape rather than the two
    /// instances: nothing in `TaskCompletionAnimationManager` may assign `status` or `completedAt`,
    /// and the three transitions it performs must each reach the shared workflow exactly once.
    ///
    /// A behavioural test cannot do this job. The contextless branch is unreachable in the shipping
    /// app — the manager's context is injected on root appear — so a *new* direct assignment added
    /// beside the funnel would break no behaviour anyone could observe until it did.
    @Test func noStatusIsAssignedDirectlyInTheAnimationManager() throws {
        let path = "Cadence/macOS/Services/TaskCompletionAnimationManager.swift"
        let code = try strippingComments(sourceFile(path))

        #expect(code.matchCount(ofPattern: directStatusAssignment) == 0, "\(path) assigns a task's status directly")
        #expect(code.matchCount(ofPattern: directCompletedAtAssignment) == 0, "\(path) stamps completedAt directly")

        // Every transition goes through the macOS wrapper, which is what adds the notification
        // reconcile hop around the shared recurrence transitions.
        //
        // **The two settling spellings are the *committing* ones since T-628**, and the pin moved
        // with them rather than being relaxed. The claim it makes is unchanged — one funnel,
        // reached once per transition — but the funnel now has a commit boundary in it, because
        // `markDone` reaches `spawnNextOccurrenceIfNeeded`, which inserts. The uncommitted
        // spellings must not come back beside them, so they are pinned at zero.
        try expectOccurrences(
            of: "TaskWorkflowService.commitMarkDone(task, in: $0)",
            at: [path: 1]
        )
        try expectOccurrences(
            of: "TaskWorkflowService.commitMarkCancelled(task, in: $0)",
            at: [path: 1]
        )
        try expectOccurrences(of: "TaskWorkflowService.markDone(", at: [path: 0])
        try expectOccurrences(of: "TaskWorkflowService.markCancelled(", at: [path: 0])
        try expectOccurrences(of: "TaskWorkflowService.markTodo(task)", at: [path: 1])
        // One funnel, and every call site of it.
        try expectOccurrences(of: "private func write(", at: [path: 1])
        try expectOccurrences(of: "write(.restored, to: task)", at: [path: 2])
        try expectOccurrences(of: "self.write(.done, to: task)", at: [path: 1])
        try expectOccurrences(of: "self.write(.cancelled, to: task)", at: [path: 1])

        // The needles are not vacuous, and they do not fire on a comparison or an equality test.
        #expect("task.status = .todo".matchCount(ofPattern: directStatusAssignment) == 1)
        #expect("self.task.status = status".matchCount(ofPattern: directStatusAssignment) == 1)
        #expect("task.status == .todo".matchCount(ofPattern: directStatusAssignment) == 0)
        #expect("status: task.status,".matchCount(ofPattern: directStatusAssignment) == 0)
        #expect("task.completedAt = Date()".matchCount(ofPattern: directCompletedAtAssignment) == 1)
        #expect("task.completedAt == nil".matchCount(ofPattern: directCompletedAtAssignment) == 0)
    }

    // MARK: - T-342: the freeze filter reads the shared predicate

    /// `TaskSurfaceFreezeSupportTests` pins the behaviour; this pins that it is the *shared*
    /// predicate doing it rather than a second local spelling of "done or cancelled", which is the
    /// defect shape T-374 is about.
    @Test func theFrozenSurfaceFiltersOnTheSharedFinishedPredicate() throws {
        // Two resolvers now, in `TaskSurfaceFreezeModels`. The audit counted two and this test
        // once counted four: `TasksPanel` hand-rolled `resolvedFrozenListGroups` and
        // `resolvedFrozenFlatSections` with a different result type, and both were readers of the
        // `.byDoDate` frozen snapshots — unreachable, and deleted with the mode in T-487. The
        // shared pair is what Today has always gone through, so the rule this pins is intact; the
        // two zeros below still hold `TasksPanel` to it if the hand-rolled shape ever comes back.
        try expectOccurrences(
            of: "CadenceTaskQuerySupport.isFinishedTask($0)",
            at: [
                "Cadence/macOS/Views/TaskSurfaceFreezeModels.swift": 2
            ]
        )
        try expectOccurrences(
            of: "!$0.isDone",
            at: [
                "Cadence/macOS/Views/TaskSurfaceFreezeModels.swift": 0,
                "Cadence/macOS/Views/TasksPanel.swift": 0
            ]
        )
        // And neither file grew a second local spelling of the rule beside the shared one.
        try expectOccurrences(
            of: "isCancelled",
            at: [
                "Cadence/macOS/Views/TaskSurfaceFreezeModels.swift": 0,
                "Cadence/macOS/Views/TasksPanel.swift": 0
            ]
        )
    }

    // MARK: - Non-vacuity

    /// Without this, every zero above could be a scan reading an empty string — the failure mode a
    /// `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSourceScanIsNotVacuousInTaskStatusLifecycleSurface() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")

        let scanned = [
            "Cadence/Shared/CadenceTaskMutationSupport.swift",
            "Cadence/macOS/Services/TaskCompletionAnimationManager.swift",
            "Cadence/macOS/Views/TaskSurfaceFreezeModels.swift",
            "Cadence/macOS/Views/TasksPanel.swift",
            "Cadence/iOS/iOSTaskRowActionViews.swift",
            "Cadence/iOS/iOSTaskViews.swift",
            "Cadence/iOS/iOSTaskDetailComponents.swift",
            "Cadence/iOS/iOSBoardCards.swift"
        ]
        for path in scanned {
            #expect(files.contains(path), "\(path) is not among the files the scan enumerated")
        }

        let manager = try strippingComments(sourceFile("Cadence/macOS/Services/TaskCompletionAnimationManager.swift"))
        #expect(manager.contains("final class TaskCompletionAnimationManager"))
        let mutation = try strippingComments(sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift"))
        #expect(mutation.contains("static func toggleCompletion"))
        let freeze = try strippingComments(sourceFile("Cadence/macOS/Views/TaskSurfaceFreezeModels.swift"))
        #expect(freeze.contains("func applyFrozenTaskOrder"))
        // `private var resolvedFrozenListGroups` / `resolvedFrozenFlatSections` were the two
        // needles here; both were `.byDoDate`-only and went with it (T-487). The scan still has to
        // prove it is reading this file, so it reads something Today actually draws.
        let panel = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(panel.contains("struct TasksPanel: View"))
        #expect(panel.contains("HoverFreezeObserver("))
        let actions = try strippingComments(sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift"))
        #expect(actions.contains("static func trailing("))
    }
}

// MARK: - Needles

/// A task-level completion control labelled by `isDone` alone. The leading `[^A-Za-z0-9_.]` keeps it
/// off `subtask.isDone`, whose control genuinely owns done/todo and nothing else.
private let taskLevelDoneLabel = #"[^A-Za-z0-9_.]task\.isDone \? ""#

/// An assignment to a task's `status`, and not a comparison (`==`), a labelled argument
/// (`status: task.status`) or a pattern match.
private let directStatusAssignment = #"task\.status\s*=\s*[^=]"#

private let directCompletedAtAssignment = #"task\.completedAt\s*=\s*[^=]"#

// MARK: - Source-reading helpers

private extension String {
    func matchCount(ofPattern pattern: String) -> Int {
        var count = 0
        var searchRange = startIndex..<endIndex
        while let found = range(of: pattern, options: .regularExpression, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<endIndex
        }
        return count
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
