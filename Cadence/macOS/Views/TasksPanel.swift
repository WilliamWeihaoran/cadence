#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Tasks Panel

struct TasksPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(ListNavigationManager.self) private var listNavigationManager
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
    let useStandardHeaderHeight: Bool
    @AppStorage("todayRolloverNoticeDismissedDate") private var rolloverNoticeDismissedDate = ""
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var localSortField: TaskSortField = .date
    @State private var localSortDirection: TaskSortDirection = .ascending
    @State private var localGroupingMode: TaskGroupingMode = .byDate
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenListGroups: [FrozenTodayTaskGroup]? = nil
    @State private var frozenFlatSections: [FrozenFlatTaskSection]? = nil
    @State private var dragOverTaskID: UUID? = nil

    init(
        mode: TasksPanelMode = .todayOverview,
        showsHeader: Bool = true,
        sortField: TaskSortField = .date,
        sortDirection: TaskSortDirection = .ascending,
        groupingMode: TaskGroupingMode = .byDate,
        enableControls: Bool = false,
        useStandardHeaderHeight: Bool = false
    ) {
        self.mode = mode
        self.showsHeader = showsHeader
        self.sortField = sortField
        self.sortDirection = sortDirection
        self.groupingMode = groupingMode
        self.enableControls = enableControls
        self.useStandardHeaderHeight = useStandardHeaderHeight
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

    private var derivedState: TasksPanelDerivedState {
        TasksPanelDerivedState(
            allTasks: allTasks,
            areas: areas,
            projects: projects,
            mode: mode,
            todayKey: todayKey,
            sortField: activeSortField,
            sortDirection: activeSortDirection
        )
    }

    private var overdue: [AppTask] { derivedState.overdue }
    private var dueTodayTasks: [AppTask] { derivedState.dueTodayTasks }
    private var doTodayTasks: [AppTask] { derivedState.doTodayTasks }
    private var overdoTasks: [AppTask] { derivedState.overdoTasks }
    private var todayGroupedTaskItems: [AppTask] { derivedState.todayGroupedTaskItems(showRolloverNotice: shouldShowRolloverNotice) }
    private var todayEligibleTasks: [AppTask] { derivedState.todayEligibleTasks }
    private var overdueListSummaries: [TodayOverdueListSummary] { derivedState.overdueListSummaries }
    private var overdueSectionSummaries: [TodayOverdueSectionSummary] { derivedState.overdueSectionSummaries }
    private var shouldShowRolloverNotice: Bool {
        mode == .todayOverview && !overdoTasks.isEmpty && rolloverNoticeDismissedDate != todayKey
    }
    private var byDoDateBaseTasks: [AppTask] { derivedState.byDoDateBaseTasks }
    private var byDoDateBaseSortedTasks: [AppTask] { derivedState.byDoDateBaseSortedTasks }
    private func applyFreeze(_ sorted: [AppTask]) -> [AppTask] {
        applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }

    private var byDoDateSortedTasks: [AppTask] {
        applyFreeze(byDoDateBaseSortedTasks)
    }
    private var doneTasks: [AppTask] { derivedState.doneTasks }

    private var dropCoordinator: TasksPanelDropCoordinator {
        TasksPanelDropCoordinator(
            allTasks: allTasks,
            taskIDFromPayload: { TasksPanelSupport.taskID(from: $0) },
            assignTask: { task, dropKey in
                TasksPanelSupport.assignTask(
                    task,
                    for: dropKey,
                    todayKey: todayKey,
                    areas: areas,
                    projects: projects,
                    modelContext: modelContext
                )
            },
            reorderTask: { droppedID, targetID, scopeTasks in
                TasksPanelSupport.reorderTask(
                    droppedID: droppedID,
                    targetID: targetID,
                    scopeTasks: scopeTasks,
                    modelContext: modelContext
                )
            }
        )
    }

    private var resolvedFrozenListGroups: [TodayTaskGroup]? {
        guard let frozenListGroups else { return nil }
        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        return frozenListGroups.compactMap { group in
            let resolvedTasks = group.taskIDs.compactMap { tasksByID[$0] }.filter { !$0.isDone }
            guard !resolvedTasks.isEmpty else { return nil }
            return TodayTaskGroup(
                id: group.id,
                contextID: group.contextID,
                contextName: group.contextName,
                contextIcon: group.contextIcon,
                contextColor: group.contextColor,
                listIcon: group.listIcon,
                listName: group.listName,
                listColor: group.listColor,
                tasks: resolvedTasks
            )
        }
    }

    private var resolvedFrozenFlatSections: [FrozenFlatTaskSection]? {
        guard let frozenFlatSections else { return nil }
        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        return frozenFlatSections.compactMap { section in
            let resolvedTasks = section.taskIDs.compactMap { tasksByID[$0] }.filter { !$0.isDone }
            guard !resolvedTasks.isEmpty else { return nil }
            return FrozenFlatTaskSection(
                id: section.id,
                title: section.title,
                labelColor: section.labelColor,
                dropKey: section.dropKey,
                taskIDs: resolvedTasks.map(\.id)
            )
        }
    }

    var body: some View {
        let sortedByDoDate: [AppTask] = mode == .byDoDate ? byDoDateSortedTasks : []
        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                VStack(alignment: .leading, spacing: 0) {
                    TasksPanelHeader(mode: mode)
                    if enableControls {
                        controlsBar
                    }
                }
                .frame(height: useStandardHeaderHeight ? todayPanelHeaderHeight : nil, alignment: .top)
                Divider().background(Theme.borderSubtle)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if mode == .todayOverview {
                        if shouldShowRolloverNotice {
                            TasksPanelRolloverNoticeSectionView(tasks: overdoTasks) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    for task in overdoTasks {
                                        if task.scheduledStartMin >= 0 {
                                            SchedulingActions.removeFromCalendar(task)
                                        }
                                        task.scheduledDate = todayKey
                                        task.scheduledStartMin = -1
                                    }
                                    rolloverNoticeDismissedDate = todayKey
                                    try? modelContext.save()
                                }
                            }
                        }
                        if !overdueListSummaries.isEmpty {
                            overdueListsSection
                        }
                        if !overdueSectionSummaries.isEmpty {
                            overdueSectionsSection
                        }
                        let todayTasks = shouldShowRolloverNotice ? todayGroupedTaskItems : todayEligibleTasks
                        if enableControls {
                            switch activeGroupingMode {
                            case .none:
                                if let frozenSections = resolvedFrozenFlatSections {
                                    ForEach(frozenSections, id: \.id) { section in
                                        sectionView(from: section, tasksByID: tasksByID)
                                    }
                                } else if !todayTasks.isEmpty {
                                    liveFlatSection(label: "Today Tasks", tasks: todayTasks, labelColor: Theme.dim)
                                }
                            case .byDate:
                                if let frozenSections = resolvedFrozenFlatSections {
                                    ForEach(frozenSections, id: \.id) { section in
                                        sectionView(from: section, tasksByID: tasksByID)
                                    }
                                } else {
                                    if !overdue.isEmpty { liveFlatSection(label: "Past Due", tasks: overdue, labelColor: Theme.red) }
                                    if !overdoTasks.isEmpty { liveFlatSection(label: "Past Do", tasks: overdoTasks, labelColor: Theme.amber) }
                                    if !dueTodayTasks.isEmpty { liveFlatSection(label: "Due Today", tasks: dueTodayTasks, labelColor: Theme.red.opacity(0.85)) }
                                    if !doTodayTasks.isEmpty { liveFlatSection(label: "Do Today", tasks: doTodayTasks, labelColor: Theme.blue) }
                                }
                            case .byList:
                                todayListSections(groups: groupedTasks(todayTasks))
                            case .byPriority:
                                if let frozenSections = resolvedFrozenFlatSections {
                                    ForEach(frozenSections, id: \.id) { section in
                                        sectionView(from: section, tasksByID: tasksByID)
                                    }
                                } else {
                                    ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                                        let tasks = todayTasks.filter { $0.priority == priority }
                                        if !tasks.isEmpty {
                                            liveFlatSection(
                                                label: priority.label,
                                                tasks: tasks,
                                                labelColor: Theme.priorityColor(priority),
                                                dropKey: "priority:\(priority.rawValue)"
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            let groups = groupedTasks(todayGroupedTaskItems)
                            if !groups.isEmpty {
                                todayListSections(groups: groups)
                            }
                        }
                    } else {
                        let todayK = todayKey
                        switch activeGroupingMode {
                        case .none:
                            if let frozenSections = resolvedFrozenFlatSections {
                                ForEach(frozenSections, id: \.id) { section in
                                    sectionView(from: section, tasksByID: tasksByID)
                                }
                            } else if !sortedByDoDate.isEmpty {
                                liveFlatSection(label: "Tasks", tasks: sortedByDoDate, labelColor: Theme.dim)
                            }
                        case .byDate:
                            if let frozenSections = resolvedFrozenFlatSections {
                                ForEach(frozenSections, id: \.id) { section in
                                    sectionView(from: section, tasksByID: tasksByID)
                                }
                            } else {
                                let todayTasks = sortedByDoDate.filter { $0.scheduledDate == todayK }
                                let upcomingTasks = sortedByDoDate.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayK }
                                let unscheduledTasks = sortedByDoDate.filter { taskIsUnscheduled($0) }
                                if !todayTasks.isEmpty  { liveFlatSection(label: "Do Today", tasks: todayTasks, labelColor: Theme.blue, dropKey: "date:today") }
                                if !upcomingTasks.isEmpty { liveFlatSection(label: "Scheduled", tasks: upcomingTasks, labelColor: Theme.dim, dropKey: "date:scheduled") }
                                if !unscheduledTasks.isEmpty { liveFlatSection(label: "Unscheduled", tasks: unscheduledTasks, labelColor: Theme.amber, dropKey: "date:unscheduled") }
                            }
                        case .byList:
                            ForEach(groupedTasks(sortedByDoDate)) { group in
                                TasksPanelGroupSectionView(
                                    group: group,
                                    dragOverTaskID: $dragOverTaskID,
                                    contexts: contexts,
                                    areas: areas,
                                    projects: projects,
                                    allTasks: allTasks,
                                    isCollapsed: collapsedGroupIDs.contains(group.id),
                                    overdueCount: overdueCount(in: group.tasks),
                                    regularCount: regularCount(in: group.tasks),
                                    onToggle: { toggleGroup(group.id) },
                                    taskDragPayload: taskDragPayload,
                                    onDropOnGroupPayload: { payload in
                                        dropCoordinator.handleSectionDrop(payload: payload, dropKey: "list:\(group.id)")
                                    },
                                    onDropOnTaskPayload: { payload, targetTask in
                                        dropCoordinator.handleTaskDrop(
                                            payload: payload,
                                            targetTask: targetTask,
                                            scopeTasks: group.tasks,
                                            dropKey: "list:\(group.id)"
                                        )
                                    }
                                )
                            }
                        case .byPriority:
                            if let frozenSections = resolvedFrozenFlatSections {
                                ForEach(frozenSections, id: \.id) { section in
                                    sectionView(from: section, tasksByID: tasksByID)
                                }
                            } else {
                                ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                                    let tasks = sortedByDoDate.filter { $0.priority == priority }
                                    if !tasks.isEmpty {
                                        liveFlatSection(label: priority.label, tasks: tasks, labelColor: Theme.priorityColor(priority), dropKey: "priority:\(priority.rawValue)")
                                    }
                                }
                            }
                        }
                    }
                    if !doneTasks.isEmpty {
                        TasksPanelCompletedSectionView(
                            tasks: doneTasks,
                            mode: mode,
                            contexts: contexts,
                            areas: areas,
                            projects: projects,
                            allTasks: allTasks,
                            isCollapsed: isCompletedCollapsed,
                            onToggle: { isCompletedCollapsed.toggle() },
                            taskDragPayload: taskDragPayload
                        )
                    }
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
            .cadenceSoftPageBounce()
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
                frozenListGroups: $frozenListGroups,
                frozenFlatSections: $frozenFlatSections,
                naturalTasks: mode == .todayOverview
                    ? todayEligibleTasks.sorted(by: compareTasksForCurrentSort)
                    : sortedByDoDate
                ,
                listGroupSnapshot: {
                    let snapshotTasks = mode == .todayOverview
                        ? (shouldShowRolloverNotice ? todayGroupedTaskItems : todayEligibleTasks)
                        : sortedByDoDate
                    return activeGroupingMode == .byList ? currentFrozenListGroupSnapshot(for: snapshotTasks) : []
                }(),
                flatSectionSnapshot: activeGroupingMode == .byList ? [] : currentFrozenFlatSectionSnapshot()
            )
        }
    }

    @ViewBuilder
    private func liveFlatSection(label: String, tasks: [AppTask], labelColor: Color, dropKey: String? = nil) -> some View {
        TasksPanelFlatSectionView(
            label: label,
            tasks: tasks,
            labelColor: labelColor,
            contexts: contexts,
            areas: areas,
            projects: projects,
            allTasks: allTasks,
            isCollapsed: collapsedGroupIDs.contains("flat-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))"),
            overdueCount: overdueCount(in: tasks),
            regularCount: regularCount(in: tasks),
            dragOverTaskID: $dragOverTaskID,
            onToggle: { toggleGroup("flat-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))") },
            taskDragPayload: taskDragPayload,
            onDropOnSectionPayload: dropCoordinator.sectionDropHandler(for: dropKey),
            onDropOnTaskPayload: dropCoordinator.taskDropHandler(scopeTasks: tasks, dropKey: dropKey)
        )
    }

    @ViewBuilder
    private func sectionView(from section: FrozenFlatTaskSection, tasksByID: [UUID: AppTask]) -> some View {
        let sectionTasks = section.taskIDs.compactMap { tasksByID[$0] }
        liveFlatSection(label: section.title, tasks: sectionTasks, labelColor: section.labelColor, dropKey: section.dropKey)
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            CadenceEnumPickerBadge(title: "Sort", selection: $localSortField)
            CadenceEnumPickerBadge(title: "Order", selection: $localSortDirection)
            CadenceEnumPickerBadge(title: "Group", selection: $localGroupingMode,
                                   excluded: mode == .todayOverview ? [.byDate] : [])
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Theme.surface)
    }

    private var overdueListsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past Due Lists")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.red)
                .kerning(0.8)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(overdueListSummaries) { summary in
                    TodayOverdueListCard(summary: summary) {
                        openOverdueListSummary(summary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var overdueSectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past Due Sections")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.red.opacity(0.9))
                .kerning(0.8)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(overdueSectionSummaries) { summary in
                    TodayOverdueSectionCard(summary: summary) {
                        openOverdueSectionSummary(summary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Grouping

    private func todayContextSections(from groups: [TodayTaskGroup]) -> [TodayTaskContextSection] {
        var orderedSections: [TodayTaskContextSection] = []
        var groupedContextMap: [String: Int] = [:]

        for group in groups {
            if let contextID = group.contextID {
                if let index = groupedContextMap[contextID] {
                    orderedSections[index] = TodayTaskContextSection(
                        id: orderedSections[index].id,
                        contextName: orderedSections[index].contextName,
                        contextIcon: orderedSections[index].contextIcon,
                        contextColor: orderedSections[index].contextColor,
                        groups: orderedSections[index].groups + [group]
                    )
                } else {
                    groupedContextMap[contextID] = orderedSections.count
                    orderedSections.append(
                        TodayTaskContextSection(
                            id: "context-\(contextID)",
                            contextName: group.contextName,
                            contextIcon: group.contextIcon,
                            contextColor: group.contextColor,
                            groups: [group]
                        )
                    )
                }
            } else {
                orderedSections.append(
                    TodayTaskContextSection(
                        id: "group-\(group.id)",
                        contextName: nil,
                        contextIcon: nil,
                        contextColor: nil,
                        groups: [group]
                    )
                )
            }
        }

        return orderedSections
    }

    @ViewBuilder
    private func todayListSections(groups: [TodayTaskGroup]) -> some View {
        ForEach(todayContextSections(from: groups)) { section in
            TodayTaskContextSectionView(
                section: section,
                dragOverTaskID: $dragOverTaskID,
                contexts: contexts,
                areas: areas,
                projects: projects,
                allTasks: allTasks,
                collapsedGroupIDs: collapsedGroupIDs,
                overdueCount: { overdueCount(in: $0) },
                regularCount: { regularCount(in: $0) },
                onToggleGroup: toggleGroup,
                taskDragPayload: taskDragPayload,
                onDropOnGroupPayload: { group, payload in
                    dropCoordinator.handleSectionDrop(payload: payload, dropKey: "list:\(group.id)")
                },
                onDropOnTaskPayload: { group, payload, targetTask in
                    dropCoordinator.handleTaskDrop(
                        payload: payload,
                        targetTask: targetTask,
                        scopeTasks: group.tasks,
                        dropKey: "list:\(group.id)"
                    )
                }
            )
        }
    }

    private func groupedTasks(_ tasks: [AppTask]) -> [TodayTaskGroup] {
        if let resolvedFrozenListGroups {
            return resolvedFrozenListGroups
        }

        return TasksPanelSupport.listGroups(from: tasks, contexts: contexts) { groupTasks in
            applyFreeze(groupTasks.sorted(by: compareTasksForCurrentSort))
        }
    }

    private func makeFlatSection(
        id: String,
        title: String,
        tasks: [AppTask],
        labelColor: Color,
        dropKey: String? = nil
    ) -> FrozenFlatTaskSection? {
        guard !tasks.isEmpty else { return nil }
        return TasksPanelSupport.makeFlatSection(
            id: id,
            title: title,
            tasks: tasks,
            labelColor: labelColor,
            dropKey: dropKey
        )
    }

    private func currentFrozenListGroupSnapshot(for tasks: [AppTask]) -> [FrozenTodayTaskGroup] {
        groupedTasks(tasks).map { group in
            FrozenTodayTaskGroup(
                id: group.id,
                contextID: group.contextID,
                contextName: group.contextName,
                contextIcon: group.contextIcon,
                contextColor: group.contextColor,
                listIcon: group.listIcon,
                listName: group.listName,
                listColor: group.listColor,
                taskIDs: group.tasks.map(\.id)
            )
        }
    }

    private func currentFrozenFlatSectionSnapshot() -> [FrozenFlatTaskSection] {
        switch mode {
        case .todayOverview:
            let todayTasks = shouldShowRolloverNotice ? todayGroupedTaskItems : todayEligibleTasks
            switch activeGroupingMode {
            case .none:
                return [makeFlatSection(id: "today-tasks", title: "Today Tasks", tasks: todayTasks, labelColor: Theme.dim)].compactMap { $0 }
            case .byDate:
                return [
                    makeFlatSection(id: "past-due", title: "Past Due", tasks: overdue, labelColor: Theme.red),
                    makeFlatSection(id: "past-do", title: "Past Do", tasks: overdoTasks, labelColor: Theme.amber),
                    makeFlatSection(id: "due-today", title: "Due Today", tasks: dueTodayTasks, labelColor: Theme.red.opacity(0.85)),
                    makeFlatSection(id: "do-today", title: "Do Today", tasks: doTodayTasks, labelColor: Theme.blue)
                ].compactMap { $0 }
            case .byList:
                return []
            case .byPriority:
                return TaskPriority.allCases.reversed().compactMap { priority in
                    makeFlatSection(
                        id: "priority-\(priority.rawValue)",
                        title: priority.label,
                        tasks: todayTasks.filter { $0.priority == priority },
                        labelColor: Theme.priorityColor(priority),
                        dropKey: "priority:\(priority.rawValue)"
                    )
                }
            }
        case .byDoDate:
            let todayK = todayKey
            switch activeGroupingMode {
            case .none:
                return [makeFlatSection(id: "tasks", title: "Tasks", tasks: byDoDateSortedTasks, labelColor: Theme.dim)].compactMap { $0 }
            case .byDate:
                let todayTasks = byDoDateSortedTasks.filter { $0.scheduledDate == todayK }
                let upcomingTasks = byDoDateSortedTasks.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayK }
                let unscheduledTasks = byDoDateSortedTasks.filter { taskIsUnscheduled($0) }
                return [
                    makeFlatSection(id: "do-today", title: "Do Today", tasks: todayTasks, labelColor: Theme.blue, dropKey: "date:today"),
                    makeFlatSection(id: "scheduled", title: "Scheduled", tasks: upcomingTasks, labelColor: Theme.dim, dropKey: "date:scheduled"),
                    makeFlatSection(id: "unscheduled", title: "Unscheduled", tasks: unscheduledTasks, labelColor: Theme.amber, dropKey: "date:unscheduled")
                ].compactMap { $0 }
            case .byList:
                return []
            case .byPriority:
                return TaskPriority.allCases.reversed().compactMap { priority in
                    makeFlatSection(
                        id: "priority-\(priority.rawValue)",
                        title: priority.label,
                        tasks: byDoDateSortedTasks.filter { $0.priority == priority },
                        labelColor: Theme.priorityColor(priority),
                        dropKey: "priority:\(priority.rawValue)"
                    )
                }
            }
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

        return taskSortPrecedes(lhs, rhs, field: activeSortField, direction: activeSortDirection)
    }

    private func todayTaskSortRank(_ task: AppTask) -> Int {
        if !task.dueDate.isEmpty && task.dueDate < todayKey { return 0 }
        if !task.scheduledDate.isEmpty && task.scheduledDate < todayKey { return 1 }
        if task.dueDate == todayKey { return 2 }
        if task.scheduledDate == todayKey { return 3 }
        return 4
    }

    // MARK: - Section builders

    private var isEmptyState: Bool {
        derivedState.isEmptyState(for: mode)
    }

    private func taskIsUnscheduled(_ task: AppTask) -> Bool {
        task.scheduledDate.isEmpty
    }

    private func toggleGroup(_ id: String) {
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
    }

    private func overdueCount(in tasks: [AppTask]) -> Int? {
        TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey)
    }

    private func regularCount(in tasks: [AppTask]) -> Int {
        TasksPanelSupport.regularCount(in: tasks, todayKey: todayKey)
    }

    private func openOverdueListSummary(_ summary: TodayOverdueListSummary) {
        TasksPanelSupport.openOverdueListSummary(summary, listNavigationManager: listNavigationManager)
    }

    private func openOverdueSectionSummary(_ summary: TodayOverdueSectionSummary) {
        TasksPanelSupport.openOverdueSectionSummary(summary, listNavigationManager: listNavigationManager)
    }


    private func taskDragPayload(for task: AppTask) -> String {
        TasksPanelSupport.taskDragPayload(for: task)
    }
}

#endif
