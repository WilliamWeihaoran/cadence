import SwiftUI
import Observation
import SwiftData

/// The deferred completion: the tap starts a fill, the `.done` write waits it out, and a tap
/// inside it takes the completion back.
///
/// **One manager for both platforms ([[T-8203]]).** It lived in `macOS/Services/` while iOS wrote
/// completion synchronously, so the two platforms disagreed about whether an animation plays and
/// whether a mis-tap can be withdrawn — a UI difference no hardware constraint answers, which is
/// drift under [[T-8201]]. Nothing in it was AppKit; it moved here whole rather than being copied,
/// so the clock, the undo rule and the termination settle are the same object on both. The only
/// platform split is the last hop of `write`, and it is plumbing rather than UI: macOS reconciles
/// through `TaskWorkflowService` and names a refusal on `settleFailed`, iOS through
/// `CadenceTaskStatusEditing`, which names it on `CadenceTaskSettleFailureCenter` — each
/// platform's existing one place, so a refused tick is said where that shell already says it.
@MainActor
@Observable
final class TaskCompletionAnimationManager {
    static let shared = TaskCompletionAnimationManager()

    // The deferral, and therefore the undo window, is `CadenceTaskCompletionTiming`'s and is read
    // from there at each use ([[T-8202]]). This manager deliberately keeps no constant of its own:
    // the section manager and the drawing read the same number on both platforms.

    /// The **last-resort** context for a settle, and nothing more (T-3098).
    ///
    /// `macOSRootLifecycleSupport.handleAppear` injects this once, at launch, from the root's
    /// `currentModelContext`. `macOSRootView.refreshAppData()` then *replaces* that context
    /// wholesale when another process writes the store, and the `.onAppear` that seeded this
    /// never re-runs — it sits outside both `.id(dataRefreshID)` subtrees — so after the first
    /// refresh this property names a context the UI has stopped using. See `settleContext(for:)`
    /// for why that is now harmless.
    var modelContext: ModelContext?

    // Completion (green)
    private(set) var pendingStartTimes: [UUID: Date] = [:]
    @ObservationIgnored private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    /// The task each pending fill will settle (T-5360). The sleep's closure captured it already;
    /// holding it here too is what lets `settleAllPendingBeforeTermination` write it without
    /// waiting for a sleep that a quit will never let finish.
    @ObservationIgnored private var pendingTargets: [UUID: AppTask] = [:]

    // Cancellation (gray)
    private(set) var pendingCancelStartTimes: [UUID: Date] = [:]
    @ObservationIgnored private var pendingCancelTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingCancelTargets: [UUID: AppTask] = [:]

    /// Set when a settle was refused and put back (T-628), and read by `macOSRootView`'s alert.
    ///
    /// It lives on the manager rather than on a view because the manager is where the write is:
    /// four surfaces reach `toggleCompletion` — the timeline block, the task row, the ⌘-key
    /// command and the inspector — and a notice owned by any one of them would be missing from the
    /// other three.
    private(set) var settleFailed = false

    private init() {}

    // MARK: - Completion

    func isPending(_ task: AppTask) -> Bool {
        pendingStartTimes[task.id] != nil
    }

