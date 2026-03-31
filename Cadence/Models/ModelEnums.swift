import Foundation

// MARK: - Task enums

enum TaskPriority: String, Codable, CaseIterable, Hashable {
    case none     = "none"
    case low      = "low"
    case medium   = "medium"
    case high     = "high"

    var label: String {
        switch self {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var nextCycled: TaskPriority {
        switch self {
        case .none: return .low
        case .low: return .medium
        case .medium: return .high
        case .high: return .none
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Hashable {
    case todo        = "todo"
    case inProgress  = "inprogress"
    case done        = "done"
    case cancelled   = "cancelled"
}

// MARK: - Project enums

enum ProjectStatus: String, Codable, CaseIterable, Hashable {
    case active    = "active"
    case done      = "done"
    case paused    = "paused"
    case cancelled = "cancelled"
}

// MARK: - Goal enums

enum GoalStatus: String, Codable, CaseIterable, Hashable {
    case active = "active"
    case done   = "done"
    case paused = "paused"
}

enum GoalProgressType: String, Codable, CaseIterable, Hashable {
    case subtasks = "subtasks"
    case hours    = "hours"

    var label: String {
        switch self {
        case .subtasks: return "Subtasks"
        case .hours:    return "Hours"
        }
    }
}

// MARK: - Habit enums

enum HabitFrequency: String, Codable, CaseIterable, Hashable {
    case daily         = "daily"
    case daysOfWeek    = "daysOfWeek"
    case timesPerWeek  = "timesPerWeek"
    case monthly       = "monthly"

    var label: String {
        switch self {
        case .daily:        return "Daily"
        case .daysOfWeek:   return "Days of Week"
        case .timesPerWeek: return "Times per Week"
        case .monthly:      return "Monthly"
        }
    }
}
