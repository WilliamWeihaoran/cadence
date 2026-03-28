import SwiftData
import Foundation

/// A concrete action item. Lives inside an Area, Project, Goal, or as an inbox item.
@Model final class AppTask {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var priorityRaw: String = "none"
    var statusRaw: String = "todo"

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }
    var dueDate: String = ""            // YYYY-MM-DD or ""
    var scheduledDate: String = ""      // YYYY-MM-DD — the day this is time-blocked
    var scheduledStartMin: Int = -1     // minutes from midnight (-1 = not scheduled)
    var estimatedMinutes: Int = 0       // 0 = no estimate
    var calendarEventID: String = ""    // EKEvent identifier
    var order: Int = 0
    var createdAt: Date = Date()

    var area: Area? = nil
    var project: Project? = nil
    var goal: Goal? = nil
    var context: Context? = nil         // denormalized for efficient queries

    // MARK: - Computed

    var isDone: Bool { status == .done }
    var isCancelled: Bool { status == .cancelled }

    /// End time in minutes from midnight (start + duration, default 60min if no estimate)
    var scheduledEndMin: Int {
        guard scheduledStartMin >= 0 else { return -1 }
        return scheduledStartMin + max(estimatedMinutes, 60)
    }

    var containerName: String {
        goal?.title ?? area?.name ?? project?.name ?? ""
    }

    var containerColor: String {
        goal?.colorHex ?? area?.colorHex ?? project?.colorHex ?? "#6b7a99"
    }

    init(title: String) {
        self.title = title
    }
}
