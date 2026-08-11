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

    /// Sort weight, high to none. Every "sort by priority" in the app means this.
    ///
    /// This existed as six independent `switch` statements — in `CadenceTaskQuerySupport`, in
    /// `CadenceCalendarPlanningSupport` (private, *the same folder*), in `GoalContributionSummary`,
    /// in the Today widget, and twice under `iOS/`. They agreed, which is the state that precedes
    /// drift; every bug found in this repo's audits came from one idea implemented more than once.
    /// The ordering is a property of the enum, so it lives on the enum.
    ///
    /// `nonisolated` because widget timeline providers run off the main actor and this module
    /// defaults to `MainActor` isolation.
    nonisolated var rank: Int {
        switch self {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        case .none:   return 0
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

    var label: String {
        switch self {
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "play.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
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

/// How a recurring series stops. `.never` is the default and preserves the historical
/// behavior (a series that repeats forever). The other two cases are paired with
/// `AppTask.recurrenceEndDate` ("yyyy-MM-dd") and `AppTask.recurrenceEndCount` respectively.
enum TaskRecurrenceEndMode: String, Codable, CaseIterable, Hashable {
    case never      = "never"
    case onDate     = "onDate"
    case afterCount = "afterCount"

    var label: String {
        switch self {
        case .never: return "Never"
        case .onDate: return "On Date"
        case .afterCount: return "After"
        }
    }

    var shortLabel: String {
        switch self {
        case .never: return "Never"
        case .onDate: return "Date"
        case .afterCount: return "Count"
        }
    }

    var systemImage: String {
        switch self {
        case .never: return "infinity"
        case .onDate: return "calendar.badge.checkmark"
        case .afterCount: return "number"
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

    var label: String {
        switch self {
        case .active: return "Active"
        case .done: return "Done"
        case .paused: return "Paused"
        }
    }
}

/// Shape of a goal. Top-level goals are typically `.ongoing` — a long-running direction,
/// which is what the retired `Pursuit` model used to represent — while nested goals are
/// typically `.completable`, a milestone with a finish line.
enum GoalKind: String, Codable, CaseIterable, Hashable {
    case ongoing = "ongoing"
    case completable = "completable"
    case maintenance = "maintenance"

    var label: String {
        switch self {
        case .ongoing: return "Ongoing"
        case .completable: return "Completable"
        case .maintenance: return "Maintenance"
        }
    }

    var detail: String {
        switch self {
        case .ongoing: return "Long-running growth"
        case .completable: return "Has a finish line"
        case .maintenance: return "Keep steady"
        }
    }

    var systemImage: String {
        switch self {
        case .ongoing: return "infinity"
        case .completable: return "flag.fill"
        case .maintenance: return "repeat"
        }
    }
}

enum GoalProgressType: String, Codable, CaseIterable, Hashable {
    case subtasks = "subtasks"
    case hours    = "hours"

    /// The `.subtasks` raw value is persisted and stays as it is; the label does not.
    /// This mode counts whole `AppTask` rows — `Subtask` is a different model that never takes
    /// part in the ratio — so "Subtasks" named something the number has nothing to do with.
    var label: String {
        switch self {
        case .subtasks: return "Tasks"
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
