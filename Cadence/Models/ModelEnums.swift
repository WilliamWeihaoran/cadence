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

enum TaskRecurrenceRule: String, Codable, CaseIterable, Hashable {
    case none    = "none"
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"
    case yearly  = "yearly"

    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "arrow.clockwise"
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .monthly: return "calendar.badge.clock"
        case .yearly: return "calendar.circle"
        }
    }
}

// MARK: - Project enums

enum ProjectStatus: String, Codable, CaseIterable, Hashable {
    case active    = "active"
    case done      = "done"
    case archived  = "archived"
    case paused    = "paused"
    case cancelled = "cancelled"
}

enum AreaStatus: String, Codable, CaseIterable, Hashable {
    case active   = "active"
    case done     = "done"
    case archived = "archived"
}

// MARK: - Goal enums

enum GoalStatus: String, Codable, CaseIterable, Hashable {
    case active = "active"
    case done   = "done"
    case paused = "paused"
}

enum PursuitStatus: String, Codable, CaseIterable, Hashable {
    case active = "active"
    case done   = "done"
    case paused = "paused"

    var label: String {
        switch self {
        case .active: return "Active"
        case .done: return "Done"
        case .paused: return "Paused"
        }
    }
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
