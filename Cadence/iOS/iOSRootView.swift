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
                iOSCompactRootShell(selection: $compactTabSelection)
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
    case lists
    case search
    case more

    var title: String {
        switch self {
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .lists: return "Lists"
        case .search: return "Search"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .inbox: return "tray.fill"
        case .lists: return "folder.fill"
        case .search: return "magnifyingglass"
        case .more: return "ellipsis"
        }
    }
}

private struct iOSCompactRootShell: View {
    @Binding var selection: iOSRootTab

    var body: some View {
        activeTab
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
            iOSCompactTabBar(selection: $selection)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(
                        colors: [Theme.bg.opacity(0.12), Theme.bg.opacity(0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
            }
            .background(Theme.bg.ignoresSafeArea())
            .tint(Theme.blue)
    }

    @ViewBuilder
    private var activeTab: some View {
        switch selection {
        case .today:
            NavigationStack {
                iPadTodayView()
                    .toolbar(.hidden, for: .navigationBar)
            }
        case .inbox:
            NavigationStack {
                iPadInboxView()
                    .toolbar(.hidden, for: .navigationBar)
            }
        case .lists:
            NavigationStack {
                iOSListsView()
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .search:
            NavigationStack {
                iOSSearchView()
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .more:
            NavigationStack {
                iOSMoreView()
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}

private struct iOSCompactTabBar: View {
    @Binding var selection: iOSRootTab

    private let tabs: [iOSRootTab] = [.today, .inbox, .lists, .search, .more]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 8, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? Theme.blue : Theme.text.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.blue.opacity(0.13))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .background(Theme.surface.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 8)
    }
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
