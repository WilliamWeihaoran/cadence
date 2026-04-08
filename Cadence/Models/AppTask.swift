import SwiftData
import Foundation

enum TaskSectionDefaults {
    static let defaultName = "Default"
    static let defaultColorHex = "#6b7a99"
}

struct TaskSectionConfig: Codable, Hashable, Identifiable {
    var uuid: UUID = UUID()
    var name: String
    var colorHex: String = TaskSectionDefaults.defaultColorHex
    var dueDate: String = ""
    var isCompleted: Bool = false
    var isArchived: Bool = false

    var id: UUID { uuid }

    var isDefault: Bool {
        name.caseInsensitiveCompare(TaskSectionDefaults.defaultName) == .orderedSame
    }

    private enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case colorHex
        case dueDate
        case isCompleted
        case isArchived
    }

    init(
        uuid: UUID = UUID(),
        name: String,
        colorHex: String = TaskSectionDefaults.defaultColorHex,
        dueDate: String = "",
        isCompleted: Bool = false,
        isArchived: Bool = false
    ) {
        self.uuid = uuid
        self.name = name
        self.colorHex = colorHex
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decodeIfPresent(UUID.self, forKey: .uuid) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? TaskSectionDefaults.defaultColorHex
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

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
    var estimatedMinutes: Int = 30
    var actualMinutes: Int = 0          // cumulative actual time logged
    var calendarEventID: String = ""    // EKEvent identifier
    var sectionName: String = TaskSectionDefaults.defaultName
    var order: Int = 0
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    var area: Area? = nil
    var project: Project? = nil
    var goal: Goal? = nil
    var context: Context? = nil         // denormalized for efficient queries
    var subtasks: [Subtask]? = nil

    // MARK: - Computed

    var isDone: Bool { status == .done }
    var isCancelled: Bool { status == .cancelled }

    /// End time in minutes from midnight (start + duration, default 30min if no estimate)
    var scheduledEndMin: Int {
        guard scheduledStartMin >= 0 else { return -1 }
        return scheduledStartMin + max(estimatedMinutes, 30)
    }

    var containerName: String {
        goal?.title ?? area?.name ?? project?.name ?? ""
    }

    var containerColor: String {
        goal?.colorHex ?? area?.colorHex ?? project?.colorHex ?? "#6b7a99"
    }

    var resolvedSectionName: String {
        let trimmed = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TaskSectionDefaults.defaultName : trimmed
    }

    var hidesEmptyDueDateInList: Bool {
        if let project {
            return project.hideDueDateIfEmpty
        }
        if let area {
            return area.hideDueDateIfEmpty
        }
        return false
    }

    var shouldShowDueDateField: Bool {
        !dueDate.isEmpty || !hidesEmptyDueDateInList
    }

    init(title: String) {
        self.title = title
    }
}
