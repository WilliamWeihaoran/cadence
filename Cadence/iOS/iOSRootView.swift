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
    case notes
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
    @State private var compactMorePath: [CadenceFeatureDestination] = []

    var body: some View {
        let _ = themeManager.selectedTheme

        Group {
            if horizontalSizeClass == .regular {
                iPadMacStyleRootShell(selection: $selection) {
                    detailView(for: selection ?? .today)
                }
            } else {
                iOSCompactRootShell(
                    selection: $compactTabSelection,
                    morePath: $compactMorePath
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

private enum iOSRootTab: Hashable {
    case today
    case inbox
    case notes
    case search
    case more

    var title: String {
        switch self {
        case .today: return CadenceFeatureDestination.today.compactTitle
        case .inbox: return CadenceFeatureDestination.inbox.compactTitle
        case .notes: return CadenceFeatureDestination.notes.compactTitle
        case .search: return "Search"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return CadenceFeatureDestination.today.systemImage
        case .inbox: return CadenceFeatureDestination.inbox.systemImage
        case .notes: return CadenceFeatureDestination.notes.systemImage
        case .search: return CadenceFeatureDestination.search.systemImage
        case .more: return "ellipsis"
        }
    }
}

private struct iOSCompactRootShell: View {
    @Binding var selection: iOSRootTab
    @Binding var morePath: [CadenceFeatureDestination]

    var body: some View {
        TabView(selection: $selection) {
            iPadTodayView()
                .tag(iOSRootTab.today)
                .tabItem { Label(iOSRootTab.today.title, systemImage: iOSRootTab.today.systemImage) }

            iPadInboxView()
                .tag(iOSRootTab.inbox)
                .tabItem { Label(iOSRootTab.inbox.title, systemImage: iOSRootTab.inbox.systemImage) }

            NavigationStack {
                iOSCompactNotesView()
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tag(iOSRootTab.notes)
            .tabItem { Label(iOSRootTab.notes.title, systemImage: iOSRootTab.notes.systemImage) }

            NavigationStack {
                iOSSearchView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tag(iOSRootTab.search)
            .tabItem { Label(iOSRootTab.search.title, systemImage: iOSRootTab.search.systemImage) }

            NavigationStack(path: $morePath) {
                iOSMoreView()
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tag(iOSRootTab.more)
            .tabItem { Label(iOSRootTab.more.title, systemImage: iOSRootTab.more.systemImage) }
        }
            .background(Theme.bg.ignoresSafeArea())
            .tint(Theme.blue)
            .toolbarBackground(Theme.surface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
    }
}

private extension iOSRootView {
    func handleDeepLinkRoute() {
        guard let route = deepLinkManager.route?.deepLink else { return }
        switch route {
        case .today, .task:
            selection = .today
            compactTabSelection = .today
            compactMorePath = []
        case .habits:
            selection = .habits
            compactTabSelection = .more
            compactMorePath = [.habits]
        case .goals:
            selection = .goals
            compactTabSelection = .more
            compactMorePath = [.goals]
        case .calendar:
            selection = .calendar
            compactTabSelection = .more
            compactMorePath = [.calendar]
        }
    }
}
#endif
