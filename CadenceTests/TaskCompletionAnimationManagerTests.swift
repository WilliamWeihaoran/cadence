#if os(macOS)
import AppKit
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
        // completion animation: the task must still read as "not done" so it
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
    /// `modelContext`, which any task the manager can see has. This waits out the real fill
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

        try await waitOutTheFill { task.status == .done }

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

        try await waitOutTheFill { task.status == .cancelled }

        #expect(task.status == .cancelled)
        // T-202: a cancellation records when the task stopped being open, exactly as a completion does.
        #expect(task.completedAt != nil)
        let next = try spawnedTask(for: task, in: context)
        #expect(next != nil, "the contextless cancellation path did not spawn the next occurrence")
        #expect(next?.status == .todo)
    }

    // MARK: - T-3098: the settle follows the task, not the injection

    /// **The macOS context swap, simulated end to end.** `macOSRootView.refreshAppData()` replaces
    /// the app's `ModelContext` when another process writes the store, and the `.onAppear` that
    /// injected `manager.modelContext` is outside both `.id(dataRefreshID)` subtrees, so it never
    /// re-runs: every row the user can see is re-fetched through the *replacement* context while
    /// this manager still names the retired one.
    ///
    /// Two contexts over one in-memory container is that situation exactly. `retired` is the stale
    /// injection; `live` is what the rebuilt subtree reads and therefore where the task the user
    /// clicks actually lives. Committing the settle through `retired` leaves `task.status` dirty on
    /// `live` and saves a context that has nothing to save — the completion simply never reaches
    /// the store, which `audit`, a third context that can only see what was written, is here to
    /// catch. The successor row goes the same way.
    @Test func aSettleCommitsThroughTheContextTheTaskLivesInNotTheInjectedOne() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let retired = ModelContext(container)
        let live = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let injected = manager.modelContext
        manager.modelContext = retired
        defer { manager.modelContext = injected }

        let seeded = AppTask(title: "water the plants")
        seeded.recurrenceRule = .daily
        seeded.scheduledDate = "2026-08-04"
        retired.insert(seeded)
        try retired.save()

        // Re-fetched through the replacement context, which is the only way the rebuilt subtree
        // can hand a row to the completion control after a refresh.
        let task = try #require(
            try live.fetch(FetchDescriptor<AppTask>()).first { $0.id == seeded.id }
        )
        #expect(task !== seeded)

        manager.toggleCompletion(for: task)
        try await waitOutTheFill { task.status == .done }
        #expect(task.status == .done)

        let audit = ModelContext(container)
        let persisted = try #require(
            try audit.fetch(FetchDescriptor<AppTask>()).first { $0.id == seeded.id }
        )
        #expect(
            persisted.status == .done,
            "the completion was committed through the retired context, so it never reached the store"
        )
        #expect(persisted.completedAt != nil)

        let spawnedID = try #require(task.recurrenceSpawnedTaskID)
        let successor = try audit.fetch(FetchDescriptor<AppTask>()).first { $0.id == spawnedID }
        #expect(successor != nil)
        #expect(successor?.status == .todo)
    }

    /// **The crash candidate, with something real to cross.** The test above seeds a bare task, so
    /// restoring the old precedence had no relationship to carry between contexts and could only
    /// lose the write. This one gives the task the five things `makeNextRecurringTask` copies onto
    /// the successor — `area`, `project`, `context`, `goal` and `tags` — before
    /// `spawnNextOccurrenceIfNeeded` reaches `context.insert(nextTask)`.
    ///
    /// Reached through `live`, every one of those relationships resolves to `live`'s copy, so the
    /// successor is built entirely out of `live` objects. Handing `retired` to the insert is then
    /// the shape T-3098 leads with. Under the fix there is no second context in the picture at all:
    /// the successor is built from `live` objects and inserted into `live`, and the audit context
    /// — which can only see what was actually written — finds it wearing every relationship.
    @Test func aRecurringTaskCarriesItsRelationshipsIntoTheSuccessorAcrossASwap() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let retired = ModelContext(container)
        let live = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let injected = manager.modelContext
        manager.modelContext = retired
        defer { manager.modelContext = injected }

        let workContext = Context(name: "Home")
        let area = Area(name: "Garden", context: workContext)
        let project = Project(name: "Plants", context: workContext, area: area)
        let goal = Goal(title: "Keep everything alive")
        let tag = Tag(name: "watering")
        let seeded = AppTask(title: "water the plants")
        seeded.recurrenceRule = .daily
        seeded.scheduledDate = "2026-08-04"
        for model in [workContext, area, project, goal, tag, seeded] as [any PersistentModel] {
            retired.insert(model)
        }
        seeded.context = workContext
        seeded.area = area
        seeded.project = project
        seeded.goal = goal
        seeded.tags = [tag]
        try retired.save()

        let task = try #require(
            try live.fetch(FetchDescriptor<AppTask>()).first { $0.id == seeded.id }
        )
        #expect(task !== seeded)
        // The relationships the successor will be built from are `live`'s, not `retired`'s. This is
        // the premise the whole test rests on, so it is asserted rather than assumed.
        #expect(task.area !== area)
        #expect(task.project !== project)
        #expect(task.context !== workContext)
        #expect(task.sortedTags.first !== tag)

        manager.toggleCompletion(for: task)
        try await waitOutTheFill { task.status == .done }
        #expect(task.status == .done)

        let audit = ModelContext(container)
        let persisted = try #require(
            try audit.fetch(FetchDescriptor<AppTask>()).first { $0.id == seeded.id }
        )
        #expect(persisted.status == .done)

        let spawnedID = try #require(task.recurrenceSpawnedTaskID)
        let successor = try #require(
            try audit.fetch(FetchDescriptor<AppTask>()).first { $0.id == spawnedID }
        )
        #expect(successor.area?.id == area.id)
        #expect(successor.project?.id == project.id)
        #expect(successor.context?.id == workContext.id)
        #expect(successor.goal?.id == goal.id)
        #expect(successor.sortedTags.map(\.id) == [tag.id])
    }

    /// The injected context is still the fallback, and T-357's branch below it is still reachable.
    /// A task registered in no context at all has nothing to ask, so `settleContext(for:)` must
    /// answer with the injection rather than dropping to the series-skipping path.
    @Test func aTaskWithNoContextOfItsOwnStillSettlesThroughTheInjectedOne() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let injected = manager.modelContext
        manager.modelContext = context
        defer { manager.modelContext = injected }

        let task = AppTask(title: "water the plants")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-08-04"
        #expect(task.modelContext == nil)

        manager.toggleCompletion(for: task)
        try await waitOutTheFill { task.status == .done }

        #expect(task.status == .done)
        let next = try spawnedTask(for: task, in: context)
        #expect(next != nil, "the injected fallback was lost, so the series stopped here")
    }

    // MARK: - T-5360: a quit inside the fill must not lose the tick

    /// **The bug, stated:** the `.done` write waited behind the fill's in-memory sleep and
    /// nothing settled it on quit, so a Cmd+Q inside that window brought the task back open on the
    /// next launch. Driven through the real quit hook, so a delegate that stops calling the settle
    /// fails here too; `audit` can only see what was committed.
    @Test func quittingInsideTheFillCommitsThePendingCompletionAndCancellation() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let injected = manager.modelContext
        manager.modelContext = context
        defer { manager.modelContext = injected }

        let ticked = AppTask(title: "file the report")
        let dropped = AppTask(title: "call the plumber")
        context.insert(ticked)
        context.insert(dropped)
        try context.save()

        manager.toggleCompletion(for: ticked)
        manager.toggleCancellation(for: dropped)
        #expect(manager.isPending(ticked))
        #expect(manager.isPendingCancel(dropped))

        CadenceAppDelegate().applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        #expect(!manager.isPending(ticked))
        #expect(!manager.isPendingCancel(dropped))
        let audit = ModelContext(container)
        let persisted = try audit.fetch(FetchDescriptor<AppTask>())
        #expect(persisted.first { $0.id == ticked.id }?.status == .done, "the pending completion was lost on quit")
        #expect(persisted.first { $0.id == dropped.id }?.status == .cancelled, "the pending cancellation was lost on quit")
        #expect(context.hasChanges == false)
    }

    /// The settle replaces the timer's write; it must not be followed by it. A recurring task
    /// settled twice would spawn two successors, so this waits past the fill and counts them.
    @Test func aSettleOnQuitIsNotRepeatedWhenTheFillWouldHaveEnded() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let injected = manager.modelContext
        manager.modelContext = context
        defer { manager.modelContext = injected }

        let task = AppTask(title: "water the plants")
        task.recurrenceRule = .daily
        task.scheduledDate = "2026-08-04"
        context.insert(task)
        try context.save()

        manager.toggleCompletion(for: task)
        manager.settleAllPendingBeforeTermination()
        #expect(task.status == .done)

        let deadline = Date().addingTimeInterval(CadenceTaskCompletionTiming.animationDuration + 1)
        while Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }

        let all = try context.fetch(FetchDescriptor<AppTask>())
        #expect(all.count == 2, "expected the task and exactly one successor")
    }

    // MARK: - Helpers

    /// Waits for the fill's continuation to actually run, rather than for a fixed stretch of wall
    /// clock.
    ///
    /// This was one `Task.sleep(animationDuration + 1.0)`, and that one-second margin was the whole
    /// of what separated a pass from a failure. Measured 2026-09-11: the suite passes **alone** in
    /// 3.56s, and this same test failed inside a full run reporting a **1.60s** duration — shorter
    /// than the sleep it was supposedly performing, so the reading was a distorted clock under load
    /// rather than a slow continuation. The product path was never implicated: nothing outside this
    /// file changed, and the isolated run exercises the same code.
    ///
    /// Polling for the state the caller is about to assert depends on neither the margin nor the
    /// clock. It deliberately **returns** at the deadline rather than throwing, so a continuation
    /// that genuinely never runs still fails on the caller's own `#expect`s, naming the property
    /// that is wrong — a timeout that swallowed that would be a worse test than the flaky one.
    private func waitOutTheFill(until isDone: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(CadenceTaskCompletionTiming.animationDuration + 30)
        while !isDone() {
            if Date() >= deadline { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
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

    // MARK: - T-8202: where the fill is at a given moment

    /// **The fill reaches its confirmation point at half the window, measured not slept.**
    ///
    /// [[T-268]] rules out driving this delay with a sleep: a margin over `animationDuration`
    /// failed here under parallel load, and the clock it was reading was the distorted one, not
    /// the product's. `progress(for:now:)` takes the moment as an argument, so the whole question
    /// — is the ring half full when the owner says the check should appear — is answerable with
    /// arithmetic against the start the manager actually recorded.
    @Test func theCompletionFillIsHalfwayWhenTheConfirmationMarkIsDue() throws {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")
        defer { manager.cancelPending(for: task.id) }

        manager.toggleCompletion(for: task)
        let start = try #require(manager.pendingStartTimes[task.id], "the tap recorded no start time")

        let due = manager.progress(for: task, now: start.addingTimeInterval(CadenceTaskCompletionTiming.confirmationDelay))
        #expect(abs(due - 0.5) < 0.000_001)
        #expect(CadenceTaskCompletionTiming.showsConfirmation(at: due))

        // A tenth of a second earlier it is still only a ring.
        let early = manager.progress(for: task, now: start.addingTimeInterval(CadenceTaskCompletionTiming.confirmationDelay - 0.1))
        #expect(!CadenceTaskCompletionTiming.showsConfirmation(at: early))

        // And the fill is still short of full right up to the end, then clamps.
        //
        // The full reading is taken a hair PAST the duration on purpose. `Date` carries ~7.9e8
        // seconds, so its ULP here is ~1.2e-7: `start.addingTimeInterval(1.2)` rounds, and the
        // elapsed time read back lands a few tens of nanoseconds either side of 1.2. Asking for
        // exactly 1 at exactly the duration is therefore a coin flip against the representation,
        // not an assertion about the product.
        #expect(manager.progress(for: task, now: start.addingTimeInterval(CadenceTaskCompletionTiming.animationDuration - 0.01)) < 1)
        #expect(manager.progress(for: task, now: start.addingTimeInterval(CadenceTaskCompletionTiming.animationDuration + 0.05)) == 1)

        // The deferral is intact through all of it: nothing has been written yet.
        #expect(task.status == .todo)
        #expect(manager.isPending(task))
    }

    /// The same clock for a column as for a card. Shortening one and leaving the other is a
    /// visible inconsistency on the same board, which is why [[T-8202]] moved the number out of
    /// both managers rather than editing two literals.
    @Test func aColumnSweepRunsOnTheSameWindowAsATaskFill() throws {
        let manager = SectionCompletionAnimationManager.shared
        let section = TaskSectionConfig(name: "Shipping")
        defer { manager.cancelPending(for: section.id) }

        manager.toggleCompletion(for: section, getCurrent: { section }, save: { _ in })
        let start = try #require(manager.pendingStartTimes[section.id], "the column control recorded no start time")

        let due = manager.progress(for: section, now: start.addingTimeInterval(CadenceTaskCompletionTiming.confirmationDelay))
        #expect(abs(due - 0.5) < 0.000_001)
        #expect(manager.progress(for: section, now: start.addingTimeInterval(CadenceTaskCompletionTiming.animationDuration - 0.01)) < 1)
        #expect(manager.progress(for: section, now: start.addingTimeInterval(CadenceTaskCompletionTiming.animationDuration + 0.05)) == 1)

        // Still deferred: the column has not been completed or archived by starting the sweep.
        #expect(manager.isPending(section))
        #expect(!section.isCompleted)
    }

    /// The shortened window is still a window: a second tap inside it is the free take-back, and
    /// the column's control behaves the same way. The task side of this is
    /// `tappingCompleteAgainWhilePendingCancelsTheAnimationInstead`; this is its column half.
    @Test func aSecondTapOnAColumnInsideTheWindowTakesTheCompletionBack() {
        let manager = SectionCompletionAnimationManager.shared
        let section = TaskSectionConfig(name: "Shipping")
        var saved: [TaskSectionConfig] = []

        manager.toggleCompletion(for: section, getCurrent: { section }, save: { saved.append($0) })
        #expect(manager.isPending(section))

        manager.toggleCompletion(for: section, getCurrent: { section }, save: { saved.append($0) })

        #expect(!manager.isPending(section))
        #expect(saved.isEmpty, "the take-back wrote the column anyway")
        #expect(!section.isCompleted)
    }

    /// **The drawing reads the shared threshold; it does not keep one of its own ([[T-8202]]).**
    ///
    /// The confirmation mark's cue is a *fraction of the window*, so a literal in the view is a
    /// number that silently stops meaning "halfway" the next time the window moves — which is
    /// exactly how a 2.5s fill ended up confirming at 1.75s. This is a source scan because the
    /// comparison lives inside a `body`, which a unit test cannot reach.
    @Test func theCompletionGlyphAsksTheSharedTimingWhenToShowItsMark() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskCompletionAnimationViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)

        // Non-vacuity: the read found the right file, and the stripper ran without shortening it.
        #expect(code.contains("struct TaskCompletionProgressGlyph"), "the scan did not read the glyph's file")
        #expect(code != raw, "nothing was stripped, so the scan is reading prose as code")
        #expect(code.count == raw.count, "the stripper changed the length, so offsets no longer hold")

        #expect(
            CadenceSourceScan.matchCount(#"CadenceTaskCompletionTiming\.showsConfirmation\(at: clampedProgress\)"#, in: code) == 1,
            "the glyph no longer asks the shared timing when to show its mark"
        )

        // And it decides nothing itself. The needle is a comparison against the progress value, so
        // `0.75` on the spring's damping and the `0`/`1` of the clamp are left alone by design.
        let comparison = #"clampedProgress\s*[<>]=?\s*[0-9.]+"#
        #expect(CadenceSourceScan.matchCount(comparison, in: code) == 0, "the glyph spells its own threshold again")

        // The needle really would see one. Without this the assertion above passes on a typo.
        #expect(CadenceSourceScan.matchCount(comparison, in: "let shown = clampedProgress > 0.7") == 1)
        #expect(CadenceSourceScan.matchCount(comparison, in: "let shown = somethingElse > 0.7") == 0)
    }
}
#endif
