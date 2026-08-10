import SwiftUI

enum CadenceFeatureSectionKind: String, Identifiable, Hashable {
    case plan
    case progress
    case organize
    case workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .progress: return "Progress"
        case .organize: return "Organize"
        case .workspace: return "Workspace"
        }
    }
}

struct CadenceFeatureSection: Identifiable, Hashable {
    let kind: CadenceFeatureSectionKind
    let destinations: [CadenceFeatureDestination]

    var id: CadenceFeatureSectionKind { kind }
    var title: String { kind.title }
}

enum CadenceFeatureDestination: String, CaseIterable, Identifiable, Hashable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case notes
    case lists
    case goals
    case habits
    case search
    case settings

    var id: String { rawValue }

    static let desktopSidebarOrder: [CadenceFeatureDestination] = [
        .today,
        .allTasks,
        .focus,
        .inbox,
        .calendar,
        .goals,
        .habits
    ]

    static let primaryOrder: [CadenceFeatureDestination] = [
        .today,
        .allTasks,
        .inbox,
        .calendar
    ]

    static let secondaryOrder: [CadenceFeatureDestination] = [
        .notes,
        .focus,
        .lists,
        .goals,
        .habits
    ]

    static let utilityOrder: [CadenceFeatureDestination] = [
        .search,
        .settings
    ]

    static let workspaceDrawerSections: [CadenceFeatureSection] = [
        CadenceFeatureSection(kind: .plan, destinations: primaryOrder),
        CadenceFeatureSection(kind: .progress, destinations: [.focus, .goals, .habits]),
        CadenceFeatureSection(kind: .organize, destinations: [.notes, .lists]),
        CadenceFeatureSection(kind: .workspace, destinations: utilityOrder)
    ]

    static let compactHomeSections: [CadenceFeatureSection] = [
        CadenceFeatureSection(kind: .plan, destinations: primaryOrder),
        CadenceFeatureSection(kind: .progress, destinations: [.focus, .goals, .habits]),
        CadenceFeatureSection(kind: .organize, destinations: [.notes, .lists])
    ]

    var isPrimaryNavigation: Bool {
        switch self {
        case .today, .allTasks, .focus, .inbox, .calendar:
            return true
        case .notes, .lists, .goals, .habits, .search, .settings:
            return false
        }
    }

    var isTrackingNavigation: Bool {
        switch self {
        case .goals, .habits:
            return true
        case .today, .allTasks, .focus, .inbox, .calendar, .notes, .lists, .search, .settings:
            return false
        }
    }

    var isUtilityNavigation: Bool {
        switch self {
        case .search, .settings:
            return true
        case .today, .allTasks, .focus, .inbox, .calendar, .notes, .lists, .goals, .habits:
            return false
        }
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .focus: return "Focus"
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .notes: return "Notes"
        case .lists: return "Lists"
        case .goals: return "Goals"
        case .habits: return "Habits"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    var compactTitle: String {
        switch self {
        case .allTasks: return "Tasks"
        default: return title
        }
    }

    var subtitle: String {
        switch self {
        case .today: return "Plan the current day"
        case .allTasks: return "Review active and completed work"
        case .focus: return "Run focused sessions"
        case .inbox: return "Capture and triage"
        case .calendar: return "Schedule tasks and events"
        case .notes: return "Daily and permanent notes"
        case .lists: return "Areas, projects, and lists"
        case .goals: return "Directions and milestones"
        case .habits: return "Recurring progress"
        case .search: return "Find tasks and notes"
        case .settings: return "Workspace preferences"
        }
    }

    var searchSummary: String {
        switch self {
        case .today: return "Tasks, notes, and schedule"
        case .allTasks: return "Full task index"
        case .focus: return "Timer and current work"
        case .inbox: return "Capture and triage"
        case .calendar: return "Timeline, month, and board"
        case .notes: return "Daily, weekly, and permanent notes"
        case .lists: return "Areas, projects, and lists"
        case .goals: return "Directions and milestones"
        case .habits: return "Repeating commitments"
        case .search: return "Find anything in Cadence"
        case .settings: return "Preferences and diagnostics"
        }
    }

    var searchKeywords: String {
        switch self {
        case .today:
            return "today plan tasks notes schedule agenda do date due date"
        case .allTasks:
            return "all tasks task index completed active priority due scheduled"
        case .focus:
            return "focus timer pomodoro session current work"
        case .inbox:
            return "inbox capture triage unsorted quick add"
        case .calendar:
            return "calendar schedule timeline month board events bundles"
        case .notes:
            return "notes daily weekly notepad markdown permanent meeting"
        case .lists:
            return "lists areas projects contexts organize kanban planning links"
        case .goals:
            return "goals milestones outcomes progress timeline pursuits aspirations directions"
        case .habits:
            return "habits routines streaks recurring commitments"
        case .search:
            return "search find lookup command"
        case .settings:
            return "settings preferences sync tags themes account data diagnostics"
        }
    }

    var searchAliases: String {
        "\(rawValue) \(title) \(compactTitle) \(subtitle) \(searchSummary) \(searchKeywords)"
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .allTasks: return "checklist"
        case .focus: return "timer"
        case .inbox: return "tray.fill"
        case .calendar: return "calendar"
        case .notes: return "note.text"
        case .lists: return "folder.fill"
        case .goals: return "flag.fill"
        case .habits: return "flame.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        Color(hex: defaultColorHex)
    }

    var defaultColorHex: String {
        switch self {
        case .today: return "#FFB84D"
        case .allTasks: return "#5AA2FF"
        case .focus: return "#FF6B6B"
        case .inbox: return "#5AA2FF"
        case .calendar: return "#9E8CFF"
        case .notes: return "#9E8CFF"
        case .lists: return "#4ECB71"
        case .goals: return "#4ECB71"
        case .habits: return "#FFB84D"
        case .search: return "#9E8CFF"
        case .settings: return "#5AA2FF"
        }
    }
}

