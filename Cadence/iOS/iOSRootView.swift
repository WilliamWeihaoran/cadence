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
                        iOSSettingsView()
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(iOSRootTab.settings)
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

private struct iPadMacStyleRootShell<Content: View>: View {
    @Binding var selection: iOSSidebarItem?
    @ViewBuilder let detail: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            iOSSidebar(selection: $selection)
                .frame(width: 240)
                .background(
                    LinearGradient(
                        colors: [Theme.surface.opacity(0.98), Theme.surfaceElevated.opacity(0.98)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Theme.borderSubtle.opacity(0.85))
                        .frame(width: 1)
                }

            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
        }
        .background(Theme.bg.ignoresSafeArea())
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
    }
}

private struct iOSSidebar: View {
    @Binding var selection: iOSSidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasks: [AppTask]

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var activeContexts: [Context] {
        contexts.filter { !$0.isArchived }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var unscopedAreas: [Area] {
        activeAreas.filter { $0.context == nil }
    }

    private var unscopedProjects: [Project] {
        activeProjects.filter { $0.context == nil && $0.area == nil }
    }

    private var hasOrganizeContent: Bool {
        !activeContexts.isEmpty || !unscopedAreas.isEmpty || !unscopedProjects.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    iOSSidebarBrand()

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                        ForEach(iOSStaticSidebarDestination.allCases) { destination in
                            iOSSidebarCardButton(
                                title: destination.title,
                                systemImage: destination.systemImage,
                                tint: destination.tint,
                                count: count(for: destination),
                                isSelected: selection == destination.item
                            ) {
                                selection = destination.item
                            }
                        }
                    }

                    if hasOrganizeContent {
                        iOSSidebarSection(title: "ORGANIZE") {
                            ForEach(activeContexts) { context in
                                iOSSidebarContextGroup(
                                    context: context,
                                    selection: $selection
                                )
                            }

                            if !unscopedAreas.isEmpty || !unscopedProjects.isEmpty {
                                iOSSidebarLooseListsGroup(
                                    areas: unscopedAreas,
                                    projects: unscopedProjects,
                                    selection: $selection
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            HStack {
                iOSSidebarFooterButton(
                    systemImage: "gearshape.fill",
                    isSelected: selection == .settings
                ) { selection = .settings }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .background(Theme.surface)
    }

    private var todayCount: Int? {
        let count = allTasks.filter { task in
            guard !task.isDone && !task.isCancelled else { return false }
            return task.scheduledDate == todayKey || task.dueDate == todayKey
        }.count
        return count > 0 ? count : nil
    }

    private var inboxCount: Int? {
        let count = allTasks.filter { !$0.isDone && !$0.isCancelled && $0.area == nil && $0.project == nil }.count
        return count > 0 ? count : nil
    }

    private var allTaskCount: Int? {
        let count = allTasks.filter { !$0.isDone && !$0.isCancelled }.count
        return count > 0 ? count : nil
    }

    private func count(for destination: iOSStaticSidebarDestination) -> Int? {
        switch destination {
        case .today: return todayCount
        case .allTasks: return allTaskCount
        case .focus: return nil
        case .inbox: return inboxCount
        case .calendar: return nil
        case .pursuits: return nil
        case .goals: return nil
        case .habits: return nil
        }
    }
}

private enum iOSStaticSidebarDestination: CaseIterable, Identifiable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case pursuits
    case goals
    case habits

    var id: String { title }

    var item: iOSSidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .pursuits: return .pursuits
        case .goals: return .goals
        case .habits: return .habits
        }
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .focus: return "Focus"
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .pursuits: return "Pursuits"
        case .goals: return "Milestones"
        case .habits: return "Habits"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .allTasks: return "checklist"
        case .focus: return "timer"
        case .inbox: return "tray.fill"
        case .calendar: return "calendar"
        case .pursuits: return "sparkles"
        case .goals: return "flag.fill"
        case .habits: return "flame.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today: return Color(hex: "#FFB84D")
        case .allTasks: return Color(hex: "#5AA2FF")
        case .focus: return Color(hex: "#FF6B6B")
        case .inbox: return Color(hex: "#5AA2FF")
        case .calendar: return Color(hex: "#9E8CFF")
        case .pursuits: return Color(hex: "#A78BFA")
        case .goals: return Color(hex: "#4ECB71")
        case .habits: return Color(hex: "#FFB84D")
        }
    }
}

private struct iOSSidebarBrand: View {
    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.surfaceElevated)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cadence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Workspace")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.bottom, 2)
    }
}

