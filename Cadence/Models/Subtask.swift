import SwiftData
import Foundation

/// A sub-item belonging to exactly one AppTask.
/// Cannot be time-blocked, independently focused, or have its own subtasks.
@Model final class Subtask {
    var id: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var order: Int = 0
    var createdAt: Date = Date()

    var parentTask: AppTask? = nil

    init(title: String) {
        self.title = title
    }
}
