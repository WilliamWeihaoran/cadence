import SwiftUI

nonisolated enum CadenceFeatureSectionKind: String, Identifiable, Hashable {
    case progress
    case organize
    case workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .progress: return "Progress"
        case .organize: return "Organize"
        case .workspace: return "Workspace"
        }
    }
}

nonisolated struct CadenceFeatureSection: Identifiable, Hashable {
    let kind: CadenceFeatureSectionKind
    let destinations: [CadenceFeatureDestination]

    var id: CadenceFeatureSectionKind { kind }
    var title: String { kind.title }
}

nonisolated enum CadenceFeatureDestination: String, CaseIterable, Identifiable, Hashable {
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

    /// The default order of the rows Settings → Sidebar offers a handle for, which is also
    /// `SidebarStaticDestination.defaultOrder`. `.inbox` is not among them any more: it is a view
    /// inside the Tasks row rather than a row, so offering it a place in the row order would be
    /// offering a control that moves nothing.
    static let desktopSidebarOrder: [CadenceFeatureDestination] = [
        .today,
        .allTasks,
        .focus,
        .calendar,
        .goals,
        .habits
    ]

    // `workspaceDrawerSections` used to list every destination for the iPad drawer to draw. The
    // drawer is gone entirely — lists are rows in the sidebar now — and `primaryOrder`,
    // `secondaryOrder` and `utilityOrder` went with it: they were the iPad sidebar's own PLAN /
    // WORKSPACE / PROGRESS grouping, and that column reads `CadenceSidebarLayout` now, which is the
    // same grouping macOS reads.

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

    /// The short label, for a sidebar row, an iPad column and an iPhone tab.
    ///
    /// `.allTasks` reads **Tasks** because the destination hosts both All and Inbox
    /// (`CadenceTasksPageScope`) — a row labelled "All Tasks" would be naming one of its own two
    /// views. `CadenceSidebarLayout.rowTitle(for:)` is how the sidebars ask for it.
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

    /// The destination's glyph tint when the user has not overridden it, as a hex string because
    /// that is what `CadencePreferenceKeys.sidebarTabColors` stores an override as.
    ///
    /// **Every arm reads a `Theme` accent token; none of them spells a hex.** These are app-defined
    /// palette decisions that merely happen to be typed as strings, and for a long time ten of the
    /// eleven were hand-written literals here — a second copy of a palette `Theme` already owned,
    /// which had already drifted from it in three of the five hues (T-166). The visible symptom was
    /// two ambers for one destination: the sidebar drew Today in `#FFB84D` while the Cmd+K palette,
    /// which derives its tint from `Theme.amber`, drew it in `#ffa94d`. `Theme.tealHex` existed
    /// precisely so `.focus` would not have to, and was the only arm getting it right.
    ///
    /// The families are `Theme`'s, and they are documented on `Theme.tealHex`: amber is Today and
    /// Habits, blue is Tasks/Inbox and Settings, purple is Notes and Search, green is Lists and
    /// Goals, red is Calendar, teal is Focus. Two destinations sharing a token is how they read as
    /// related — it is not a duplicate to be split.
    ///
    /// `CadenceFeatureDestinationTintTests` pins that no arm here is a literal. Adding one back —
    /// even one whose value matches its token exactly — reopens the drift, because the next hue
    /// change to `Theme` will not reach it.
    var defaultColorHex: String {
        switch self {
        case .today: return Theme.amberHex
        case .allTasks: return Theme.blueHex
        case .focus: return Theme.tealHex
        case .inbox: return Theme.blueHex
        // Red, at the user's request. This collided with `.focus`, which was the same hex;
        // Focus moved to `Theme.tealHex` rather than Calendar giving the red back, because red
        // on a calendar reads as urgency and teal on a timer reads as nothing, which is what a
        // timer should read as. See `Theme.teal` for why a sixth accent beat reusing one.
        case .calendar: return Theme.redHex
        case .notes: return Theme.purpleHex
        case .lists: return Theme.greenHex
        case .goals: return Theme.greenHex
        case .habits: return Theme.amberHex
        case .search: return Theme.purpleHex
        case .settings: return Theme.blueHex
        }
    }
}

nonisolated enum CadenceFeatureBadgeSupport {
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