private struct iOSSidebarCardButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : tint)

                    Spacer()

                    if let count, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isSelected ? .white : tint)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 9)

                Spacer(minLength: 5)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint : tint.opacity(0.11))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.5) : tint.opacity(0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct iOSSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.65))
                    .frame(height: 1)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

private struct iOSSidebarContextGroup: View {
    @Bindable var context: Context
    @Binding var selection: iOSSidebarItem?

    private var listEntries: [iOSSidebarListEntry] {
        let areaEntries = (context.areas ?? []).filter(\.isActive).map(iOSSidebarListEntry.area)
        let projectEntries = (context.projects ?? []).filter(\.isActive).map(iOSSidebarListEntry.project)
        let entries = areaEntries + projectEntries
        let hasGlobalOrder = Set(entries.map(\.order)).count == entries.count
        guard hasGlobalOrder else { return areaEntries + projectEntries }
        return entries.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: context.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: context.colorHex))

                Text(context.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)

            if !listEntries.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color(hex: context.colorHex).opacity(0.22))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(listEntries) { entry in
                            iOSSidebarListButton(entry: entry, selection: $selection)
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
    }
}

private struct iOSSidebarLooseListsGroup: View {
    let areas: [Area]
    let projects: [Project]
    @Binding var selection: iOSSidebarItem?

    private var listEntries: [iOSSidebarListEntry] {
        let entries = areas.map(iOSSidebarListEntry.area) + projects.map(iOSSidebarListEntry.project)
        return entries.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LISTS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(listEntries) { entry in
                    iOSSidebarListButton(entry: entry, selection: $selection)
                }
            }
            .padding(.leading, 8)
        }
    }
}

private enum iOSSidebarListEntry: Identifiable {
    case area(Area)
    case project(Project)

    var id: String {
        switch self {
        case .area(let area): return "area-\(area.id.uuidString)"
        case .project(let project): return "project-\(project.id.uuidString)"
        }
    }

    var item: iOSSidebarItem {
        switch self {
        case .area(let area): return .area(area.id)
        case .project(let project): return .project(project.id)
        }
    }

    var icon: String {
        switch self {
        case .area(let area): return area.icon
        case .project(let project): return project.icon
        }
    }

    var label: String {
        switch self {
        case .area(let area): return area.name.isEmpty ? "Untitled Area" : area.name
        case .project(let project): return project.name.isEmpty ? "Untitled Project" : project.name
        }
    }

    var color: Color {
        switch self {
        case .area(let area): return Color(hex: area.colorHex)
        case .project(let project): return Color(hex: project.colorHex)
        }
    }

    var dueDateKey: String? {
        switch self {
        case .area: return nil
        case .project(let project): return project.dueDate.isEmpty ? nil : project.dueDate
        }
    }

    var order: Int {
        switch self {
        case .area(let area): return area.order
        case .project(let project): return project.order
        }
    }

    var kindRank: Int {
        switch self {
        case .area: return 0
        case .project: return 1
        }
    }
}

private struct iOSSidebarListButton: View {
    let entry: iOSSidebarListEntry
    @Binding var selection: iOSSidebarItem?

    private var isSelected: Bool {
        selection == entry.item
    }

