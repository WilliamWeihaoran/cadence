#if os(macOS)
import AppKit
import Foundation
import SwiftData
import SwiftUI
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

    /// [[T-8392]]: the reverse of the test above. A completion started while a cancellation is
    /// filling — the swipe's Done, macOS's timeline block — replaces it, so the cancellation's
    /// window has nothing left to close and the task ends done, not cancelled.
    @Test func startingCompletionAbortsAnInFlightCancellationPending() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")
        context.insert(task)
        try context.save()

        manager.toggleCancellation(for: task)
        #expect(manager.isPendingCancel(task))

        manager.toggleCompletion(for: task)

        #expect(manager.isPending(task))
        #expect(!manager.isPendingCancel(task), "both fills are running at once")
        manager.windowClosed(onCancellationOf: task.id)
        manager.windowClosed(onCompletionOf: task.id)
        let audit = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(audit.first { $0.id == task.id }?.status == .done, "the earlier cancellation overrode the completion")
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

    // `theCompletionGlyphAsksTheSharedTimingWhenToShowItsMark` moved to
    // `CadenceTaskCompletionGlyphTests` with the circle it reads ([[T-8411]]).

    // MARK: - T-8203: the same deferred completion on iOS

    /// **The circle's three-tap walk is one decision, on the manager.** It was spelled twice on
    /// macOS (`TaskCompletionButton.handleTap`, `KanbanCardComputedSupport.handleCompletionTap`)
    /// and not at all on iOS, which wrote `.done` on the first tap. Every step keeps the stored
    /// status open: only the window closing writes.
    @Test func theCircleWalksFromOpenToCompletingToCancellingAndBackToOpen() {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "a")
        defer {
            manager.cancelPending(for: task.id)
            manager.cancelCancelPending(for: task.id)
        }
        #expect(manager.glyph(for: task).state == .todo)
        #expect(manager.pendingProgress(for: task) == nil)

        manager.advanceCompletionControl(for: task)
        #expect(manager.isPending(task))
        #expect(!manager.isPendingCancel(task))
        #expect(manager.glyph(for: task).state == .pendingCompletion)
        #expect(manager.pendingProgress(for: task) != nil)

        manager.advanceCompletionControl(for: task)
        #expect(!manager.isPending(task), "a second tap left the completion running")
        #expect(manager.isPendingCancel(task), "a second tap mid-fill must turn into a cancellation, as on macOS")
        #expect(manager.glyph(for: task).state == .pendingCancellation)

        manager.advanceCompletionControl(for: task)
        #expect(!manager.isPending(task))
        #expect(!manager.isPendingCancel(task))
        #expect(manager.glyph(for: task).state == .todo)
        #expect(task.status == .todo, "a tap wrote the status before any window closed")
    }

    /// The timer's own body, driven without sleeping through it ([[T-268]]): closing the window
    /// commits `.done`, and a take-back inside the window leaves it nothing to close.
    @Test func closingTheWindowCommitsTheCompletionUnlessItWasTakenBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let ticked = AppTask(title: "ticked")
        let withdrawn = AppTask(title: "withdrawn")
        context.insert(ticked)
        context.insert(withdrawn)
        try context.save()

        manager.toggleCompletion(for: ticked)
        manager.toggleCompletion(for: withdrawn)
        manager.toggleCompletion(for: withdrawn)
        manager.windowClosed(onCompletionOf: ticked.id)
        manager.windowClosed(onCompletionOf: withdrawn.id)

        #expect(!manager.isPending(ticked))
        let audit = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(audit.first { $0.id == ticked.id }?.status == .done)
        #expect(audit.first { $0.id == withdrawn.id }?.status == .todo, "a take-back still completed the task")
    }

    /// **Hazard 4: a task settled out of process mid-window keeps the settle it was given.**
    /// `CompleteTaskIntent` (a widget), MCP or a second device can finish the task inside the
    /// 1.2s; the window closing afterwards must not re-stamp `completedAt`, and a pending
    /// *cancellation* must not turn finished work into abandoned work.
    @Test func aTaskSettledElsewhereInsideTheWindowKeepsTheSettleItWasGiven() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let earlier = Date(timeIntervalSince1970: 1_800_000_000)
        let completing = AppTask(title: "completing")
        let cancelling = AppTask(title: "cancelling")
        let quitting = AppTask(title: "quitting")
        for task in [completing, cancelling, quitting] { context.insert(task) }
        try context.save()

        manager.toggleCompletion(for: completing)
        manager.toggleCancellation(for: cancelling)
        manager.toggleCompletion(for: quitting)
        for task in [completing, cancelling, quitting] {
            CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries(task, as: .done, now: earlier)
        }
        try context.save()

        manager.windowClosed(onCompletionOf: completing.id)
        manager.windowClosed(onCancellationOf: cancelling.id)
        manager.settleAllPendingBeforeTermination()

        #expect(completing.completedAt == earlier, "the window re-stamped a completion made elsewhere")
        #expect(cancelling.status == .done, "a pending cancellation overwrote a completion made elsewhere")
        #expect(cancelling.completedAt == earlier)
        #expect(quitting.completedAt == earlier, "the termination settle re-stamped a completion made elsewhere")
        #expect(!manager.isPending(completing) && !manager.isPendingCancel(cancelling) && !manager.isPending(quitting))
    }

    /// **Hazard 1: iOS has no Cmd-Q, it has backgrounding.** Leaving `.active` settles the fill as
    /// the macOS quit does; becoming active again settles nothing.
    @Test func leavingTheActivePhaseSettlesTheFillAndReturningToItDoesNot() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let manager = TaskCompletionAnimationManager.shared
        let resumed = AppTask(title: "resumed")
        let switched = AppTask(title: "app switcher")
        let backgrounded = AppTask(title: "home")
        for task in [resumed, switched, backgrounded] { context.insert(task) }
        try context.save()

        manager.toggleCompletion(for: resumed)
        manager.settleAllPending(onLeaving: .active)
        #expect(manager.isPending(resumed), "returning to the app settled a fill the user can still take back")
        #expect(resumed.status == .todo)
        manager.cancelPending(for: resumed.id)

        manager.toggleCompletion(for: switched)
        manager.settleAllPending(onLeaving: .inactive)
        #expect(switched.status == .done, "going inactive left the tick in memory")

        manager.toggleCompletion(for: backgrounded)
        manager.settleAllPending(onLeaving: .background)
        #expect(backgrounded.status == .done, "backgrounding left the tick in memory")
        let audit = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(audit.filter { $0.status == .done }.count == 2)
    }

    /// The iOS wiring, which no macOS test host can run: the three surfaces in scope start the
    /// shared fill rather than writing synchronously, the root settles it on leaving active, and the
    /// circle draws the fill only while one runs and asks the shared timing when to show its mark.
    @Test func theIOSRowCardSwipeAndRootAreWiredToTheSharedDeferredCompletion() throws {
        let row = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        let card = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSBoardCards.swift"))
        let swipe = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift"))
        let root = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootView.swift"))
        let circle = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureComponents.swift"))
        // [[T-8411]]: the drawing is the shared circle's; the iOS file keeps only the live host.
        let drawing = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceTaskCompletionCircle.swift"))
        let manager = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/Shared/TaskCompletionAnimationManager.swift"))
        #expect(row.contains("struct iOSTaskRow"), "non-vacuity: wrong file read")
        #expect(circle.contains("struct iOSTaskCompletionFill"), "non-vacuity: wrong file read")
        #expect(drawing.contains("struct CadenceTaskCompletionCircle"), "non-vacuity: wrong file read")

        for (name, code) in [("row", row), ("card", card)] {
            let toggle = try #require(CadenceSourceScan.functionBody(named: "toggleCompletion", in: code), "\(name) has no toggleCompletion()")
            #expect(toggle.contains("TaskCompletionAnimationManager.shared.advanceCompletionControl(for: task)"), "the \(name)'s circle does not start the shared fill")
            #expect(!code.contains("CadenceTaskStatusEditing.toggleCompletion("), "the \(name) writes completion synchronously again")
            #expect(code.contains("iOSTaskCompletionFill(task: task") || code.contains("iOSTaskCompletionFill(\n"), "the \(name) draws a still circle")
            #expect(code.contains("TaskCompletionAnimationManager.shared.glyph(for: task)"), "the \(name)'s glyph cannot see the pending states")
        }
        #expect(swipe.contains("TaskCompletionAnimationManager.shared.toggleCompletion(for: task)"))
        #expect(!swipe.contains("CadenceTaskStatusEditing.toggleCompletion("), "the swipe writes completion synchronously again")

        let phaseObserver = try #require(
            CadenceSourceScan.declarationBody(".onChange(of: scenePhase)", in: root),
            "the root lost its scene-phase observer"
        )
        #expect(
            phaseObserver.contains("TaskCompletionAnimationManager.shared.settleAllPending(onLeaving: phase)"),
            "the iOS root does not settle a running fill on leaving active, so a killed app drops the tick"
        )

        // Hazard 5: the display-link redraw exists only for a pending glyph, and Reduce Motion stops it.
        #expect(circle.contains("!reduceMotion && (glyph.state == .pendingCompletion || glyph.state == .pendingCancellation)"))
        #expect(drawing.contains("CadenceTaskCompletionTiming.showsConfirmation(at: fill)"))
        let comparison = #"\bfill\s*[<>]=?\s*[0-9.]+"#
        #expect(CadenceSourceScan.matchCount(comparison, in: drawing) == 0, "the circle spells its own confirmation threshold")
        #expect(CadenceSourceScan.matchCount(comparison, in: "let shown = fill > 0.7") == 1)

        // The manager's iOS hop is the iOS status wrapper, so a deferred tick reconciles and
        // reports a refusal exactly as the synchronous one did.
        #expect(manager.contains("CadenceTaskStatusEditing.setStatus(transition.status, for: task, in: context)"))
    }

    /// [[T-8352]]: the iOS Calendar timed block's circle is a tap target on the shared deferred
    /// completion, draws whatever fill the manager is running, and a hold that ends on the circle
    /// moves the block without completing the task.
    @Test func theIOSTimelineBlockCircleIsWiredToTheSharedDeferredCompletion() throws {
        let file = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift"))
        let start = try #require(file.range(of: "struct iOSTimelineTaskBlock: View"), "non-vacuity: the block moved")
        let end = try #require(file.range(of: "struct iOSTimelineBlockEditing", range: start.upperBound..<file.endIndex))
        let block = String(file[start.lowerBound..<end.lowerBound])

        let tap = try #require(CadenceSourceScan.functionBody(named: "handleCompletionTap", in: block), "the block's circle is not a tap target")
        #expect(tap.contains("TaskCompletionAnimationManager.shared.advanceCompletionControl(for: task)"), "the block's circle does not start the shared fill")
        #expect(tap.contains("if isTapTheEndOfAHold { return }"), "a hold lifted on the circle would complete the task")
        let blockTap = try #require(CadenceSourceScan.functionBody(named: "handleTap", in: block))
        #expect(blockTap.contains("if isTapTheEndOfAHold { return }"), "the block's own tap stopped asking the shared hold test")

        #expect(block.contains("iOSTaskCompletionFill("), "the block draws a still circle")
        #expect(block.contains("TaskCompletionAnimationManager.shared.glyph(for: task)"), "the block's glyph cannot see the pending states")
        #expect(!block.contains("CadenceTaskCompletionCircle(glyph: .resolve(task: task)"), "the block still draws the circle from the stored status alone")
        #expect(!block.contains("CadenceTaskStatusEditing.toggleCompletion("), "the block writes completion synchronously")
        #expect(block.contains(".accessibilityAction(named: Text(completionGlyph.state.accessibilityActionLabel))"), "VoiceOver cannot reach the block's circle")
    }

    // MARK: - T-8354: the row-wide pending sweep, one drawing on both platforms

    /// The sweep names the deferral the ring names: green while a completion runs, grey once the
    /// second tap turns it into a cancellation, and nothing at all on an idle task.
    @Test func thePendingSweepFollowsTheDeferralTheRingIsDrawing() {
        let manager = TaskCompletionAnimationManager.shared
        let task = AppTask(title: "sweep")
        #expect(CadenceTaskCompletionSweepFrame.resolve(for: task, in: manager) == nil, "an idle task swept")

        manager.advanceCompletionControl(for: task)
        let completing = CadenceTaskCompletionSweepFrame.resolve(for: task, in: manager, now: Date().addingTimeInterval(0.3))
        #expect(completing?.isCancellation == false, "a running completion did not sweep green")
        #expect((completing?.progress ?? 0) > 0, "the sweep did not read the running fill's clock")
        #expect((completing?.progress ?? 1) < 1)

        manager.advanceCompletionControl(for: task)
        #expect(manager.isPendingCancel(task), "non-vacuity: the second tap did not start a cancellation")
        #expect(CadenceTaskCompletionSweepFrame.resolve(for: task, in: manager)?.isCancellation == true, "a running cancellation did not sweep grey")

        manager.advanceCompletionControl(for: task)
        #expect(CadenceTaskCompletionSweepFrame.resolve(for: task, in: manager) == nil, "the take-back left the row sweeping")
        #expect(task.status == .todo)
    }

    /// The iOS row, board card and Calendar timed block lay the shared sweep over themselves, the
    /// drawing lives once in `Shared/`, and the host gates its display-link redraw on a pending
    /// task and on Reduce Motion — none of which a macOS test host can render.
    @Test func theIOSRowCardAndBlockLayTheSharedPendingSweep() throws {
        let row = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        let card = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSBoardCards.swift"))
        let timeline = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift"))
        let shared = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/Shared/Components/TaskCompletionPendingOverlay.swift"))
        // [[T-8411]] deleted the macOS glyph file the sweep once lived in; the macOS views as a
        // whole must still declare no sweep of their own.
        let macPaths = try CadenceSourceScan.swiftFiles(under: "Cadence/macOS")
        #expect(macPaths.count > 10, "non-vacuity: the macOS sources were not listed")
        let mac = try macPaths.map { CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0)) }.joined(separator: "\n")
        #expect(row.contains("struct iOSTaskRow"), "non-vacuity: wrong row file read")
        #expect(mac.contains("struct TaskCompletionButton"), "non-vacuity: wrong macOS files read")

        let rowStart = try #require(row.range(of: "struct iOSTaskRow: View"))
        let rowEnd = try #require(row.range(of: "struct iOSTaskMetaLabel", range: rowStart.upperBound..<row.endIndex))
        #expect(
            row[rowStart.lowerBound..<rowEnd.lowerBound].contains("TaskCompletionPendingSweep(task: task, cornerRadius: Theme.radiusCard)"),
            "the iOS task row shows only the ring while its fill runs"
        )

        let cardStart = try #require(card.range(of: "struct iOSBoardTaskCard: View"))
        let cardBody = String(card[cardStart.lowerBound...])
        #expect(!cardBody.contains("settlingOverlay: { EmptyView() }"), "the iOS board card's settle slot is empty again")
        #expect(cardBody.contains("TaskCompletionPendingSweep(task: task, cornerRadius: CadenceLedgerCardMetrics.cornerRadius)"), "the iOS board card does not sweep")

        let blockStart = try #require(timeline.range(of: "struct iOSTimelineTaskBlock: View"))
        let blockEnd = try #require(timeline.range(of: "struct iOSTimelineBlockEditing", range: blockStart.upperBound..<timeline.endIndex))
        #expect(
            timeline[blockStart.lowerBound..<blockEnd.lowerBound].contains("TaskCompletionPendingSweep(task: task, cornerRadius: Theme.radiusControl)"),
            "the iOS Calendar timed block does not sweep"
        )

        // One drawing: declared in Shared, not in the macOS views any more.
        #expect(CadenceSourceScan.matchCount(#"struct TaskCompletionPendingOverlay\b"#, in: shared) == 1)
        #expect(CadenceSourceScan.matchCount(#"struct TaskCompletionPendingOverlay\b"#, in: mac) == 0, "the macOS file draws its own sweep again")

        // The host: no display link unless pending, none under Reduce Motion, and the overlay is fed
        // from the shared decision rather than a second reading of the manager.
        let host = try #require(CadenceSourceScan.declarationBody("struct TaskCompletionPendingSweep", in: shared), "the sweep host moved")
        #expect(host.contains("if !reduceMotion, CadenceTaskCompletionSweepFrame.resolve(for: task) != nil {"), "the sweep redraws at screen rate when nothing is pending, or under Reduce Motion")
        #expect(host.contains("TimelineView(.animation)"), "non-vacuity: the host no longer animates at all")
        #expect(host.contains("tint: frame.tint"), "the host picks its own tint")
    }

    // MARK: - T-8412: macOS draws the pending state still under Reduce Motion

    /// macOS's task row, Kanban card and Kanban column read `accessibilityReduceMotion` the way iOS
    /// does: the ring's display-link redraw is gated on it, and the row-wide sweep is the shared
    /// host (which draws nothing under it) rather than a second ungated copy. A macOS test host
    /// cannot toggle the setting and render, so the pin reads the source, scoped per declaration.
    @Test func theMacOSRingAndSweepDrawThePendingStateStillUnderReduceMotion() throws {
        let tasks = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        let card = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanCardView.swift"))
        let column = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        // Comment-stripped, not `codeOnly`: the header pin reads a symbol name, which is a literal.
        let header = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift")

        // The list row's ring and sweep.
        let button = try #require(CadenceSourceScan.declarationBody("private struct TaskCompletionButton", in: tasks), "non-vacuity: the row's ring moved")
        #expect(button.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"), "the row's ring does not read Reduce Motion")
        #expect(button.contains("if !reduceMotion && (isPendingCompletion || isPendingCancel) {"), "the row's ring animates under Reduce Motion")
        #expect(button.contains("TimelineView(.animation)"), "non-vacuity: the row's ring no longer animates at all")
        let background = try #require(CadenceSourceScan.declarationBody("private struct TaskRowBackground", in: tasks), "non-vacuity: the row background moved")
        #expect(background.contains("TaskCompletionPendingSweep(task: task, cornerRadius: Theme.radiusCard)"), "the row does not lay the shared sweep")
        #expect(!background.contains("TimelineView("), "the row runs its own ungated sweep again")

        // The Kanban card's ring and settle wash.
        let ring = try #require(CadenceSourceScan.declarationBody("private var completionRing: some View", in: card), "non-vacuity: the card's ring moved")
        #expect(card.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"), "the card does not read Reduce Motion")
        #expect(ring.contains("if !reduceMotion && (isPendingCompletion || isPendingCancel) {"), "the card's ring animates under Reduce Motion")
        let wash = try #require(CadenceSourceScan.declarationBody("private var settlingOverlay: some View", in: card), "non-vacuity: the card's wash moved")
        #expect(wash.contains("TaskCompletionPendingSweep(task: task, cornerRadius: CadenceLedgerCardMetrics.cornerRadius)"), "the card does not lay the shared sweep")
        #expect(!wash.contains("TimelineView("), "the card runs its own ungated sweep again")

        // The Kanban column: one gate for its sweep and its header ring, and no other display link.
        let gate = try #require(CadenceSourceScan.declarationBody("private var animatesPendingCompletion: Bool", in: column), "the column lost its motion gate")
        #expect(gate.contains("!reduceMotion && isPendingCompletion"), "the column animates under Reduce Motion")
        #expect(column.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        let displayLinks = CadenceSourceScan.matchCount(#"TimelineView\(\.animation\)"#, in: column)
        let gatedLinks = CadenceSourceScan.matchCount(#"if animatesPendingCompletion \{\s*TimelineView\(\.animation\)"#, in: column)
        #expect(displayLinks == 2, "non-vacuity: the column's sweep and header ring")
        #expect(gatedLinks == displayLinks, "a column display link is not behind the Reduce Motion gate")
        // Still, the header ring stamps a pending glyph rather than an empty track.
        #expect(column.contains("header(activeCount: activeCount, completionProgress: nil)"), "the still header draws a zero-length fill")
        let controls = try #require(CadenceSourceScan.declarationBody("private var headerControls: some View", in: header), "non-vacuity: the header ring moved")
        // [[T-8411]]: the ring is the shared circle fed the column glyph, whose still pending face
        // is the green ring and dot (pinned on `CadenceTaskCompletionCircleFace` itself).
        #expect(controls.contains("glyph: .column("), "the column header picks its own glyph again")
        #expect(controls.contains("isPendingCompletion: isPendingCompletion"), "a still completing column's ring looks idle")
    }
}
#endif
