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

/// **Not `nonisolated`, and it is the only thing in this file that is not.** Everything else here
/// is a pure mapping over two enums; this one resolves through `CadenceSidebarLayout`, which the
/// project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes main-actor-isolated. Reaching it
/// from a nonisolated context is a warning, and the warning baseline is zero. Both callers — a
/// SwiftUI view body and `CadenceCompactTabTests`, which is `@MainActor` — are already there, so
/// nothing is paying for this.
extension CadenceCompactTab {
    /// The rows the iPhone's **Tasks index** lists above its lists — the destination half of the
    /// screen the Tasks tab opens on (T-2072).
    ///
    /// *"you see all the lists and you can go into each list, then you can also go to different
    /// views that we have, such as inbox and today and all tasks"*. The views are these rows; the
    /// lists under them are `CadenceSidebarLists.sections(contexts:items:)`, the same value the
    /// iPad column draws.
    ///
    /// **Resolved through `CadenceSidebarLayout` rather than listed here**, so the index honours
    /// the synced hidden set and the user's order (T-1274) instead of being a fourth place that
    /// decides which task surfaces exist. A Today hidden in Settings → Sidebar is hidden on the
    /// phone's index too, which is the whole point of that preference being synced.
    ///
    /// **`.inbox` is appended to `.allTasks` rather than taken from the sidebar's list**, because
    /// the sidebar deliberately has no Inbox row: `CadenceSidebarLayout.navRow(for:)` says Inbox is
    /// reached *through* the Tasks row, and `CadenceTasksPageScope` is the switch inside it. The
    /// owner asked for Inbox as a row **in this index**, which is a compact-shell presentation of a
    /// destination that already exists — the same thing the command palette does when it offers
    /// "Inbox" as its own entry. Nothing about the iPad or macOS column changes, and the row still
    /// opens the merged Tasks page, so the two shells stay one design rather than two.
    ///
    /// Hiding Tasks therefore hides Inbox with it: the sidebar's own rule is that Inbox's row *is*
    /// the Tasks row, so a hidden Tasks row cannot leave one of its two views on screen.
    ///
    /// Only destinations this tab owns survive the filter, so Calendar, Notes, Goals and Habits
    /// stay where their own tabs put them however the user reorders the sidebar.
    static func tasksIndexDestinations(
        storedOrder: [CadenceFeatureDestination] = [],
        hidden: Set<CadenceFeatureDestination> = []
    ) -> [CadenceFeatureDestination] {
        CadenceSidebarLayout.resolvedDestinations(
            in: .primary,
            customisable: CadenceSidebarLayout.customisableDestinations,
            storedOrder: storedOrder,
            hidden: hidden
        )
        .filter { $0.compactTab == .tasks }
        .flatMap { $0 == .allTasks ? [CadenceFeatureDestination.allTasks, .inbox] : [$0] }
    }
}

/// The three slices of work the Tasks tab holds.
///
/// **They were a segmented control in the tab's header until T-2072**, where they became rows in
/// the tab's index. What the enum is did not change: it is still the one place that says there are
/// three slices, what each is called, and which destination each opens — read by
/// `CadenceTasksPageScope` for the merged page's two labels, and by `compactTasksSection` for the
/// slice a route names. `ios.compact.tasksSection` still records which slice the shell last
/// opened, which is what a widening size class reads when nothing is pushed.
nonisolated enum CadenceTasksSection: String, CaseIterable, Identifiable, Hashable {
    // Order is the index's order, and it is a narrowing: today, then the unfiled things you might
    // pull into today, then everything. `all` last because it is the widest and the least often
    // wanted. Raw values are persisted (`ios.compact.tasksSection`) and are unchanged by the
    // reordering — `allCases` order is presentation, `rawValue` is storage, and only the first of
    // those moved.
    case today
    case inbox
    case all

    var id: String { rawValue }

    static let defaultSection: CadenceTasksSection = .today

    static func resolved(_ rawValue: String) -> CadenceTasksSection {
        CadenceTasksSection(rawValue: rawValue) ?? defaultSection
    }

    /// The slice's short label — the merged page's switcher reads it, and the index's Tasks row
    /// does not (a row has the width for `compactTitle`). Short on purpose: the tab is already
    /// named Tasks, so "All Tasks" would say the word twice in 60pt.
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

/// Where a destination lands in the compact shell: which tab, which Tasks slice (if the Tasks
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

    /// The Tasks slice this destination is, or `nil` when another tab owns it. Recorded on the
    /// route so `ios.compact.tasksSection` keeps naming the slice the shell last opened.
    var compactTasksSection: CadenceTasksSection? {
        switch self {
        case .today: return .today
        case .allTasks: return .all
        case .inbox: return .inbox
        case .calendar, .notes, .focus, .lists, .goals, .habits, .search, .settings: return nil
        }
    }

    /// Whether selecting this destination's tab is enough to show it, with nothing pushed.
    ///
    /// **The Tasks tab stopped being one of those (T-2072).** Its root is an index — Today, Tasks
    /// and Inbox as rows, then every list — so selecting the tab shows the index and each of its
    /// three task surfaces is a push, exactly as a More row is. A widget or deep link naming Today
    /// has to ask for that push; left `true`, it would select the Tasks tab, land on the index, and
    /// report that it had arrived.
    var isCompactTabRoot: Bool {
        switch compactTab {
        case .calendar, .notes: return true
        case .tasks, .more: return false
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
    /// The feature a link opens *before* the store is consulted. `.task` answers Today here
    /// because Today is where a live task's row lives, and the row turns
    /// `CadenceDeepLinkManager.pendingTaskID` into a detail sheet.
    ///
    /// **Roots must not route a `.task` link on this alone.** Today's scope excludes done and
    /// cancelled work and anything dated for another day, so this answer is wrong for a large
    /// class of real links; `CadenceDeepLinkManager.resolvedDestination(for:modelContext:)` fetches
    /// the row and overrides it (and disarms `pendingTaskID`) when Today will not show it. This
    /// property remains the answer for every singleton route, and the pre-resolution answer for
    /// `.task`.
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
