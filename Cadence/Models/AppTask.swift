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

/// A concrete action item. Lives inside an Area, Project, Milestone, or as an inbox item.
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
    var recurrenceRule: TaskRecurrenceRule {
        get { TaskRecurrenceRule(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
    var recurrenceEndMode: TaskRecurrenceEndMode {
        get { TaskRecurrenceEndMode(rawValue: recurrenceEndModeRaw) ?? .never }
        set { recurrenceEndModeRaw = newValue.rawValue }
    }
    var dueDate: String = ""            // YYYY-MM-DD or ""
    var scheduledDate: String = ""      // YYYY-MM-DD — the day this is time-blocked
    var scheduledStartMin: Int = -1     // minutes from midnight (-1 = not scheduled)
    var estimatedMinutes: Int = 30
    var actualMinutes: Int = 0          // cumulative actual time logged
    var calendarEventID: String = ""    // EKEvent identifier
    var recurrenceRaw: String = TaskRecurrenceRule.none.rawValue
    var recurrenceSpawnedTaskIDRaw: String = ""
    var recurrenceSeriesIDRaw: String = ""
    var recurrenceSourceTaskIDRaw: String = ""
    var recurrenceOccurrenceIndex: Int = 0
    // Series end condition. Every attribute is defaulted so lightweight migration can add them
    // without a SchemaMigrationPlan, and existing rows read back as ".never" (repeat forever).
    var recurrenceEndModeRaw: String = TaskRecurrenceEndMode.never.rawValue
    var recurrenceEndDate: String = ""  // YYYY-MM-DD or "" — only meaningful when mode is .onDate
    var recurrenceEndCount: Int = 0     // total occurrences allowed — only meaningful when mode is .afterCount
    var sectionName: String = TaskSectionDefaults.defaultName
    var order: Int = 0
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    var area: Area? = nil
    var project: Project? = nil
    var goal: Goal? = nil
    var context: Context? = nil         // denormalized for efficient queries
    var bundle: TaskBundle? = nil
    var bundleOrder: Int = 0
    var subtasks: [Subtask]? = nil
    var tags: [Tag]? = nil

    // MARK: - Computed

    var isDone: Bool { status == .done }
    var isCancelled: Bool { status == .cancelled }
    var isRecurring: Bool { recurrenceRule != .none }

    var recurrenceSpawnedTaskID: UUID? {
        get { UUID(uuidString: recurrenceSpawnedTaskIDRaw) }
        set { recurrenceSpawnedTaskIDRaw = newValue?.uuidString ?? "" }
    }

    var recurrenceSeriesID: UUID {
        UUID(uuidString: recurrenceSeriesIDRaw) ?? id
    }

    var recurrenceSourceTaskID: UUID? {
        get { UUID(uuidString: recurrenceSourceTaskIDRaw) }
        set { recurrenceSourceTaskIDRaw = newValue?.uuidString ?? "" }
    }

    var isRecurrenceSeriesMember: Bool {
        isRecurring || !recurrenceSeriesIDRaw.isEmpty || !recurrenceSourceTaskIDRaw.isEmpty
    }

    // MARK: - Recurrence end condition
    //
    // `recurrenceOccurrenceIndex` is 0-BASED: the first task of a series is index 0, the task it
    // spawns is index 1, and so on. So the number of occurrences that have existed up to and
    // including this one is `index + 1` — that's what an "after N occurrences" limit counts.

    /// 1-based position of this occurrence in its series (the first task is occurrence 1).
    var recurrenceOccurrenceNumber: Int { max(0, recurrenceOccurrenceIndex) + 1 }

    /// The end mode that actually applies, after discarding configurations that can't be honored:
    /// a task that doesn't recur at all, an `.onDate` with no end date, or an `.afterCount` with a
    /// non-positive count. Those all degrade to `.never` rather than silently killing a series.
    var effectiveRecurrenceEndMode: TaskRecurrenceEndMode {
        guard isRecurring else { return .never }
        switch recurrenceEndMode {
        case .never:
            return .never
        case .onDate:
            return recurrenceEndDate.isEmpty ? .never : .onDate
        case .afterCount:
            return recurrenceEndCount >= 1 ? .afterCount : .never
        }
    }

    /// True when the series can definitively produce nothing further from this occurrence *without*
    /// needing to know what the next occurrence's date would be — i.e. the "after N occurrences"
    /// budget is used up. Date-limited series depend on the successor's date, so ask
    /// `recurrenceAllowsNextOccurrence(on:)` for those.
    var recurrenceHasEnded: Bool {
        effectiveRecurrenceEndMode == .afterCount && recurrenceOccurrenceNumber >= recurrenceEndCount
    }

    /// Whether a successor landing on `nextDateKey` ("yyyy-MM-dd") is still inside the series' end
    /// condition. `nil`/empty means the successor carries no date at all, which no date limit can
    /// exclude. Date keys are fixed-width `yyyy-MM-dd`, so lexicographic compare == chronological.
    func recurrenceAllowsNextOccurrence(on nextDateKey: String?) -> Bool {
        switch effectiveRecurrenceEndMode {
        case .never:
            return true
        case .afterCount:
            return recurrenceOccurrenceNumber < recurrenceEndCount
        case .onDate:
            guard let nextDateKey, !nextDateKey.isEmpty else { return true }
            return nextDateKey <= recurrenceEndDate
        }
    }

    /// The full stop condition the spawn engine asks about: this task recurs, hasn't already
    /// spawned its successor, and the end condition still permits one dated `nextDateKey`.
    func shouldSpawnNextOccurrence(nextDateKey: String?) -> Bool {
        isRecurring
            && recurrenceSpawnedTaskID == nil
            && recurrenceAllowsNextOccurrence(on: nextDateKey)
    }

    /// End time in minutes from midnight (start + duration, default 30min if no estimate)
    var scheduledEndMin: Int {
        guard scheduledStartMin >= 0 else { return -1 }
        return scheduledStartMin + max(estimatedMinutes, 30)
    }

    var containerName: String {
        area?.name ?? project?.name ?? ""
    }

    var containerColor: String {
        area?.colorHex ?? project?.colorHex ?? "#6b7a99"
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

    var sortedTags: [Tag] {
        TagSupport.sorted(tags ?? [])
    }

    init(title: String) {
        self.title = title
    }
}

/// A scheduled container for small tasks that should share one calendar block.
@Model final class TaskBundle {
    var id: UUID = UUID()
    var title: String = ""
    var dateKey: String = ""
    var startMin: Int = 0
    var durationMinutes: Int = 30
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \AppTask.bundle)
    var tasks: [AppTask]? = nil

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Task Bundle" : trimmed
    }

    var endMin: Int {
        startMin + max(durationMinutes, 5)
    }

    var sortedTasks: [AppTask] {
        (tasks ?? [])
            .filter { !$0.isCancelled && $0.bundle?.id == id }
            .sorted {
                if $0.bundleOrder != $1.bundleOrder {
                    return $0.bundleOrder < $1.bundleOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    var activeTasks: [AppTask] {
        sortedTasks.filter { !$0.isDone }
    }

    var isCompleted: Bool {
        !sortedTasks.isEmpty && activeTasks.isEmpty
    }

    var totalEstimatedMinutes: Int {
        sortedTasks.reduce(0) { $0 + max($1.estimatedMinutes, 5) }
    }

    init(title: String, dateKey: String, startMin: Int, durationMinutes: Int) {
        self.title = title
        self.dateKey = dateKey
        self.startMin = startMin
        self.durationMinutes = max(durationMinutes, 5)
    }
}
