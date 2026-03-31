#if os(macOS)
import SwiftUI
import Observation

@MainActor
@Observable
final class SectionCompletionAnimationManager {
    static let shared = SectionCompletionAnimationManager()
    static let animationDuration: TimeInterval = 2.5

    private(set) var pendingStartTimes: [UUID: Date] = [:]
    @ObservationIgnored private var pendingTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func isPending(_ section: TaskSectionConfig) -> Bool {
        pendingStartTimes[section.id] != nil
    }

    func progress(for section: TaskSectionConfig, now: Date = Date()) -> Double {
        guard let start = pendingStartTimes[section.id] else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / Self.animationDuration, 0), 1)
    }

    func toggleCompletion(
        for section: TaskSectionConfig,
        getCurrent: @escaping () -> TaskSectionConfig?,
        save: @escaping (TaskSectionConfig) -> Void
    ) {
        if section.isCompleted {
            cancelPending(for: section.id)
            guard var current = getCurrent() else { return }
            current.isCompleted = false
            current.isArchived = false
            save(current)
            return
        }

        if isPending(section) {
            cancelPending(for: section.id)
        } else {
            beginCompletion(for: section.id, getCurrent: getCurrent, save: save)
        }
    }

    func cancelPending(for sectionID: UUID) {
        pendingTasks[sectionID]?.cancel()
        pendingTasks[sectionID] = nil
        pendingStartTimes[sectionID] = nil
    }

    private func beginCompletion(
        for sectionID: UUID,
        getCurrent: @escaping () -> TaskSectionConfig?,
        save: @escaping (TaskSectionConfig) -> Void
    ) {
        cancelPending(for: sectionID)
        pendingStartTimes[sectionID] = Date()
        pendingTasks[sectionID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.animationDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.pendingStartTimes[sectionID] != nil, var current = getCurrent() else { return }
                self.pendingTasks[sectionID] = nil
                self.pendingStartTimes[sectionID] = nil
                current.isCompleted = true
                current.isArchived = true
                save(current)
            }
        }
    }
}
#endif