    func progress(for task: AppTask, now: Date = Date()) -> Double {
        guard let start = pendingStartTimes[task.id] else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / CadenceTaskCompletionTiming.animationDuration, 0), 1)
    }

    /// **T-344, decided: the completion control toggles *settled*, not *done*.** A cancelled task is
    /// settled, so tapping its circle restores it to todo — the same thing tapping a done task's
    /// circle does — rather than converting an abandoned task into an accomplished one.
    ///
    /// The circle is already *drawn* by a settled/open decision: `CadenceTaskCompletionGlyph`
    /// returns a filled glyph for `.cancelled` and `.done` alike, and `isSettled` covers both. A
    /// control that looks up "settled" to paint itself and "isDone" to decide what a tap means is
    /// the same rule spelled two ways, which is the defect T-147 and T-342 are both instances of.
    /// Reading `isFinishedTask` here makes the appearance and the action one rule: a filled circle
    /// un-settles, an empty circle settles as done.
    ///
    /// The cancelled → done transition survives as two taps (restore, then complete), which is also
    /// how you would say it out loud. That is the right way round: `markDone` stamps `completedAt`
    /// and spawns the next occurrence of a recurring series, so a mis-tap under the old rule minted
    /// live work, and a mis-tap under this one costs a tap.
    func toggleCompletion(for task: AppTask) {
        if CadenceTaskQuerySupport.isFinishedTask(task) {
            cancelPending(for: task.id)
            write(.restored, to: task)
            return
        }

        if isPending(task) {
            cancelPending(for: task.id)
        } else {
            beginCompletion(for: task)
        }
    }

    /// **What a tap on a task's completion circle does, as one decision ([[T-8203]]).**
    ///
    /// Three taps walk the control: open → completing; completing → cancelling (the fill turns
    /// grey and a cross replaces the dot); cancelling → open again. A settled task reopens. These
    /// are exactly the five names `CadenceTaskCompletionState.accessibilityActionLabel` already
    /// announces — "Cancel task" mid-fill, "Stop canceling task" mid-cancel — so the label and the
    /// gesture are one rule. macOS spelled this as a three-branch `handleTap()` in the task row and
    /// again in the Kanban card; iOS, which had no pending state at all, called the synchronous
    /// toggle. Every circle on both platforms now asks this.
    func advanceCompletionControl(for task: AppTask) {
        if isPending(task) {
            cancelPending(for: task.id)
            toggleCancellation(for: task)
        } else if isPendingCancel(task) {
            cancelCancelPending(for: task.id)
        } else {
            toggleCompletion(for: task)
        }
    }

    /// The glyph a completion circle should draw for `task` right now, pending states included.
    func glyph(for task: AppTask) -> CadenceTaskCompletionGlyph {
        .resolve(task: task, isPendingCompletion: isPending(task), isPendingCancellation: isPendingCancel(task))
    }

    /// The running fill for whichever deferral `task` is in — completion first, as the glyph's
    /// own order has it — or `nil` when there is none to draw.
    func pendingProgress(for task: AppTask, now: Date = Date()) -> Double? {
        if isPending(task) { return progress(for: task, now: now) }
        if isPendingCancel(task) { return cancelProgress(for: task, now: now) }
        return nil
    }

    func cancelPending(for taskID: UUID) {
        pendingTasks[taskID]?.cancel()
        pendingTasks[taskID] = nil
        pendingStartTimes[taskID] = nil
        pendingTargets[taskID] = nil
    }

    private func beginCompletion(for task: AppTask) {
        let id = task.id
        // The twin of `beginCancellation`'s first line ([[T-8392]]). Without it a completion started
        // over a running cancellation — the swipe's Done, macOS's timeline block, the Cmd key —
        // left both fills pending, and the cancellation, having started first, closed first and
        // settled the task as cancelled after the user had asked for done.
        cancelCancelPending(for: id)
        cancelPending(for: id)
        pendingStartTimes[id] = Date()
        pendingTargets[id] = task
        pendingTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(CadenceTaskCompletionTiming.animationDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.windowClosed(onCompletionOf: id) }
        }
    }

    /// What the completion timer does when the window closes, as a method of its own so a test
    /// can close the window without sleeping through it ([[T-268]] forbids sleep-and-assert).
    /// A no-op unless a fill is still recorded for `id` — a take-back inside the window cleared it.
    func windowClosed(onCompletionOf id: UUID) {
        guard pendingStartTimes[id] != nil, let task = pendingTargets[id] else { return }
        pendingTasks[id] = nil
        pendingStartTimes[id] = nil
        pendingTargets[id] = nil
        guard !wasSettledElsewhere(task) else { return }
        self.write(.done, to: task)
    }

    // MARK: - Cancellation

    func isPendingCancel(_ task: AppTask) -> Bool {
        pendingCancelStartTimes[task.id] != nil
    }

    func cancelProgress(for task: AppTask, now: Date = Date()) -> Double {
        guard let start = pendingCancelStartTimes[task.id] else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / CadenceTaskCompletionTiming.animationDuration, 0), 1)
    }

    func toggleCancellation(for task: AppTask) {
        if task.isCancelled {
            cancelCancelPending(for: task.id)
            write(.restored, to: task)
            return
        }

        if isPendingCancel(task) {
            cancelCancelPending(for: task.id)
        } else {
            beginCancellation(for: task)
        }
    }

    func cancelCancelPending(for taskID: UUID) {
        pendingCancelTasks[taskID]?.cancel()
        pendingCancelTasks[taskID] = nil
        pendingCancelStartTimes[taskID] = nil
        pendingCancelTargets[taskID] = nil
    }

    private func beginCancellation(for task: AppTask) {
        let id = task.id
        // Cancel any in-progress completion first
        cancelPending(for: id)
        cancelCancelPending(for: id)
        pendingCancelStartTimes[id] = Date()
        pendingCancelTargets[id] = task
        pendingCancelTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(CadenceTaskCompletionTiming.animationDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.windowClosed(onCancellationOf: id) }
        }
    }

    /// The cancellation twin of `windowClosed(onCompletionOf:)`.
    func windowClosed(onCancellationOf id: UUID) {
        guard pendingCancelStartTimes[id] != nil, let task = pendingCancelTargets[id] else { return }
        pendingCancelTasks[id] = nil
        pendingCancelStartTimes[id] = nil
        pendingCancelTargets[id] = nil
        guard !wasSettledElsewhere(task) else { return }
        self.write(.cancelled, to: task)
    }

    // MARK: - Termination

    /// **T-5360.** Settle every fill still running, now, before the app quits.
    ///
    /// The fill holds the `.done` (or `.cancelled`) write behind an in-memory sleep, so a
    /// Cmd+Q inside that window used to drop the tick: the task came back open on next launch.
    /// The user's intent was already expressed — the fill is a grace period for an undo, not a
    /// confirmation step — so quitting finishes it exactly as the timer would have, through the
    /// same committing `write`. Writing immediately and animating separately was the alternative,
    /// and was rejected: the deferral is what keeps a hovered row in its group until the fill ends
    /// and what makes a second tap a free undo, and both are pinned by this manager's tests.
    /// `CadenceAppDelegate.applicationWillTerminate` calls this beside the focus bank.
    func settleAllPendingBeforeTermination() {
        let completions = pendingTargets
        let cancellations = pendingCancelTargets
        for id in completions.keys { cancelPending(for: id) }
        for id in cancellations.keys { cancelCancelPending(for: id) }
        for task in completions.values where !wasSettledElsewhere(task) { write(.done, to: task) }
        for task in cancellations.values where !wasSettledElsewhere(task) { write(.cancelled, to: task) }
    }

    /// **The iOS spelling of termination ([[T-8203]], hazard 1).** iOS has no Cmd-Q to hear: it
    /// suspends a backgrounded app and kills it later without notice, so a fill still running when
    /// the user swipes home is the same dropped tick [[T-5360]] fixed on macOS, re-introduced. The
    /// root's `scenePhase` observer calls this on every phase change; it settles on leaving
    /// `.active` — the same edge `MarkdownEditorTerminationFlush` uses for held editor text — and
    /// does nothing on returning, so coming back to the app cannot complete a task nobody tapped.
    /// Settling on `.inactive` too (Control Centre, the app switcher) shortens an undo window the
    /// user has already walked away from; waiting for `.background` would bet the write on a
    /// suspension that may never deliver it.
    func settleAllPending(onLeaving phase: ScenePhase) {
        guard phase != .active else { return }
        settleAllPendingBeforeTermination()
    }

    /// **A task settled by someone else mid-fill is left as they settled it ([[T-8203]], hazard 4).**
    ///
    /// `CompleteTaskIntent` completes a task from a widget out of process, and MCP and a second
    /// device can do the same; any of them can land inside the 1.2s window. Writing `.done` over a
    /// task that is already done re-stamps `completedAt` with a later time, and writing
    /// `.cancelled` over a completed one turns finished work into abandoned work — in both cases
    /// overwriting a decision with an older one. The user's intent ("this is over") has already
    /// been met, so the fill just ends.
    private func wasSettledElsewhere(_ task: AppTask) -> Bool {
        CadenceTaskQuerySupport.isFinishedTask(task)
    }

    // MARK: - Status writes

    /// The three transitions this manager performs. A closed set on purpose, so the funnel below
    /// has no impossible case to answer for: the manager never writes `.inProgress`.
    private enum StatusWrite {
        case done
        case cancelled
        case restored

        var status: TaskStatus {
            switch self {
            case .done: .done
            case .cancelled: .cancelled
            case .restored: .todo
            }
        }
    }

    /// **Every** status write in this manager goes through here, and none of them spell
    /// `task.status =`. Two independent audits found two different direct assignments in this one
    /// file, sixty lines apart: T-341's restore branch wrote `task.status = .todo` and left behind
    /// the `completedAt` the task was cancelled with, so an open task carried a completion
    /// timestamp; T-357's contextless branches settled a task without asking the recurrence
    /// workflow anything, so a recurring task finished through them never spawned its successor.
    /// Fixing the two known ones invites a third. One funnel, plus
    /// `CadenceTaskStatusLifecycleSurfaceTests.noStatusIsAssignedDirectlyInTheAnimationManager`, is what
    /// stops it: a new call site cannot bypass the shared path without failing that scan.
    ///
    /// The context is `modelContext ?? task.modelContext`. The injected one is set on root appear
    /// and the manager is injected app-wide, so the fallback is the branch that used to be
    /// open-coded — and a task this manager can see was inserted by *some* context, so it is
    /// almost never nil. When it genuinely is (an unpersisted task, which is what the unit tests
    /// hold), `settleWithoutAdvancingSeries` still keeps the invariant T-341 is about: a settled
    /// status carries a timestamp, an open one carries none. There is no store to spawn a successor
    /// into in that case, and inventing one would be worse than not advancing the series.
    func clearSettleFailure() { settleFailed = false }

    /// Names a refusal this manager did not cause itself but that shares its one alert (T-654).
    ///
    /// `FocusView`'s timer controls bank a focus session's minutes through the same committing
    /// shape a settle uses — a snapshot restored on refusal, nothing left pending — and macOS has
    /// exactly one place that names a refused task mutation to the user. A second alert owned by
    /// the focus screen would be a second answer to "did that write land"; this reuses the first.
    func recordSettleFailure() { settleFailed = true }

    /// Runs a committing settle and records a refusal instead of dropping it.
    ///
    /// `commitSettle` has already put the task and its successor back by the time this catches, so
    /// the circle the user is looking at re-draws open — the alert is what says why rather than
    /// leaving that reversal unexplained.
    private func settle(in context: ModelContext, _ commit: (ModelContext) throws -> Void) {
        do {
            try commit(context)
        } catch {
            settleFailed = true
        }
    }

    /// The context a settle must be committed through: **the one the task itself lives in.**
    ///
    /// This used to read `modelContext ?? task.modelContext`, preferring the injected context, and
    /// that precedence was the whole of T-3098. A settle is not a free-floating write — it edits
    /// `task`, and `spawnNextOccurrenceIfNeeded` builds a successor that inherits `task`'s `area`,
    /// `project`, `context`, `goal` and `tags` before `context.insert(nextTask)` runs. Those are
    /// objects registered in whatever context owns `task`. Handing a *different* context to the
    /// insert is the documented Core Data cross-context relationship fault, and when it does not
    /// fault it commits through a context that is no longer the one the UI reads, so the edit the
    /// user just made is left pending on a context nothing will ever save.
    ///
    /// Asking the task where it lives makes the rule "write the object in the context that owns
    /// it", which holds whatever `refreshAppData()` did and *whenever* it did it — including a
    /// swap that lands midway through the fill, where re-seeding this property would instead
    /// pair a freshly-swapped context with a task from the outgoing one. The injected context
    /// stays as the fallback for the only case it can still answer: a task registered nowhere, so
    /// `modelContext` is nil (T-357's branch keeps its own `else` below for when both are nil).
    private func settleContext(for task: AppTask) -> ModelContext? {
        task.modelContext ?? modelContext
    }

    private func write(_ transition: StatusWrite, to task: AppTask) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            guard let context = settleContext(for: task) else {
                CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries(task, as: transition.status)
                return
            }
            commit(transition, to: task, in: context)
        }
    }

    /// The one platform split in this manager, and it is plumbing, not UI ([[T-8203]]).
    ///
    /// Both spellings reach the same committing shared transition (`CadenceTaskMutationSupport`'s
    /// `commitSettle` / `setStatus`); they differ in the app-side hop around it. macOS's
    /// `TaskWorkflowService` reconciles through `HabitNotificationReconcileSupport` and reports a
    /// refusal to this manager's `settleFailed`, which `macOSRootView` reads. iOS has no
    /// `TaskWorkflowService`: its status wrapper is `CadenceTaskStatusEditing`, which reconciles
    /// through `CadenceWindDownReconciler` and records a refusal on
    /// `CadenceTaskSettleFailureCenter`, the iOS shell's one place for that sentence (T-636/T-642).
    /// Routing iOS through it is what keeps a deferred tick reconciling and reporting exactly as
    /// the synchronous one it replaced did.
    private func commit(_ transition: StatusWrite, to task: AppTask, in context: ModelContext) {
#if os(macOS)
        switch transition {
        case .restored:
            settle(in: context) { try TaskWorkflowService.commitMarkTodo(task, in: $0) }
        case .done:
            settle(in: context) { try TaskWorkflowService.commitMarkDone(task, in: $0) }
        case .cancelled:
            settle(in: context) { try TaskWorkflowService.commitMarkCancelled(task, in: $0) }
        }
#else
        CadenceTaskStatusEditing.setStatus(transition.status, for: task, in: context)
#endif
    }
}
