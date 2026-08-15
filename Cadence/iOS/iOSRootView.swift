#if os(iOS)
import SwiftData
import SwiftUI

enum iOSSidebarItem: Hashable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case goals
    case habits
    case notes
    case lists
    case search
    case settings
    case area(UUID)
    case project(UUID)
}

struct iOSRootView: View {
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasksForNotifications: [AppTask]
    @Query private var allHabitsForNotifications: [Habit]
    @State private var selection: iOSSidebarItem? = .today
    /// One `NavigationPath` per compact tab, so switching tabs preserves where you were. Each is
    /// type-erased — see `iOSCompactTabPaths`.
    @State private var compactPaths = iOSCompactTabPaths()
    /// Restored across launches, like `ios.calendar.anchorDateKey`.
    ///
    /// Written from exactly two places, both of them deliberate acts: a tap on a bar item, and a
    /// deep link (which is a tap on a widget or a URL). Nothing derived, nothing measured, nothing
    /// written during layout — that is the lesson of `ecaf80f`, where a persisted navigation value
    /// took an initial scroll reading for a user action and then compounded across launches.
    @AppStorage("ios.compact.selectedTab") private var selectedTabRaw = CadenceCompactTab.defaultTab.rawValue
    @AppStorage("ios.compact.tasksSection") private var tasksSectionRaw = CadenceTasksSection.defaultSection.rawValue

    private var selectedTab: CadenceCompactTab {
        CadenceCompactTab.resolved(selectedTabRaw)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadMacStyleRootShell(selection: $selection) {
                    detailView(for: selection ?? .today)
                }
            } else {
                iOSCompactRootShell(
                    selectedTab: Binding(
                        get: { selectedTab },
                        set: { selectedTabRaw = $0.rawValue }
                    ),
                    tasksSection: Binding(
                        get: { CadenceTasksSection.resolved(tasksSectionRaw) },
                        set: { tasksSectionRaw = $0.rawValue }
                    ),
                    paths: $compactPaths
                )
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .statusBarHidden(horizontalSizeClass == .regular)
        .onOpenURL { url in
            CadenceDeepLinkManager.shared.handle(url)
        }
        .onChange(of: deepLinkManager.route?.token) { _, _ in
            handleDeepLinkRoute()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                CadenceWidgetRefreshCenter.reloadAllWidgets()
                let tasks = allTasksForNotifications
                let habits = allHabitsForNotifications
                Task { await NotificationManager.shared.reconcile(tasks: tasks, habits: habits) }
            }
        }
    }

    @ViewBuilder
    private func detailView(for item: iOSSidebarItem) -> some View {
        switch item {
        case .today:
            iPadTodayView()
        case .allTasks:
            iOSAllTasksView()
        case .focus:
            iOSFocusView()
        case .inbox:
            iPadInboxView()
        case .calendar:
            iOSCalendarView()
        case .goals:
            iOSGoalsView()
        case .habits:
            iOSHabitsView()
        case .notes:
            NavigationStack {
                iOSCompactNotesView()
                    .toolbar(.hidden, for: .navigationBar)
            }
        case .lists:
            NavigationStack {
                iOSListsView()
            }
        case .search:
            NavigationStack {
                iOSSearchView()
            }
        case .settings:
            iOSSettingsView()
        case .area(let id):
            if let area = areas.first(where: { $0.id == id }) {
                iOSListDetailView(area: area)
            } else {
                iOSMissingListView()
            }
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                iOSListDetailView(project: project)
            } else {
                iOSMissingListView()
            }
        }
    }
}

private extension iOSRootView {
    /// One route, resolved once, applied to both shells.
    ///
    /// The compact half is the part that changed shape: a link used to be a push onto the single
    /// stack, and now it has to answer *which tab* first. `CadenceCompactRoute` (in `Shared/`, with
    /// tests) is where that answer lives, so a widget tap cannot land on the wrong tab without a
    /// test failing.
    func handleDeepLinkRoute() {
        guard let deepLink = deepLinkManager.route?.deepLink else { return }
        let destination = deepLink.featureDestination
        selection = destination.item
        apply(deepLink.compactRoute)
    }

    /// Only the target tab's stack is touched. Pushing onto — or clearing — a tab the link did not
    /// name would quietly rearrange a screen the user is not looking at and will come back to.
    func apply(_ route: CadenceCompactRoute) {
        selectedTabRaw = route.tab.rawValue
        if let section = route.tasksSection {
            tasksSectionRaw = section.rawValue
        }
        compactPaths[route.tab] = route.pushedDestination.map { NavigationPath([$0]) } ?? NavigationPath()
    }
}
#endif
