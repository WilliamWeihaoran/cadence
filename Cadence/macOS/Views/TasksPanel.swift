#if os(macOS)
import SwiftUI
import SwiftData

enum TasksPanelMode {
    case todayOverview
    case byDoDate
}

enum TaskFilterDoDate: String, CaseIterable, Identifiable {
    case any = "Any Do Date"
    case today = "Do Today"
    case overdue = "Overdue"
    case scheduled = "Scheduled"
    case unscheduled = "Unscheduled"
    var id: String { rawValue }
}

enum TaskSortField: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case date = "Date"
    case priority = "Priority"
    var id: String { rawValue }
}

enum TaskSortDirection: String, CaseIterable, Identifiable {
    case ascending = "Ascending"
    case descending = "Descending"
    var id: String { rawValue }
}

enum TaskGroupingMode: String, CaseIterable, Identifiable {
    case none = "None"
    case byDate = "By Date"
    case byList = "By List"
    case byPriority = "By Priority"
    var id: String { rawValue }
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

// MARK: - Task Row Style

enum MacTaskRowStyle {
    case standard      // full 2-line row with list picker
    case todayGrouped  // no list picker, due date on line 1 right (existing showListBadge: false behavior)
    case list          // do-date pill left of title, due text right, no list picker
}

// MARK: - Tasks Panel

struct TasksPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    let mode: TasksPanelMode
    let showsHeader: Bool
    let sortField: TaskSortField
    let sortDirection: TaskSortDirection
    let groupingMode: TaskGroupingMode
    let enableControls: Bool
    @AppStorage("todayRolloverNoticeDismissedDate") private var rolloverNoticeDismissedDate = ""
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var localSortField: TaskSortField = .date
    @State private var localSortDirection: TaskSortDirection = .ascending
    @State private var localGroupingMode: TaskGroupingMode = .byDate
    @State private var frozenTaskOrder: [UUID]? = nil
    @State private var dragOverTaskID: UUID? = nil

    init(
        mode: TasksPanelMode = .todayOverview,
        showsHeader: Bool = true,
        sortField: TaskSortField = .date,
        sortDirection: TaskSortDirection = .ascending,
        groupingMode: TaskGroupingMode = .byDate,
        enableControls: Bool = false
    ) {
        self.mode = mode
        self.showsHeader = showsHeader
        self.sortField = sortField
        self.sortDirection = sortDirection
        self.groupingMode = groupingMode
        self.enableControls = enableControls
        let prefix = mode == .todayOverview ? "today" : "allTasks"
        let ud = UserDefaults.standard
        _localSortField = State(initialValue: TaskSortField(rawValue: ud.string(forKey: "\(prefix)SortField") ?? "") ?? sortField)
        _localSortDirection = State(initialValue: TaskSortDirection(rawValue: ud.string(forKey: "\(prefix)SortDirection") ?? "") ?? sortDirection)
        let stored = TaskGroupingMode(rawValue: ud.string(forKey: "\(prefix)GroupingMode") ?? "")
        let fallback: TaskGroupingMode = mode == .todayOverview ? .byList : groupingMode
        // Today view does not support byDate grouping
        _localGroupingMode = State(initialValue: (stored == .byDate && mode == .todayOverview) ? fallback : (stored ?? fallback))
    }

