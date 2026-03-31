#if os(macOS)
import SwiftUI
import Observation

@MainActor
@Observable
final class TaskCompletionAnimationManager {
    static let shared = TaskCompletionAnimationManager()
    static let animationDuration: TimeInterval = 2.5

    private(set) var pendingStartTimes: [UUID: Date] = [:]
    @ObservationIgnored private var pendingTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

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
                task.status = .todo
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
                    task.status = .done
                }
            }
        }
    }
}
#endif
