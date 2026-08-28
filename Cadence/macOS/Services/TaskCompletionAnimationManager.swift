#if os(macOS)
import SwiftUI
import Observation
import SwiftData

@MainActor
@Observable
final class TaskCompletionAnimationManager {
    static let shared = TaskCompletionAnimationManager()
    static let animationDuration: TimeInterval = 2.5
    var modelContext: ModelContext?

    // Completion (green)
    private(set) var pendingStartTimes: [UUID: Date] = [:]
    @ObservationIgnored private var pendingTasks: [UUID: Task<Void, Never>] = [:]

    // Cancellation (gray)
    private(set) var pendingCancelStartTimes: [UUID: Date] = [:]
    @ObservationIgnored private var pendingCancelTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - Completion

    func isPending(_ task: AppTask) -> Bool {
        pendingStartTimes[task.id] != nil
    }

    func progress(for task: AppTask, now: Date = Date()) -> Double {
        guard let start = pendingStartTimes[task.id] else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / Self.animationDuration, 0), 1)
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

    func cancelPending(for taskID: UUID) {
        pendingTasks[taskID]?.cancel()
        pendingTasks[taskID] = nil
        pendingStartTimes[taskID] = nil
    }

    private func beginCompletion(for task: AppTask) {
        let id = task.id
        cancelPending(for: id)
        pendingStartTimes[id] = Date()
        pendingTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.animationDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.pendingStartTimes[id] != nil else { return }
                self.pendingTasks[id] = nil
                self.pendingStartTimes[id] = nil
                self.write(.done, to: task)
            }
        }
    }

    // MARK: - Cancellation

    func isPendingCancel(_ task: AppTask) -> Bool {
        pendingCancelStartTimes[task.id] != nil
    }

    func cancelProgress(for task: AppTask, now: Date = Date()) -> Double {
        guard let start = pendingCancelStartTimes[task.id] else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / Self.animationDuration, 0), 1)
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
    }

    private func beginCancellation(for task: AppTask) {
        let id = task.id
        // Cancel any in-progress completion first
        cancelPending(for: id)
        cancelCancelPending(for: id)
        pendingCancelStartTimes[id] = Date()
        pendingCancelTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.animationDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.pendingCancelStartTimes[id] != nil else { return }
                self.pendingCancelTasks[id] = nil
                self.pendingCancelStartTimes[id] = nil
                self.write(.cancelled, to: task)
            }
        }
    }

    // MARK: - Status writes

    /// The three transitions this manager performs. A closed set on purpose, so the funnel below
    /// has no impossible case to answer for: the manager never writes `.inProgress`.
    private enum StatusWrite {
        case done
        case cancelled
        case restored
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
    private func write(_ transition: StatusWrite, to task: AppTask) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch transition {
            case .restored:
                TaskWorkflowService.markTodo(task)
            case .done:
                if let context = modelContext ?? task.modelContext {
                    TaskWorkflowService.markDone(task, in: context)
                } else {
                    CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries(task, as: .done)
                }
            case .cancelled:
                if let context = modelContext ?? task.modelContext {
                    TaskWorkflowService.markCancelled(task, in: context)
                } else {
                    CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries(task, as: .cancelled)
                }
            }
        }
    }
}
#endif