    private var activeSortField: TaskSortField { enableControls ? localSortField : sortField }
    private var activeSortDirection: TaskSortDirection { enableControls ? localSortDirection : sortDirection }
    private var activeGroupingMode: TaskGroupingMode { enableControls ? localGroupingMode : groupingMode }
    private var udPrefix: String { mode == .todayOverview ? "today" : "allTasks" }

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
    private var overdoTasks: [AppTask] {
        let excluded = Set(overdue.map(\.id)).union(dueTodayTasks.map(\.id))
        return allTasks.filter {
            !$0.isDone &&
            !$0.isCancelled &&
            !$0.scheduledDate.isEmpty &&
            $0.scheduledDate < todayKey &&
            !excluded.contains($0.id)
        }
    }
    private var todayGroupedTaskItems: [AppTask] {
        var seen = Set<UUID>()
        let ordered = shouldShowRolloverNotice ? (overdue + dueTodayTasks + doTodayTasks) : (overdue + overdoTasks + dueTodayTasks + doTodayTasks)
        return ordered.filter { seen.insert($0.id).inserted }
    }
    private var todayEligibleTasks: [AppTask] {
        var seen = Set<UUID>()
        return (overdue + overdoTasks + dueTodayTasks + doTodayTasks).filter { seen.insert($0.id).inserted }
    }
    private var shouldShowRolloverNotice: Bool {
        mode == .todayOverview && !overdoTasks.isEmpty && rolloverNoticeDismissedDate != todayKey
    }
    private var byDoDateBaseTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled }
    }
    private var byDoDateBaseSortedTasks: [AppTask] {
        byDoDateBaseTasks.sorted { lhs, rhs in
            let result: Bool
            switch activeSortField {
            case .custom:
                result = lhs.order < rhs.order
            case .date:
                let leftDate = lhs.scheduledDate.isEmpty ? "9999-99-99" : lhs.scheduledDate
                let rightDate = rhs.scheduledDate.isEmpty ? "9999-99-99" : rhs.scheduledDate
                if leftDate != rightDate {
                    result = leftDate < rightDate
                } else {
                    result = lhs.order < rhs.order
                }
            case .priority:
                let lp = priorityRank(lhs.priority)
                let rp = priorityRank(rhs.priority)
                if lp != rp {
                    result = lp < rp
                } else {
                    result = lhs.order < rhs.order
                }
            }
            return activeSortDirection == .ascending ? result : !result
        }
    }
    private func applyFreeze(_ sorted: [AppTask]) -> [AppTask] {
        guard let frozen = frozenTaskOrder else { return sorted }
        let byID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
        return frozen.compactMap { byID[$0] } + sorted.filter { !frozen.contains($0.id) }
    }

    private var byDoDateSortedTasks: [AppTask] {
        applyFreeze(byDoDateBaseSortedTasks)
    }
    private var doneTasks: [AppTask] { allTasks.filter { $0.isDone }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
    private var sidebarListOrder: [String] {
        var order: [String] = ["inbox"]
        for context in contexts.sorted(by: { $0.order < $1.order }) {
            let sortedAreas = (context.areas ?? []).sorted { $0.order < $1.order }
            let sortedProjects = (context.projects ?? []).sorted { $0.order < $1.order }
            order.append(contentsOf: sortedAreas.map { "a_\($0.id.uuidString)" })
            order.append(contentsOf: sortedProjects.map { "p_\($0.id.uuidString)" })
        }
        return order
    }

    var body: some View {
        let sortedByDoDate: [AppTask] = mode == .byDoDate ? byDoDateSortedTasks : []
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                TasksPanelHeader(mode: mode)
                if enableControls {
                    controlsBar
                }
                Divider().background(Theme.borderSubtle)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if mode == .todayOverview {
                        if shouldShowRolloverNotice {
                            rolloverNoticeSection(tasks: overdoTasks)
                        }
                        let todayTasks = shouldShowRolloverNotice ? todayGroupedTaskItems : todayEligibleTasks
                        if enableControls {
                            switch activeGroupingMode {
                            case .none:
                                if !todayTasks.isEmpty {
                                    flatSection(label: "Today Tasks", tasks: todayTasks, labelColor: Theme.dim)
                                }
                            case .byDate:
                                if !overdue.isEmpty { flatSection(label: "Past Due", tasks: overdue, labelColor: Theme.red) }
                                if !overdoTasks.isEmpty { flatSection(label: "Past Do", tasks: overdoTasks, labelColor: Theme.amber) }
                                if !dueTodayTasks.isEmpty { flatSection(label: "Due Today", tasks: dueTodayTasks, labelColor: Theme.red.opacity(0.85)) }
                                if !doTodayTasks.isEmpty { flatSection(label: "Do Today", tasks: doTodayTasks, labelColor: Theme.blue) }
                            case .byList:
                                ForEach(groupedTasks(todayTasks)) { group in
                                    groupSection(group: group)
                                }
                            case .byPriority:
                                ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                                    let tasks = todayTasks.filter { $0.priority == priority }
                                    if !tasks.isEmpty {
                                        flatSection(label: priority.label, tasks: tasks, labelColor: Theme.priorityColor(priority), dropKey: "priority:\(priority.rawValue)")
                                    }
                                }
                            }
                        } else {
                            let groups = groupedTasks(todayGroupedTaskItems)
                            if !groups.isEmpty {
                                ForEach(groups) { group in
                                    groupSection(group: group)
                                }
                            }
                        }
                    } else {
                        let todayK = todayKey
                        switch activeGroupingMode {
                        case .none:
                            if !sortedByDoDate.isEmpty {
                                flatSection(label: "Tasks", tasks: sortedByDoDate, labelColor: Theme.dim)
                            }
                        case .byDate:
                            let todayTasks = sortedByDoDate.filter { $0.scheduledDate == todayK }
                            let upcomingTasks = sortedByDoDate.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayK }
                            let unscheduledTasks = sortedByDoDate.filter { taskIsUnscheduled($0) }
                            if !todayTasks.isEmpty  { flatSection(label: "Do Today",    tasks: todayTasks,    labelColor: Theme.blue, dropKey: "date:today")  }
                            if !upcomingTasks.isEmpty { flatSection(label: "Scheduled", tasks: upcomingTasks, labelColor: Theme.dim,  dropKey: "date:scheduled") }
                            if !unscheduledTasks.isEmpty { flatSection(label: "Unscheduled", tasks: unscheduledTasks, labelColor: Theme.amber, dropKey: "date:unscheduled") }
                        case .byList:
                            ForEach(groupedTasks(sortedByDoDate)) { group in
                                groupSection(group: group)
                            }
                        case .byPriority:
                            ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                                let tasks = sortedByDoDate.filter { $0.priority == priority }
                                if !tasks.isEmpty {
                                    flatSection(label: priority.label, tasks: tasks, labelColor: Theme.priorityColor(priority), dropKey: "priority:\(priority.rawValue)")
                                }
                            }
                        }
                    }
                    if !doneTasks.isEmpty { completedSection(tasks: doneTasks) }
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
        .onAppear {
            isCompletedCollapsed = true
        }
        .onChange(of: localSortField) { _, v in
            UserDefaults.standard.set(v.rawValue, forKey: udPrefix + "SortField")
        }
        .onChange(of: localSortDirection) { _, v in
            UserDefaults.standard.set(v.rawValue, forKey: udPrefix + "SortDirection")
        }
        .onChange(of: localGroupingMode) { _, v in
            UserDefaults.standard.set(v.rawValue, forKey: udPrefix + "GroupingMode")
        }
        .background {
            HoverFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                naturalIDs: mode == .todayOverview
                    ? todayEligibleTasks.sorted(by: compareTasksForCurrentSort).map(\.id)
                    : sortedByDoDate.map(\.id)
            )
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            TasksPanelEnumPickerBadge(title: "Sort", selection: $localSortField)
            TasksPanelEnumPickerBadge(title: "Order", selection: $localSortDirection)
            TasksPanelEnumPickerBadge(title: "Group", selection: $localGroupingMode,
                                      excluded: mode == .todayOverview ? [.byDate] : [])
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Theme.surface)
    }

    // MARK: - Grouping

    private func groupedTasks(_ tasks: [AppTask]) -> [TodayTaskGroup] {
        var groups: [String: TodayTaskGroup] = [:]

        for task in tasks {
            let key: String
            if let area = task.area {
                key = "a_\(area.id.uuidString)"
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
                }
            } else if let project = task.project {
                key = "p_\(project.id.uuidString)"
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
                }
            }
            groups[key]!.tasks.append(task)
        }

        let orderedKeys = sidebarListOrder.filter { groups[$0] != nil }
        let unorderedKeys = groups.keys
            .filter { !orderedKeys.contains($0) }
            .sorted()

        return (orderedKeys + unorderedKeys).compactMap { key in
            guard var group = groups[key] else { return nil }
            group.tasks = applyFreeze(group.tasks.sorted(by: compareTasksForCurrentSort))
            return group
        }
    }

    private func compareTasksForCurrentSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        // Keep the legacy today ranking only for the dedicated Today overview mode.
        if mode == .todayOverview && !enableControls {
            let leftRank = todayTaskSortRank(lhs)
            let rightRank = todayTaskSortRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let ascending: Bool
        switch activeSortField {
        case .custom:
            ascending = lhs.order < rhs.order
        case .date:
            let leftDate = lhs.scheduledDate.isEmpty ? "9999-99-99" : lhs.scheduledDate
            let rightDate = rhs.scheduledDate.isEmpty ? "9999-99-99" : rhs.scheduledDate
            if leftDate != rightDate {
                ascending = leftDate < rightDate
            } else {
                ascending = lhs.order < rhs.order
            }
        case .priority:
            let lp = priorityRank(lhs.priority)
            let rp = priorityRank(rhs.priority)
            if lp != rp {
                ascending = lp < rp
            } else {
                ascending = lhs.order < rhs.order
            }
        }
        return activeSortDirection == .ascending ? ascending : !ascending
    }

    private func todayTaskSortRank(_ task: AppTask) -> Int {
        if !task.dueDate.isEmpty && task.dueDate < todayKey { return 0 }
        if !task.scheduledDate.isEmpty && task.scheduledDate < todayKey { return 1 }
        if task.dueDate == todayKey { return 2 }
        if task.scheduledDate == todayKey { return 3 }
        return 4
    }

    // MARK: - Section builders

    @ViewBuilder
    private func groupSection(group: TodayTaskGroup) -> some View {
        let dropKey = "list:\(group.id)"
        Button {
            toggleGroup(group.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: collapsedGroupIDs.contains(group.id) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)

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

                if let overdueCount = overdueCount(in: group.tasks) {
                    Text("\(overdueCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    Text("/")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                }

                Text("\(regularCount(in: group.tasks))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceElevated.opacity(0.75))
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.cadencePlain)
        .onTapGesture(count: 2) {
            toggleGroup(group.id)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 6)
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first,
                  let droppedID = taskID(from: payload),
                  let droppedTask = allTasks.first(where: { $0.id == droppedID }) else { return false }
            assignTask(droppedTask, for: dropKey)
            return true
        }

        if !collapsedGroupIDs.contains(group.id) {
            ForEach(group.tasks) { task in
                MacTaskRow(task: task, style: .todayGrouped, contexts: contexts, areas: areas, projects: projects)
                    .draggable(taskDragPayload(for: task))
                    .dropDestination(for: String.self) { items, _ in
                        guard let payload = items.first,
                              let droppedID = taskID(from: payload),
                              droppedID != task.id,
                              let droppedTask = allTasks.first(where: { $0.id == droppedID }) else { return false }
                        assignTask(droppedTask, for: dropKey)
                        reorderTask(droppedID: droppedID, targetID: task.id, scopeTasks: group.tasks)
                        return true
                    } isTargeted: { isOver in
                        if isOver { dragOverTaskID = task.id }
                        else if dragOverTaskID == task.id { dragOverTaskID = nil }
                    }
                    .overlay(alignment: .top) {
                        if dragOverTaskID == task.id {
                            Rectangle().fill(Theme.blue).frame(height: 2).padding(.leading, 20).transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                    .padding(.leading, 20)
                    .padding(.trailing, 8)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
    }

    @ViewBuilder
    private func flatSection(label: String, tasks: [AppTask], labelColor: Color, dropKey: String? = nil) -> some View {
        Section {
            let groupID = "flat-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))"
            CollapsibleTaskGroupHeader(
                title: label,
                isCollapsed: collapsedGroupIDs.contains(groupID),
                overdueCount: overdueCount(in: tasks),
                regularCount: regularCount(in: tasks),
                accent: labelColor,
                onToggle: { toggleGroup(groupID) }
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 5)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .dropDestination(for: String.self) { items, _ in
                guard let dropKey,
                      let payload = items.first,
                      let droppedID = taskID(from: payload),
                      let droppedTask = allTasks.first(where: { $0.id == droppedID }) else { return false }
                assignTask(droppedTask, for: dropKey)
                return true
            }
            if !collapsedGroupIDs.contains(groupID) {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: .standard, contexts: contexts, areas: areas, projects: projects)
                        .draggable(taskDragPayload(for: task))
                        .dropDestination(for: String.self) { items, _ in
                            guard let payload = items.first,
                                  let droppedID = taskID(from: payload),
                                  droppedID != task.id,
                                  let droppedTask = allTasks.first(where: { $0.id == droppedID }) else { return false }
                            if let dropKey {
                                assignTask(droppedTask, for: dropKey)
                            }
                            reorderTask(droppedID: droppedID, targetID: task.id, scopeTasks: tasks)
                            return true
                        } isTargeted: { isOver in
                            if isOver { dragOverTaskID = task.id }
                            else if dragOverTaskID == task.id { dragOverTaskID = nil }
                        }
                        .overlay(alignment: .top) {
                            if dragOverTaskID == task.id {
                                Rectangle().fill(Theme.blue).frame(height: 2).padding(.leading, 16).transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                        .padding(.leading, 16)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
        }
    }

    private var isEmptyState: Bool {
        switch mode {
        case .todayOverview:
            return overdue.isEmpty &&
            overdoTasks.isEmpty &&
            dueTodayTasks.isEmpty &&
            doTodayTasks.isEmpty &&
            doneTasks.isEmpty
        case .byDoDate:
            return byDoDateBaseTasks.isEmpty && doneTasks.isEmpty
        }
    }

    private func taskIsUnscheduled(_ task: AppTask) -> Bool {
        task.scheduledDate.isEmpty
    }

    @ViewBuilder
    private func completedSection(tasks: [AppTask]) -> some View {
        Section {
            CompletedSectionHeader(
                count: tasks.count,
                isCollapsed: isCompletedCollapsed,
                onToggle: { isCompletedCollapsed.toggle() }
            )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 6)
            if !isCompletedCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: mode == .todayOverview ? .todayGrouped : .standard, contexts: contexts, areas: areas, projects: projects)
                        .draggable(taskDragPayload(for: task))
                        .padding(.leading, 16)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
        }
    }

    @ViewBuilder
    private func rolloverNoticeSection(tasks: [AppTask]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 22, height: 22)
                    .background(Theme.amber.opacity(0.16))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Leftover tasks are rolling over to today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Review these tasks, then confirm to move them into today's groups.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()

                Button("Roll Over") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        for task in tasks {
                            task.scheduledDate = todayKey
                        }
                        rolloverNoticeDismissedDate = todayKey
                        try? modelContext.save()
                    }
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            VStack(spacing: 4) {
                ForEach(tasks) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: task.containerColor))
                            .frame(width: 6, height: 6)
                        Text(task.title.isEmpty ? "Untitled" : task.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer()
                        if !task.containerName.isEmpty {
                            Text(task.containerName)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.6)).frame(height: 0.5)
        }
    }

    private func toggleGroup(_ id: String) {
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
    }

    private func overdueCount(in tasks: [AppTask]) -> Int? {
        let count = tasks.filter { !$0.isDone && !$0.dueDate.isEmpty && $0.dueDate < todayKey }.count
        return count > 0 ? count : nil
    }

    private func regularCount(in tasks: [AppTask]) -> Int {
        tasks.filter { !$0.isDone }.count - (overdueCount(in: tasks) ?? 0)
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    private func taskDragPayload(for task: AppTask) -> String {
        "listTask:\(task.id.uuidString)"
    }

    private func taskID(from payload: String) -> UUID? {
        if payload.hasPrefix("listTask:") {
            return UUID(uuidString: String(payload.dropFirst(9)))
        }
        return UUID(uuidString: payload)
    }

    private func reorderTask(droppedID: UUID, targetID: UUID, scopeTasks: [AppTask]) {
        var sorted = scopeTasks.sorted { $0.order < $1.order }
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let moved = sorted.remove(at: fromIndex)
        sorted.insert(moved, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (idx, task) in sorted.enumerated() {
                task.order = idx
            }
        }
        try? modelContext.save()
    }

    private func assignTask(_ task: AppTask, for dropKey: String) {
        if dropKey.hasPrefix("list:") {
            let listID = String(dropKey.dropFirst(5))
            if listID == "inbox" {
                task.area = nil
                task.project = nil
                task.context = nil
            } else if listID.hasPrefix("a_") {
                let areaID = String(listID.dropFirst(2))
                if let target = areas.first(where: { $0.id.uuidString == areaID }) {
                    task.area = target
                    task.project = nil
                    task.context = target.context
                }
            } else if listID.hasPrefix("p_") {
                let projectID = String(listID.dropFirst(2))
                if let target = projects.first(where: { $0.id.uuidString == projectID }) {
                    task.project = target
                    task.area = nil
                    task.context = target.context
                }
            }
        } else if dropKey == "date:today" {
            task.scheduledDate = todayKey
        } else if dropKey == "date:scheduled" {
            if task.scheduledDate.isEmpty || task.scheduledDate == todayKey {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
            }
        } else if dropKey == "date:unscheduled" {
            task.scheduledDate = ""
            task.scheduledStartMin = -1
        } else if dropKey.hasPrefix("priority:") {
            let raw = String(dropKey.dropFirst(9))
            if let p = TaskPriority(rawValue: raw) {
                task.priority = p
            }
        }
        try? modelContext.save()
    }

}

private struct HoverFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenOrder: [UUID]?
    let naturalIDs: [UUID]

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if newID != nil {
                    if frozenOrder == nil { frozenOrder = naturalIDs }
                } else if frozenOrder != nil {
                    frozenOrder = nil
                }
            }
    }
}

private struct TasksPanelEnumPickerBadge<T: CaseIterable & RawRepresentable & Identifiable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    var excluded: [T] = []
    @State private var showPicker = false

    private var availableCases: [T] {
        Array(T.allCases).filter { item in !excluded.contains(where: { $0.id == item.id }) }
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(selection.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(availableCases, id: \.id) { value in
                    Button {
                        selection = value
                        showPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(value.rawValue).font(.system(size: 13)).foregroundStyle(Theme.text)
                            Spacer()
                            if selection.id == value.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(selection.id == value.id ? Theme.blue.opacity(0.08) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.cadencePlain)
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 170)
            .background(Theme.surfaceElevated)
        }
    }
}

#endif