enum CadenceFeatureBadgeSupport {
    struct Snapshot {
        let todayCount: Int
        let allTaskCount: Int
        let inboxCount: Int
        let activeGoalCount: Int
        let habitCount: Int
        let activeListCount: Int

        init(
            tasks: [AppTask],
            todayKey: String = DateFormatters.todayKey(),
            activeGoalCount: Int = 0,
            habitCount: Int = 0,
            activeListCount: Int = 0
        ) {
            self.todayCount = CadenceTaskQuerySupport.scheduledOrDueTodayCount(from: tasks, todayKey: todayKey)
            self.allTaskCount = CadenceTaskQuerySupport.openTaskCount(from: tasks)
            self.inboxCount = CadenceTaskQuerySupport.openInboxTaskCount(from: tasks)
            self.activeGoalCount = activeGoalCount
            self.habitCount = habitCount
            self.activeListCount = activeListCount
        }

        func count(for destination: CadenceFeatureDestination) -> Int? {
            switch destination {
            case .today:
                return CadenceTaskQuerySupport.badgeCount(todayCount)
            case .allTasks:
                return CadenceTaskQuerySupport.badgeCount(allTaskCount)
            case .inbox:
                return CadenceTaskQuerySupport.badgeCount(inboxCount)
            case .goals:
                return activeGoalCount > 0 ? activeGoalCount : nil
            case .habits:
                return habitCount > 0 ? habitCount : nil
            case .lists:
                return activeListCount > 0 ? activeListCount : nil
            case .focus, .calendar, .notes, .search, .settings:
                return nil
            }
        }
    }

    static func count(
        for destination: CadenceFeatureDestination,
        tasks: [AppTask],
        todayKey: String = DateFormatters.todayKey(),
        activeGoalCount: Int = 0,
        habitCount: Int = 0,
        activeListCount: Int = 0
    ) -> Int? {
        Snapshot(
            tasks: tasks,
            todayKey: todayKey,
            activeGoalCount: activeGoalCount,
            habitCount: habitCount,
            activeListCount: activeListCount
        )
        .count(for: destination)
    }
}
