#if os(iOS)
import SwiftData
import SwiftUI

enum iOSSidebarItem: Hashable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case pursuits
    case goals
    case habits
    case lists
    case search
    case settings
    case area(UUID)
    case project(UUID)
}

struct iOSRootView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var selection: iOSSidebarItem? = .today
    @State private var compactTabSelection: iOSRootTab = .today

    var body: some View {
        let _ = themeManager.selectedTheme

        Group {
            if horizontalSizeClass == .regular {
                iPadMacStyleRootShell(selection: $selection) {
                    detailView(for: selection ?? .today)
                }
            } else {
                TabView(selection: $compactTabSelection) {
                    NavigationStack {
                        iPadTodayView()
                    }
                    .tabItem {
                        Label("Today", systemImage: "sun.max.fill")
                    }
                    .tag(iOSRootTab.today)

                    NavigationStack {
                        iPadInboxView()
                    }
                    .tabItem {
                        Label("Inbox", systemImage: "tray.fill")
                    }
                    .tag(iOSRootTab.inbox)

                    NavigationStack {
                        iOSListsView()
                    }
                    .tabItem {
                        Label("Lists", systemImage: "folder.fill")
                    }
                    .tag(iOSRootTab.lists)

                    NavigationStack {
                        iOSSearchView()
                    }
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(iOSRootTab.search)

                    NavigationStack {
                        iOSMoreView()
                    }
                    .tabItem {
                        Label("More", systemImage: "ellipsis.circle.fill")
                    }
                    .tag(iOSRootTab.more)
                }
                .tint(Theme.blue)
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
                CadenceWidgetRefreshCenter.reloadTodayWidgets()
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
        case .pursuits:
            iOSPursuitsView()
        case .goals:
            iOSMilestonesView()
        case .habits:
            iOSHabitsView()
        case .lists:
            NavigationStack {
                iOSListsView()
            }
        case .search:
            NavigationStack {
                iOSSearchView()
            }
        case .settings:
            NavigationStack {
                iOSSettingsView()
            }
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

private enum iOSRootTab: Hashable {
    case today
    case inbox
    case lists
    case search
    case more
}

private extension iOSRootView {
    func handleDeepLinkRoute() {
        guard let route = deepLinkManager.route?.deepLink else { return }
        switch route {
        case .today, .task:
            selection = .today
            compactTabSelection = .today
        }
    }
}
#endif