    var body: some View {
        Button {
            selection = entry.item
        } label: {
            HStack(spacing: 8) {
                Label {
                    Text(entry.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: entry.icon)
                        .foregroundStyle(entry.color)
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer(minLength: 8)

                if let dueDateKey = entry.dueDateKey {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.red)
                        Text(DateFormatters.relativeDate(from: dueDateKey))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(dueDateKey < DateFormatters.todayKey() ? Theme.red : Theme.dim)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceElevated.opacity(0.7))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.blue.opacity(0.16) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Theme.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct iOSSidebarFooterButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Theme.blue.opacity(0.22) : Theme.surfaceElevated.opacity(0.45))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Theme.blue.opacity(0.34) : Theme.borderSubtle.opacity(0.4), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct iOSMissingListView: View {
    var body: some View {
        iOSEmptyPanel(
            systemImage: "questionmark.folder",
            title: "List not found",
            subtitle: "This list may have been archived, deleted, or changed on another device."
        )
        .background(Theme.bg.ignoresSafeArea())
    }
}

private struct iOSAllTasksView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @AppStorage("ios.allTasks.sortMode") private var sortModeRaw = iOSTaskSortMode.listOrder.rawValue
    @AppStorage("ios.allTasks.showCompleted") private var showCompleted = false

    private var sortMode: iOSTaskSortMode {
        get { iOSTaskSortMode(rawValue: sortModeRaw) ?? .listOrder }
        set { sortModeRaw = newValue.rawValue }
    }

    private var activeTasks: [AppTask] {
        CadenceTaskQuerySupport.activeTasks(
            from: allTasks,
            sortMode: sortMode.cadenceSortMode
        )
    }

    private var completedTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTasks(from: allTasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "Tasks", title: "All Tasks", count: activeTasks.count)

            Divider().background(Theme.borderSubtle)

            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedTasks.count
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if activeTasks.isEmpty && (!showCompleted || completedTasks.isEmpty) {
                iOSEmptyPanel(
                    systemImage: "checklist",
                    title: "No active tasks",
                    subtitle: "Tasks you create on iPad or Mac will collect here."
                )
            } else {
                List {
                    if !activeTasks.isEmpty {
                        Section {
                            ForEach(activeTasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Active", color: Theme.blue)
                        }
                    }

                    if showCompleted && !completedTasks.isEmpty {
                        Section {
                            ForEach(completedTasks.prefix(24)) { task in
                                iOSTaskListRow(task: task, opacity: 0.62)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Completed", color: Theme.green)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

}

private struct iOSFocusView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var selectedTaskID: UUID?
    @State private var timerState = CadenceFocusTimerState()

    private var todayKey: String { DateFormatters.todayKey() }

    private var readyTasks: [AppTask] {
        CadenceFocusSupport.readyTasks(from: allTasks, todayKey: todayKey)
    }

    private var selectedTask: AppTask? {
        if let selectedTaskID {
            return readyTasks.first { $0.id == selectedTaskID } ?? allTasks.first { $0.id == selectedTaskID }
        }
        return readyTasks.first
    }

    private var elapsedSeconds: Int {
        timerState.elapsedSeconds()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                iOSPanelHeader(eyebrow: "Focus", title: "Focus", count: readyTasks.count)
                Divider().background(Theme.borderSubtle)

                if readyTasks.isEmpty {
                    iOSEmptyPanel(
                        systemImage: "timer",
                        title: "No focus tasks",
                        subtitle: "Schedule a task for today to focus it here."
                    )
                } else {
                    List(readyTasks) { task in
                        Button {
                            selectedTaskID = task.id
                            resetTimer()
                        } label: {
                            iOSFeatureTaskSummaryRow(
                                title: task.title.isEmpty ? "Untitled Task" : task.title,
                                subtitle: CadenceFocusSupport.sidebarDetail(for: task, todayKey: todayKey),
                                detail: task.estimatedMinutes > 0 ? "\(task.estimatedMinutes)m" : task.priority.label,
                                icon: task.priority == .high ? "exclamationmark.circle.fill" : "circle",
                                color: Theme.priorityColor(task.priority),
                                isSelected: selectedTask?.id == task.id
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 300, idealWidth: 360)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 22) {
                if let task = selectedTask {
                    VStack(spacing: 6) {
                        Text(task.title.isEmpty ? "Untitled Task" : task.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                        Text(task.containerName.isEmpty ? task.priority.label : task.containerName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }

                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(CadenceFocusSupport.clockDisplay(elapsedSeconds: elapsedSeconds))
                            .font(.system(size: 62, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }

                    HStack(spacing: 12) {
                        Button {
                            toggleTimer()
                        } label: {
                            Label(timerState.isRunning ? "Pause" : "Start", systemImage: timerState.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(timerState.isRunning ? Theme.amber : Theme.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            resetTimer()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .frame(width: 40, height: 38)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            complete(task)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.green)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Theme.green.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(task.notes)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: 520, alignment: .leading)
                            .padding(14)
                            .background(Theme.surfaceElevated.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                } else {
                    iOSEmptyPanel(
                        systemImage: "timer",
                        title: "Ready when you are",
                        subtitle: "Today tasks will appear here."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(Theme.bg)
        }
        .onAppear {
            selectedTaskID = selectedTaskID ?? readyTasks.first?.id
        }
    }

    private func toggleTimer() {
        timerState.toggle()
    }

    private func resetTimer() {
        timerState.reset()
    }

    private func complete(_ task: AppTask) {
        CadenceFocusSupport.complete(task, elapsedSeconds: elapsedSeconds, modelContext: modelContext)
        resetTimer()
        selectedTaskID = readyTasks.first { $0.id != task.id }?.id
    }
}

private struct iOSCalendarView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var monthDate = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current

    private var selectedKey: String {
        DateFormatters.dateKey(from: selectedDate)
    }

    private var selectedTasks: [AppTask] {
        CadenceScheduleSupport.tasks(on: selectedKey, from: allTasks)
    }

    private var selectedBundles: [TaskBundle] {
        CadenceScheduleSupport.bundles(on: selectedKey, from: allBundles)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    iOSPanelHeader(eyebrow: "Calendar", title: monthTitle)
                    Spacer()
                    iOSFeatureIconButton(systemImage: "chevron.left") { changeMonth(by: -1) }
                    iOSFeatureIconButton(systemImage: "location.fill") {
                        selectedDate = calendar.startOfDay(for: Date())
                        monthDate = selectedDate
                    }
                    iOSFeatureIconButton(systemImage: "chevron.right") { changeMonth(by: 1) }
                }
                .padding(.trailing, 12)
                .frame(height: iOSPanelHeaderHeight, alignment: .top)

                Divider().background(Theme.borderSubtle)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(monthDays, id: \.self) { date in
                        iOSCalendarDayCell(
                            date: date,
                            isCurrentMonth: calendar.isDate(date, equalTo: monthDate, toGranularity: .month),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            taskCount: itemCount(on: date)
                        ) {
                            selectedDate = date
                            if !calendar.isDate(date, equalTo: monthDate, toGranularity: .month) {
                                monthDate = date
                            }
                        }
                    }
                }
                .padding(16)

                Spacer(minLength: 0)
            }
            .frame(minWidth: 420, idealWidth: 520)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 0) {
                iOSPanelHeader(
                    eyebrow: DateFormatters.longDate.string(from: selectedDate),
                    title: "Schedule",
                    count: selectedTasks.count + selectedBundles.count
                )
                Divider().background(Theme.borderSubtle)

                if selectedTasks.isEmpty && selectedBundles.isEmpty {
                    iOSEmptyPanel(
                        systemImage: "calendar",
                        title: "Nothing scheduled",
                        subtitle: "Tasks with due or do dates will show here."
                    )
                } else {
                    List {
                        if !selectedBundles.isEmpty {
                            Section("Blocks") {
                                ForEach(selectedBundles) { bundle in
                                    iOSFeatureSummaryRow(
                                        title: bundle.displayTitle,
                                        subtitle: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                                        icon: "tray.full.fill",
                                        color: Theme.purple
                                    )
                                }
                            }
                        }

                        if !selectedTasks.isEmpty {
                            Section("Tasks") {
                                ForEach(selectedTasks) { task in
                                    iOSTaskListRow(task: task)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.bg)
                }
            }
            .background(Theme.bg)
        }
    }

    private var monthTitle: String {
        DateFormatters.monthYear.string(from: monthDate)
    }

    private var weekdaySymbols: [String] {
        calendar.shortWeekdaySymbols
    }

    private var monthDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate),
              let gridStart = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)?.start,
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let gridEnd = calendar.dateInterval(of: .weekOfMonth, for: lastDay)?.end
        else { return [] }

        var result: [Date] = []
        var cursor = gridStart
        while cursor < gridEnd {
            result.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd
        }
        return result
    }

    private func itemCount(on date: Date) -> Int {
        let key = DateFormatters.dateKey(from: date)
        return CadenceScheduleSupport.itemCount(on: key, tasks: allTasks, bundles: allBundles)
    }

    private func changeMonth(by value: Int) {
        monthDate = calendar.date(byAdding: .month, value: value, to: monthDate) ?? monthDate
    }
}

private struct iOSPursuitsView: View {
    @Query(sort: \Pursuit.order) private var pursuits: [Pursuit]
    @State private var selectedID: UUID?

    private var activePursuits: [Pursuit] {
        pursuits.filter { $0.status != .done }
    }

    private var selected: Pursuit? {
        if let selectedID {
            return pursuits.first { $0.id == selectedID }
        }
        return activePursuits.first ?? pursuits.first
    }

    var body: some View {
        HStack(spacing: 0) {
            iOSFeatureListPane(
                eyebrow: "Pursuits",
                title: "Pursuits",
                count: activePursuits.count,
                emptyTitle: "No pursuits yet",
                emptySubtitle: "Pursuits from Mac will appear here.",
                emptyIcon: "sparkles"
            ) {
                ForEach(activePursuits) { pursuit in
                    Button {
                        selectedID = pursuit.id
                    } label: {
                        iOSFeatureSummaryRow(
                            title: pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title,
                            subtitle: pursuit.context?.name ?? pursuit.kind.label,
                            detail: pursuitSummaryLabel(for: pursuit),
                            icon: pursuit.icon,
                            color: Color(hex: pursuit.colorHex),
                            isSelected: selected?.id == pursuit.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Theme.borderSubtle)

            if let pursuit = selected {
                let summary = CadencePursuitSupport.summary(for: pursuit)
                iOSPursuitDetail(pursuit: pursuit, goals: summary.goals, habits: summary.habits)
            } else {
                iOSFeatureEmptyDetail(systemImage: "sparkles", title: "No pursuit selected")
            }
        }
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
    }

    private func pursuitSummaryLabel(for pursuit: Pursuit) -> String {
        let summary = CadencePursuitSupport.summary(for: pursuit)
        return "\(summary.activeGoalCount) milestones / \(summary.activeHabitCount) habits"
    }
}

private struct iOSMilestonesView: View {
    @Query(sort: \Goal.order) private var goals: [Goal]
    @State private var selectedID: UUID?

    private var activeGoals: [Goal] {
        goals.filter { $0.status != .done }
    }

    private var selected: Goal? {
        if let selectedID {
            return goals.first { $0.id == selectedID }
        }
        return activeGoals.first ?? goals.first
    }

    var body: some View {
        HStack(spacing: 0) {
            iOSFeatureListPane(
                eyebrow: "Milestones",
                title: "Milestones",
                count: activeGoals.count,
                emptyTitle: "No milestones yet",
                emptySubtitle: "Milestones created on Mac will show here.",
                emptyIcon: "flag.fill"
            ) {
                ForEach(activeGoals) { goal in
                    Button {
                        selectedID = goal.id
                    } label: {
                        let summary = GoalContributionResolver.summary(for: goal)
                        iOSFeatureSummaryRow(
                            title: goal.title.isEmpty ? "Untitled Milestone" : goal.title,
                            subtitle: goal.pursuit?.title ?? goal.context?.name ?? goal.status.rawValue.capitalized,
                            detail: "\(Int((summary.progress * 100).rounded()))%",
                            icon: "flag.fill",
                            color: Color(hex: goal.colorHex),
                            isSelected: selected?.id == goal.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Theme.borderSubtle)

            if let goal = selected {
                iOSMilestoneDetail(goal: goal)
            } else {
                iOSFeatureEmptyDetail(systemImage: "flag.fill", title: "No milestone selected")
            }
        }
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
    }
}

private struct iOSHabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var selectedID: UUID?

    private var todayKey: String { DateFormatters.todayKey() }

    private var selected: Habit? {
        if let selectedID {
            return habits.first { $0.id == selectedID }
        }
        return dueToday.first ?? habits.first
    }

    private var dueToday: [Habit] {
        habits.filter(\.isDueToday)
    }

    var body: some View {
        HStack(spacing: 0) {
            iOSFeatureListPane(
                eyebrow: "Habits",
                title: "Habits",
                count: habits.count,
                emptyTitle: "No habits yet",
                emptySubtitle: "Habits created on Mac will show here.",
                emptyIcon: "flame.fill"
            ) {
                ForEach(habits) { habit in
                    Button {
                        selectedID = habit.id
                    } label: {
                        iOSHabitSummaryRow(
                            habit: habit,
                            todayKey: todayKey,
                            isSelected: selected?.id == habit.id,
                            toggle: { toggle(habit) }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Theme.borderSubtle)

            if let habit = selected {
                iOSHabitDetail(habit: habit, todayKey: todayKey, toggle: { toggle(habit) })
            } else {
                iOSFeatureEmptyDetail(systemImage: "flame.fill", title: "No habit selected")
            }
        }
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
    }

    private func toggle(_ habit: Habit) {
        CadenceHabitSupport.toggle(habit, on: todayKey, modelContext: modelContext)
    }
}

private struct iOSFeatureListPane<Content: View>: View {
    let eyebrow: String
    let title: String
    let count: Int
    let emptyTitle: String
    let emptySubtitle: String
    let emptyIcon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: eyebrow, title: title, count: count)
            Divider().background(Theme.borderSubtle)

            if count == 0 {
                iOSEmptyPanel(systemImage: emptyIcon, title: emptyTitle, subtitle: emptySubtitle)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        content()
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(minWidth: 300, idealWidth: 360)
        .background(Theme.surface)
    }
}

private struct iOSFeatureSummaryRow: View {
    let title: String
    let subtitle: String
    var detail: String? = nil
    let icon: String
    let color: Color
    var isSelected = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle.isEmpty ? "No context" : subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? color.opacity(0.15) : Theme.surfaceElevated.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? color.opacity(0.32) : Theme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct iOSFeatureTaskSummaryRow: View {
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let color: Color
    let isSelected: Bool

    var body: some View {
        iOSFeatureSummaryRow(
            title: title,
            subtitle: subtitle,
            detail: detail,
            icon: icon,
            color: color,
            isSelected: isSelected
        )
    }
}

private struct iOSFeatureIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceElevated.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.6), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct iOSCalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let taskCount: Int
    let action: () -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 15, weight: isSelected || isToday ? .bold : .semibold))
                    .foregroundStyle(isCurrentMonth ? Theme.text : Theme.dim.opacity(0.42))

                HStack(spacing: 3) {
                    ForEach(0..<min(taskCount, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? .white : Theme.blue)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(isSelected ? Theme.blue : isToday ? Theme.blue.opacity(0.12) : Theme.surfaceElevated.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isToday || isSelected ? Theme.blue.opacity(0.5) : Theme.borderSubtle.opacity(0.28), lineWidth: 1)
            }
            .opacity(isCurrentMonth ? 1 : 0.58)
        }
        .buttonStyle(.plain)
    }
}

private struct iOSPursuitDetail: View {
    let pursuit: Pursuit
    let goals: [Goal]
    let habits: [Habit]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iOSFeatureHero(
                    eyebrow: pursuit.kind.label,
                    title: pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title,
                    subtitle: pursuit.desc.isEmpty ? pursuit.context?.name ?? "Pursuit" : pursuit.desc,
                    icon: pursuit.icon,
                    color: Color(hex: pursuit.colorHex)
                )

                HStack(spacing: 10) {
                    iOSMetricTile(title: "Milestones", value: "\(goals.count)", icon: "flag.fill", color: Theme.green)
                    iOSMetricTile(title: "Habits", value: "\(habits.count)", icon: "flame.fill", color: Theme.amber)
                    iOSMetricTile(title: "Status", value: pursuit.status.label, icon: "circle.fill", color: Color(hex: pursuit.colorHex))
                }

                iOSFeatureSection(title: "Milestones") {
                    ForEach(goals) { goal in
                        let summary = GoalContributionResolver.summary(for: goal)
                        iOSFeatureSummaryRow(
                            title: goal.title.isEmpty ? "Untitled Milestone" : goal.title,
                            subtitle: summary.nextActionTitle ?? goal.status.rawValue.capitalized,
                            detail: summary.percentLabel,
                            icon: "flag.fill",
                            color: Color(hex: goal.colorHex)
                        )
                    }
                }

                iOSFeatureSection(title: "Habits") {
                    ForEach(habits) { habit in
                        iOSFeatureSummaryRow(
                            title: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                            subtitle: habit.frequencySummary,
                            detail: "\(habit.currentStreak)d",
                            icon: habit.icon,
                            color: Color(hex: habit.colorHex)
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }
}

private struct iOSMilestoneDetail: View {
    let goal: Goal

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iOSFeatureHero(
                    eyebrow: goal.status.rawValue.capitalized,
                    title: goal.title.isEmpty ? "Untitled Milestone" : goal.title,
                    subtitle: goal.desc.isEmpty ? goal.pursuit?.title ?? goal.context?.name ?? "Milestone" : goal.desc,
                    icon: "flag.fill",
                    color: Color(hex: goal.colorHex)
                )

                ProgressView(value: summary.progress)
                    .tint(Color(hex: goal.colorHex))

                HStack(spacing: 10) {
                    iOSMetricTile(title: "Progress", value: summary.percentLabel, icon: "chart.line.uptrend.xyaxis", color: Color(hex: goal.colorHex))
                    iOSMetricTile(title: "Tasks", value: summary.taskCountLabel, icon: "checklist", color: Theme.blue)
                    iOSMetricTile(title: "Focus", value: summary.focusLabel, icon: "timer", color: Theme.amber)
                }

                if let nextActionTitle = summary.nextActionTitle {
                    iOSFeatureSection(title: "Next Action") {
                        iOSFeatureSummaryRow(
                            title: nextActionTitle,
                            subtitle: "Highest priority open task",
                            icon: "arrow.right.circle.fill",
                            color: Theme.blue
                        )
                    }
                }

                iOSFeatureSection(title: "Linked Work") {
                    iOSFeatureSummaryRow(
                        title: "\(summary.linkedListCount) linked lists",
                        subtitle: "\(summary.overdueTaskCount) overdue, \(summary.recentCompletedCount) recent completions",
                        icon: "folder.fill",
                        color: Theme.green
                    )
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }
}

private struct iOSHabitSummaryRow: View {
    let habit: Habit
    let todayKey: String
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: habit.isDone(on: todayKey) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(habit.isDone(on: todayKey) ? Theme.green : Theme.dim)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title.isEmpty ? "Untitled Habit" : habit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(habit.pursuit?.title ?? habit.frequencySummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(habit.currentStreak)d")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: habit.colorHex))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? Color(hex: habit.colorHex).opacity(0.15) : Theme.surfaceElevated.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color(hex: habit.colorHex).opacity(0.32) : Theme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct iOSHabitDetail: View {
    let habit: Habit
    let todayKey: String
    let toggle: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iOSFeatureHero(
                    eyebrow: habit.frequencyShortLabel,
                    title: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                    subtitle: habit.pursuit?.title ?? habit.goal?.title ?? habit.context?.name ?? habit.frequencySummary,
                    icon: habit.icon,
                    color: Color(hex: habit.colorHex)
                )

                Button(action: toggle) {
                    Label(habit.isDone(on: todayKey) ? "Done Today" : "Mark Done Today",
                          systemImage: habit.isDone(on: todayKey) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(habit.isDone(on: todayKey) ? Theme.green : Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(habit.isDone(on: todayKey) ? Theme.green.opacity(0.13) : Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    iOSMetricTile(title: "Current", value: "\(habit.currentStreak)d", icon: "flame.fill", color: Theme.amber)
                    iOSMetricTile(title: "Best", value: "\(habit.bestStreak)d", icon: "trophy.fill", color: Theme.green)
                    iOSMetricTile(title: "30 days", value: "\(habit.last30DayCompletionRate)%", icon: "chart.bar.fill", color: Theme.blue)
                }

                iOSFeatureSection(title: "Recent") {
                    ForEach(habit.last7DayStates.indices, id: \.self) { index in
                        let done = habit.last7DayStates[index]
                        iOSFeatureSummaryRow(
                            title: recentDayLabel(offset: 6 - index),
                            subtitle: done ? "Completed" : "Open",
                            icon: done ? "checkmark.circle.fill" : "circle",
                            color: done ? Theme.green : Theme.dim
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }

    private func recentDayLabel(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        return DateFormatters.dayOfWeek.string(from: date)
    }
}

private struct iOSFeatureHero: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct iOSMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct iOSFeatureSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)
            VStack(spacing: 8) {
                content()
            }
        }
    }
}

private struct iOSFeatureEmptyDetail: View {
    let systemImage: String
    let title: String

    var body: some View {
        iOSEmptyPanel(
            systemImage: systemImage,
            title: title,
            subtitle: "Select an item from the list."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

private struct iOSMacPlaceholderPanel: View {
    let eyebrow: String
    let title: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: eyebrow, title: title)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.72))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

private enum iOSRootTab: Hashable {
    case today
    case inbox
    case lists
    case search
    case settings
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
