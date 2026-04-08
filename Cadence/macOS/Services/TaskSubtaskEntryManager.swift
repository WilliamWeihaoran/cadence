#if os(macOS)
import SwiftUI

@Observable
final class TaskSubtaskEntryManager {
    static let shared = TaskSubtaskEntryManager()

    var requestedTaskID: UUID? = nil

    private init() {}

    func requestFocus(for taskID: UUID) {
        requestedTaskID = taskID
    }

    func consumeIfMatches(taskID: UUID) -> Bool {
        guard requestedTaskID == taskID else { return false }
        requestedTaskID = nil
        return true
    }
}
#endif
