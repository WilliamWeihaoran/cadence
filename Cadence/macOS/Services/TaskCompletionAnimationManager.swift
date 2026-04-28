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

    func toggleCompletion(for task: AppTask) {
        if task.isDone {
            cancelPending(for: task.id)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                TaskWorkflowService.markTodo(task)
            }
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
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if let context = self.modelContext {
                        TaskWorkflowService.markDone(task, in: context)
                    } else {
                        task.completedAt = Date()
                        task.status = .done
                    }
                }
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
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                task.status = .todo
            }
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
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    task.status = .cancelled
                }
            }
        }
    }
}
#endif
