#if os(macOS)
import SwiftUI
import SwiftData

enum TasksPanelMode {
    case todayOverview
    case byDoDate
}

// MARK: - Task group (context → list)

private struct TodayTaskGroup: Identifiable {
    let id: String
    let contextIcon: String?
    let contextColor: Color?
    let listIcon: String
    let listName: String
    let listColor: Color
    var tasks: [AppTask]
}

struct TodayDueSectionItem: Identifiable {
    let id: String
    let listIcon: String
    let listName: String
    let listColor: Color
    let sectionName: String
    let taskCount: Int
    let completedTaskCount: Int
}

// MARK: - Task Row Style

enum MacTaskRowStyle {
    case standard      // full 2-line row with list picker
    case todayGrouped  // no list picker, due date on line 1 right (existing showListBadge: false behavior)
    case list          // do-date pill left of title, due text right, no list picker
}

// MARK: - Tasks Panel

struct TasksPanel: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    let mode: TasksPanelMode
    let showsHeader: Bool

    init(mode: TasksPanelMode = .todayOverview, showsHeader: Bool = true) {
        self.mode = mode
        self.showsHeader = showsHeader
    }

    private var todayKey: String { DateFormatters.todayKey() }

    private var overdue: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && !$0.dueDate.isEmpty && $0.dueDate < todayKey }
    }
    private var dueTodayTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && $0.dueDate == todayKey }
    }
    private var doTodayTasks: [AppTask] {
        let excluded = Set(overdue.map(\.id)).union(dueTodayTasks.map(\.id))
        return allTasks.filter {
            !$0.isDone && !$0.isCancelled && $0.scheduledDate == todayKey && !excluded.contains($0.id)
        }
    }
    private var dueTodaySections: [TodayDueSectionItem] {
        let areaItems = areas.flatMap { area in
            area.sectionConfigs.compactMap { section -> TodayDueSectionItem? in
                guard !section.isArchived, !section.isCompleted, section.dueDate == todayKey else { return nil }
                let sectionTasks = (area.tasks ?? []).filter {
                    !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
                }
                return TodayDueSectionItem(
                    id: "area-\(area.id.uuidString)-\(section.id.uuidString)",
                    listIcon: area.icon,
                    listName: area.name,
                    listColor: Color(hex: area.colorHex),
                    sectionName: section.name,
                    taskCount: sectionTasks.filter { !$0.isDone }.count,
                    completedTaskCount: sectionTasks.filter(\.isDone).count
                )
            }
        }

        let projectItems = projects.flatMap { project in
            project.sectionConfigs.compactMap { section -> TodayDueSectionItem? in
                guard !section.isArchived, !section.isCompleted, section.dueDate == todayKey else { return nil }
                let sectionTasks = (project.tasks ?? []).filter {
                    !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
                }
                return TodayDueSectionItem(
                    id: "project-\(project.id.uuidString)-\(section.id.uuidString)",
                    listIcon: project.icon,
                    listName: project.name,
                    listColor: Color(hex: project.colorHex),
                    sectionName: section.name,
                    taskCount: sectionTasks.filter { !$0.isDone }.count,
                    completedTaskCount: sectionTasks.filter(\.isDone).count
                )
            }
        }

        return (areaItems + projectItems).sorted {
            if $0.listName != $1.listName {
                return $0.listName.localizedCaseInsensitiveCompare($1.listName) == .orderedAscending
            }
            return $0.sectionName.localizedCaseInsensitiveCompare($1.sectionName) == .orderedAscending
        }
    }
    private var byDoDateTodayTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && $0.scheduledDate == todayKey }
    }
    private var byDoDateUpcomingTasks: [AppTask] {
        let todayIDs = Set(byDoDateTodayTasks.map(\.id))
        return allTasks.filter {
            !$0.isDone && !$0.isCancelled && !taskIsUnscheduled($0) &&
            $0.scheduledDate != todayKey && !todayIDs.contains($0.id)
        }
    }
    private var byDoDateUnscheduledTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && taskIsUnscheduled($0) }
    }
    private var doneTasks: [AppTask] { allTasks.filter { $0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                TasksPanelHeader(mode: mode)
                Divider().background(Theme.borderSubtle)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if mode == .todayOverview {
                        if !dueTodaySections.isEmpty {
                            dueSectionsSection(items: dueTodaySections)
                        }
                        if !overdue.isEmpty {
                            flatSection(label: "Overdue", tasks: overdue, labelColor: Theme.red)
                        }
                        if !dueTodayTasks.isEmpty {
                            flatSection(label: "Due Today", tasks: dueTodayTasks, labelColor: Theme.blue)
                        }
                        // Do Today: grouped by context → list
                        let groups = groupedTasks(doTodayTasks)
                        if !groups.isEmpty {
                            ForEach(groups) { group in
                                groupSection(group: group)
                            }
                        }
                    } else {
                        if !byDoDateTodayTasks.isEmpty  { flatSection(label: "Do Today",    tasks: byDoDateTodayTasks,    labelColor: Theme.blue)  }
                        if !byDoDateUpcomingTasks.isEmpty { flatSection(label: "Scheduled",  tasks: byDoDateUpcomingTasks,  labelColor: Theme.dim)   }
                        if !byDoDateUnscheduledTasks.isEmpty { flatSection(label: "Unscheduled", tasks: byDoDateUnscheduledTasks, labelColor: Theme.amber) }
                    }
                    if !doneTasks.isEmpty { flatSection(label: "Done", tasks: doneTasks, labelColor: Theme.green) }
                    if isEmptyState {
                        EmptyStateView(
                            message: mode == .byDoDate ? "No tasks yet" : "Nothing for today",
                            subtitle: mode == .byDoDate ? "Add a task above to get started" : "Due-today and do-today tasks will appear here",
                            icon: "checkmark.circle"
                        )
                        .padding(.top, 40)
                    }
                }
                .padding(.top, showsHeader && mode == .todayOverview ? 12 : 0)
                .padding(.bottom, 16)
            }
        }
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
        )
        .background(Theme.surface)
    }

    // MARK: - Grouping

    private func groupedTasks(_ tasks: [AppTask]) -> [TodayTaskGroup] {
        var groups: [String: TodayTaskGroup] = [:]
        var order: [String] = []

        for task in tasks {
            let key: String
            if let area = task.area {
                key = "a_\(area.id)"
                if groups[key] == nil {
                    groups[key] = TodayTaskGroup(
                        id: key,
                        contextIcon: area.context?.icon,
                        contextColor: area.context.map { Color(hex: $0.colorHex) },
                        listIcon: area.icon,
                        listName: area.name,
                        listColor: Color(hex: area.colorHex),
                        tasks: []
                    )
                    order.append(key)
                }
            } else if let project = task.project {
                key = "p_\(project.id)"
                if groups[key] == nil {
                    groups[key] = TodayTaskGroup(
                        id: key,
                        contextIcon: project.context?.icon,
                        contextColor: project.context.map { Color(hex: $0.colorHex) },
                        listIcon: project.icon,
                        listName: project.name,
                        listColor: Color(hex: project.colorHex),
                        tasks: []
                    )
                    order.append(key)
                }
            } else {
                key = "inbox"
                if groups[key] == nil {
                    groups[key] = TodayTaskGroup(
                        id: "inbox",
                        contextIcon: nil, contextColor: nil,
                        listIcon: "tray.fill",
                        listName: "Inbox",
                        listColor: Theme.dim,
                        tasks: []
                    )
                    order.append(key)
                }
            }
            groups[key]!.tasks.append(task)
        }
        return order.compactMap { groups[$0] }
    }

    // MARK: - Section builders

    @ViewBuilder
    private func groupSection(group: TodayTaskGroup) -> some View {
        // Group header: context badge + list name
        HStack(spacing: 10) {
            if let ctxIcon = group.contextIcon, let ctxColor = group.contextColor {
                Image(systemName: ctxIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ctxColor)
                    .frame(width: 22, height: 22)
                    .background(ctxColor.opacity(0.15))
                    .clipShape(Circle())
            }
            Image(systemName: group.listIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(group.listColor)
            Text(group.listName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 6)

        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(height: 0.5)
            .padding(.horizontal, 16)

        ForEach(group.tasks) { task in
            MacTaskRow(task: task, style: .todayGrouped)
                .draggable(task.id.uuidString)
        }
    }

    @ViewBuilder
    private func flatSection(label: String, tasks: [AppTask], labelColor: Color) -> some View {
        Section {
            ForEach(tasks) { task in
                MacTaskRow(task: task, style: .standard)
                    .draggable(task.id.uuidString)
            }
        } header: {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(labelColor)
                .kerning(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
        }
    }

    private var isEmptyState: Bool {
        switch mode {
        case .todayOverview:
            return dueTodaySections.isEmpty && overdue.isEmpty && dueTodayTasks.isEmpty && doTodayTasks.isEmpty && doneTasks.isEmpty
        case .byDoDate:
            return byDoDateTodayTasks.isEmpty && byDoDateUpcomingTasks.isEmpty && byDoDateUnscheduledTasks.isEmpty && doneTasks.isEmpty
        }
    }

    private func taskIsUnscheduled(_ task: AppTask) -> Bool {
        task.scheduledDate.isEmpty || task.scheduledStartMin < 0
    }

    @ViewBuilder
    private func dueSectionsSection(items: [TodayDueSectionItem]) -> some View {
        Section {
            ForEach(items) { item in
                TodayDueSectionCard(item: item)
            }
        } header: {
            Text("SECTIONS DUE TODAY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .kerning(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
        }
    }
}

#endif
