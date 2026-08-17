import SwiftUI

/// The iPhone shell's bottom bar.
///
/// Four tabs, and a capture control between Calendar and Notes that is deliberately **not** one of
/// them — it presents a sheet, it never selects, so it has no case here. That is the whole reason
/// this is an enum of four rather than five: a `+` that could be `selection` would eventually be
/// drawn selected by some code path that treats every bar item alike.
///
/// It lives in `Shared/` rather than next to the shell because `Cadence/iOS/` is entirely inside
/// `#if os(iOS)` and therefore invisible to `CadenceTests`, which builds for macOS. The mapping
/// below is the one thing in the tab shell that can silently strand a whole feature — a
/// destination that answers "no tab owns me" is a screen nothing can reach — so it has to be
/// testable.
nonisolated enum CadenceCompactTab: String, CaseIterable, Identifiable, Hashable {
    case tasks
    case calendar
    case notes
    case more

    var id: String { rawValue }

    /// Tasks, not Today. The app opens on the list of work, and which slice of it you saw last is
    /// remembered separately by `CadenceTasksSection`.
    static let defaultTab: CadenceCompactTab = .tasks

    /// Persisted values are read back through here so an unknown or empty string lands on the
    /// default instead of leaving the shell with no selection.
    static func resolved(_ rawValue: String) -> CadenceCompactTab {
        CadenceCompactTab(rawValue: rawValue) ?? defaultTab
    }

    var title: String {
        switch self {
        case .tasks: return "Tasks"
        case .calendar: return "Calendar"
        case .notes: return "Notes"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .tasks: return CadenceFeatureDestination.allTasks.systemImage
        case .calendar: return CadenceFeatureDestination.calendar.systemImage
        case .notes: return CadenceFeatureDestination.notes.systemImage
        case .more: return "square.grid.2x2.fill"
        }
    }

    /// Every destination this tab owns, in the order the tab presents them. The union across all
    /// four tabs is exactly `CadenceFeatureDestination.allCases` — see `CadenceCompactTabTests`.
    var destinations: [CadenceFeatureDestination] {
        CadenceFeatureDestination.allCases.filter { $0.compactTab == self }
    }
}

/// The three slices of work the Tasks tab switches between, selected by a segmented control in its
/// header — deliberately the same control the Calendar tab uses for Week/Month/Board, so the two
/// are learned once.
nonisolated enum CadenceTasksSection: String, CaseIterable, Identifiable, Hashable {
    case today
    case all
    case inbox

    var id: String { rawValue }

    static let defaultSection: CadenceTasksSection = .today

    static func resolved(_ rawValue: String) -> CadenceTasksSection {
        CadenceTasksSection(rawValue: rawValue) ?? defaultSection
    }

    /// The segment's label. Short on purpose — three segments share one row, and the tab is
    /// already named Tasks, so "All Tasks" would say the word twice in 60pt.
    var title: String {
        switch self {
        case .today: return "Today"
        case .all: return "All"
        case .inbox: return "Inbox"
        }
    }

    var destination: CadenceFeatureDestination {
        switch self {
        case .today: return .today
        case .all: return .allTasks
        case .inbox: return .inbox
        }
    }
}

/// Where a destination lands in the compact shell: which tab, which Tasks segment (if the Tasks
/// tab owns it), and whether the tab's stack needs a push to show it.
///
/// `pushedDestination == nil` means the destination *is* the tab's root — selecting the tab shows
/// it, and the stack should be emptied rather than pushed onto. That distinction is what keeps a
/// widget tap from stacking a second Calendar on top of the Calendar you were already looking at.
nonisolated struct CadenceCompactRoute: Equatable {
    var tab: CadenceCompactTab
    var tasksSection: CadenceTasksSection?
    var pushedDestination: CadenceFeatureDestination?
}

nonisolated extension CadenceFeatureDestination {
    /// Which tab owns this destination. Exhaustive by construction — adding a case to
    /// `CadenceFeatureDestination` without answering this question will not compile.
    var compactTab: CadenceCompactTab {
        switch self {
        case .today, .allTasks, .inbox:
            return .tasks
        case .calendar:
            return .calendar
        case .notes:
            return .notes
        case .focus, .lists, .goals, .habits, .search, .settings:
            return .more
        }
    }

    /// The Tasks segment that shows this destination, or `nil` when another tab owns it.
    var compactTasksSection: CadenceTasksSection? {
        switch self {
        case .today: return .today
        case .allTasks: return .all
        case .inbox: return .inbox
        case .calendar, .notes, .focus, .lists, .goals, .habits, .search, .settings: return nil
        }
    }

    /// Whether selecting this destination's tab is enough to show it, with nothing pushed.
    var isCompactTabRoot: Bool {
        switch compactTab {
        case .tasks, .calendar, .notes: return true
        case .more: return false
        }
    }

    var compactRoute: CadenceCompactRoute {
        CadenceCompactRoute(
            tab: compactTab,
            tasksSection: compactTasksSection,
            pushedDestination: isCompactTabRoot ? nil : self
        )
    }
}

nonisolated extension CadenceDeepLink {
    /// The feature a link opens. `.task` resolves to Today rather than to a screen of its own:
    /// the task itself is surfaced by `CadenceDeepLinkManager.pendingTaskID`, which the task rows
    /// watch and turn into a detail sheet.
    var featureDestination: CadenceFeatureDestination {
        switch self {
        case .today, .task: return .today
        case .habits: return .habits
        case .goals: return .goals
        case .calendar: return .calendar
        }
    }

    var compactRoute: CadenceCompactRoute {
        featureDestination.compactRoute
    }
}

nonisolated extension CadenceFeatureDestination {
    /// The More tab's contents, under quiet eyebrows. Search sits under Workspace next to
    /// Settings rather than beside the task surfaces, because from here it searches everything.
    static let compactMoreSections: [CadenceFeatureSection] = [
        CadenceFeatureSection(kind: .progress, destinations: [.focus, .goals, .habits]),
        CadenceFeatureSection(kind: .organize, destinations: [.lists]),
        CadenceFeatureSection(kind: .workspace, destinations: [.search, .settings])
    ]
}
