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

    /// Expensive: four filters, a full sort, a `sectionConfigs` decode per active list, and a
    /// pass over every completed task ever created. Build it **once per body pass** and thread
    /// the value down (`body` does exactly that) — the eleven forwarding computed properties
    /// this replaced each rebuilt the whole thing on every access.
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

    private func shouldShowRolloverNotice(_ derived: TasksPanelDerivedState) -> Bool {
        mode == .todayOverview && !derived.overdoTasks.isEmpty && rolloverNoticeDismissedDate != todayKey
    }

    private func applyFreeze(_ sorted: [AppTask]) -> [AppTask] {
        applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }

    private func byDoDateSortedTasks(_ derived: TasksPanelDerivedState) -> [AppTask] {
        applyFreeze(derived.byDoDateBaseSortedTasks)
    }

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
        let derived = derivedState

        // Split into two statements purely to keep the type checker inside its time budget —
        // one chain off a `let`-bound `derived` was enough to blow it.
        let shell = panelShell(derived: derived)
            .background(
                Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
            )
            .background(Theme.surface)
            .background { hoverFreezeObserver(derived: derived) }

        return shell
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
    }

    private func panelShell(derived: TasksPanelDerivedState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                headerSection
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    taskSections(derived: derived)
                    completedSection(derived: derived)
                    emptyStateSection(derived: derived)
                }
                .padding(.top, showsHeader && mode == .todayOverview ? 12 : 0)
                .padding(.bottom, 16)
            }
            .cadenceSoftPageBounce()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TasksPanelHeader(mode: mode)
                if enableControls {
                    controlsBar
                }
            }
            .frame(height: useStandardHeaderHeight ? todayPanelHeaderHeight : nil, alignment: .top)
            Divider().background(Theme.borderSubtle)
        }
    }

    @ViewBuilder
    private func taskSections(derived: TasksPanelDerivedState) -> some View {
        switch mode {
        case .todayOverview:
            todayOverviewSections(derived: derived)
        case .byDoDate:
            byDoDateSections(derived: derived)
        }
    }

    @ViewBuilder
    private func todayOverviewSections(derived: TasksPanelDerivedState) -> some View {
        let showsRollover = shouldShowRolloverNotice(derived)

        if showsRollover {
            TasksPanelRolloverNoticeSectionView(tasks: derived.overdoTasks) {
                rollOverPastDoTasks()
            }
        }
        if !derived.overdueListSummaries.isEmpty {
            overdueListsSection(summaries: derived.overdueListSummaries)
        }
        if !derived.overdueSectionSummaries.isEmpty {
            overdueSectionsSection(summaries: derived.overdueSectionSummaries)
        }

        if enableControls {
            todayControlledSections(derived: derived)
        } else {
            let groups = groupedTasks(derived.todayGroupedTaskItems(showRolloverNotice: showsRollover))
            if !groups.isEmpty {
                todayListSections(groups: groups)
            }
        }
    }

    @ViewBuilder
    private func todayControlledSections(derived: TasksPanelDerivedState) -> some View {
        let showsRollover = shouldShowRolloverNotice(derived)
        let todayTasks = showsRollover
            ? derived.todayGroupedTaskItems(showRolloverNotice: true)
            : derived.todayEligibleTasks
        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })

        switch activeGroupingMode {
        case .none:
            frozenOrSingleFlatSection(
                frozenSections: resolvedFrozenFlatSections,
                tasksByID: tasksByID,
                label: "Today Tasks",
                tasks: todayTasks,
                labelColor: Theme.dim
            )
        case .byDate:
            if let frozenSections = resolvedFrozenFlatSections {
                frozenFlatSections(frozenSections, tasksByID: tasksByID)
            } else {
                todayDateSections(derived: derived)
            }
        case .byList:
            todayListSections(groups: groupedTasks(todayTasks))
        case .byPriority:
            prioritySections(tasks: todayTasks, frozenSections: resolvedFrozenFlatSections, tasksByID: tasksByID)
        }
    }

    @ViewBuilder
    private func todayDateSections(derived: TasksPanelDerivedState) -> some View {
        if !derived.overdue.isEmpty { liveFlatSection(label: "Past Due", tasks: derived.overdue, labelColor: Theme.red) }
        if !derived.overdoTasks.isEmpty { liveFlatSection(label: "Past Do", tasks: derived.overdoTasks, labelColor: Theme.amber) }
        if !derived.dueTodayTasks.isEmpty { liveFlatSection(label: "Due Today", tasks: derived.dueTodayTasks, labelColor: Theme.red.opacity(0.85)) }
        if !derived.doTodayTasks.isEmpty { liveFlatSection(label: "Do Today", tasks: derived.doTodayTasks, labelColor: Theme.blue) }
    }

    @ViewBuilder
    private func byDoDateSections(derived: TasksPanelDerivedState) -> some View {
        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        let sortedTasks = byDoDateSortedTasks(derived)

        switch activeGroupingMode {
        case .none:
            frozenOrSingleFlatSection(
                frozenSections: resolvedFrozenFlatSections,
                tasksByID: tasksByID,
                label: "Tasks",
                tasks: sortedTasks,
                labelColor: Theme.dim
            )
        case .byDate:
            if let frozenSections = resolvedFrozenFlatSections {
                frozenFlatSections(frozenSections, tasksByID: tasksByID)
            } else {
                byDoDateDateSections(sortedTasks: sortedTasks)
            }
        case .byList:
            byDoDateListSections(sortedTasks: sortedTasks)
        case .byPriority:
            prioritySections(tasks: sortedTasks, frozenSections: resolvedFrozenFlatSections, tasksByID: tasksByID)
        }
    }

    @ViewBuilder
    private func byDoDateDateSections(sortedTasks: [AppTask]) -> some View {
        let todayTasks = sortedTasks.filter { $0.scheduledDate == todayKey }
        let upcomingTasks = sortedTasks.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayKey }
        let unscheduledTasks = sortedTasks.filter { taskIsUnscheduled($0) }

        if !todayTasks.isEmpty {
            liveFlatSection(label: "Do Today", tasks: todayTasks, labelColor: Theme.blue, dropKey: "date:today")
        }
        if !upcomingTasks.isEmpty {
            liveFlatSection(label: "Scheduled", tasks: upcomingTasks, labelColor: Theme.dim, dropKey: "date:scheduled")
        }
        if !unscheduledTasks.isEmpty {
            liveFlatSection(label: "Unscheduled", tasks: unscheduledTasks, labelColor: Theme.amber, dropKey: "date:unscheduled")
        }
    }

    @ViewBuilder
    private func byDoDateListSections(sortedTasks: [AppTask]) -> some View {
        ForEach(groupedTasks(sortedTasks)) { group in
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
    }

    @ViewBuilder
    private func frozenOrSingleFlatSection(
        frozenSections: [FrozenFlatTaskSection]?,
        tasksByID: [UUID: AppTask],
        label: String,
        tasks: [AppTask],
        labelColor: Color
    ) -> some View {
        if let frozenSections {
            frozenFlatSections(frozenSections, tasksByID: tasksByID)
        } else if !tasks.isEmpty {
            liveFlatSection(label: label, tasks: tasks, labelColor: labelColor)
        }
    }

    @ViewBuilder
    private func frozenFlatSections(_ sections: [FrozenFlatTaskSection], tasksByID: [UUID: AppTask]) -> some View {
        ForEach(sections, id: \.id) { section in
            sectionView(from: section, tasksByID: tasksByID)
        }
    }

    @ViewBuilder
    private func prioritySections(
        tasks: [AppTask],
        frozenSections: [FrozenFlatTaskSection]?,
        tasksByID: [UUID: AppTask]
    ) -> some View {
        if let frozenSections {
            frozenFlatSections(frozenSections, tasksByID: tasksByID)
        } else {
            ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                let priorityTasks = tasks.filter { $0.priority == priority }
                if !priorityTasks.isEmpty {
                    liveFlatSection(
                        label: priority.label,
                        tasks: priorityTasks,
                        labelColor: Theme.priorityColor(priority),
                        dropKey: "priority:\(priority.rawValue)"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func completedSection(derived: TasksPanelDerivedState) -> some View {
        if !derived.doneTasks.isEmpty {
            TasksPanelCompletedSectionView(
                tasks: derived.doneTasks,
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
    }

    @ViewBuilder
    private func emptyStateSection(derived: TasksPanelDerivedState) -> some View {
        if derived.isEmptyState(for: mode) {
            EmptyStateView(
                message: mode == .byDoDate ? "No tasks yet" : "Nothing for today",
                subtitle: mode == .byDoDate ? "Add a task above to get started" : "Due-today and do-today tasks will appear here",
                icon: "checkmark.circle"
            )
            .padding(.top, 40)
        }
    }

    private func hoverFreezeObserver(derived: TasksPanelDerivedState) -> some View {
        HoverFreezeObserver(
            frozenOrder: $frozenTaskOrder,
            frozenListGroups: $frozenListGroups,
            frozenFlatSections: $frozenFlatSections,
            naturalTasks: mode == .todayOverview
                ? derived.todayEligibleTasks.sorted(by: compareTasksForCurrentSort)
                : byDoDateSortedTasks(derived),
            listGroupSnapshot: currentFrozenListSnapshotForHover(derived),
            // Intentional: keep flat/date/priority section trees live while hovering.
            // Capturing section snapshots swaps the row tree under the pointer and
            // can create hover-enter/exit refresh jitter in grouped Today views.
            flatSectionSnapshot: []
        )
    }

    private func currentFrozenListSnapshotForHover(_ derived: TasksPanelDerivedState) -> [FrozenTodayTaskGroup] {
        guard activeGroupingMode == .byList else { return [] }
        let snapshotTasks = mode == .todayOverview
            ? (shouldShowRolloverNotice(derived)
                ? derived.todayGroupedTaskItems(showRolloverNotice: true)
                : derived.todayEligibleTasks)
            : byDoDateSortedTasks(derived)
        return currentFrozenListGroupSnapshot(for: snapshotTasks)
    }

    private func rollOverPastDoTasks() {
        withAnimation(.easeOut(duration: 0.2)) {
            for task in derivedState.overdoTasks {
                SchedulingActions.rollOverTaskToToday(task, todayKey: todayKey, in: modelContext)
            }
            rolloverNoticeDismissedDate = todayKey
            try? modelContext.save()
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

    private func overdueListsSection(summaries: [TodayOverdueListSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past Due Lists")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.red)
                .kerning(0.8)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(summaries) { summary in
                    TodayOverdueListCard(summary: summary) {
                        openOverdueListSummary(summary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func overdueSectionsSection(summaries: [TodayOverdueSectionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past Due Sections")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.red.opacity(0.9))
                .kerning(0.8)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(summaries) { summary in
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

    /// Today's "by list" organization is a **single, flat tier of list groups** — no
    /// context headers. Group order comes straight out of
    /// `TasksPanelSupport.listGroups`, which orders by `sidebarListOrder`
    /// (Inbox pinned first, then contexts in their sidebar order, and within each
    /// context its areas then its projects in their own order). That keeps the
    /// sequence stable as counts and dates change.
    ///
    /// Scoped to Today only: All Tasks (`.byDoDate`) still renders its own
    /// `byDoDateListSections`, and `AllTasksListView` keeps its context-icon
    /// affordance — neither goes through this path.
    @ViewBuilder
    private func todayListSections(groups: [TodayTaskGroup]) -> some View {
        ForEach(groups) { group in
            VStack(alignment: .leading, spacing: 0) {
                TasksPanelGroupSectionView(
                    group: group,
                    dragOverTaskID: $dragOverTaskID,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    allTasks: allTasks,
                    showsContextIcon: false,
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
                contextIcon: group.contextIcon,
                contextColor: group.contextColor,
                listIcon: group.listIcon,
                listName: group.listName,
                listColor: group.listColor,
                taskIDs: group.tasks.map(\.id)
            )
        }
    }

    /// Currently unreferenced: `hoverFreezeObserver` deliberately passes `flatSectionSnapshot: []`
    /// (see the comment there) so flat/date/priority section trees stay live while hovering.
    /// Kept as the counterpart to `currentFrozenListGroupSnapshot` should that ever change.
    private func currentFrozenFlatSectionSnapshot(derived: TasksPanelDerivedState) -> [FrozenFlatTaskSection] {
        switch mode {
        case .todayOverview:
            let todayTasks = shouldShowRolloverNotice(derived)
                ? derived.todayGroupedTaskItems(showRolloverNotice: true)
                : derived.todayEligibleTasks
            switch activeGroupingMode {
            case .none:
                return [makeFlatSection(id: "today-tasks", title: "Today Tasks", tasks: todayTasks, labelColor: Theme.dim)].compactMap { $0 }
            case .byDate:
                return [
                    makeFlatSection(id: "past-due", title: "Past Due", tasks: derived.overdue, labelColor: Theme.red),
                    makeFlatSection(id: "past-do", title: "Past Do", tasks: derived.overdoTasks, labelColor: Theme.amber),
                    makeFlatSection(id: "due-today", title: "Due Today", tasks: derived.dueTodayTasks, labelColor: Theme.red.opacity(0.85)),
                    makeFlatSection(id: "do-today", title: "Do Today", tasks: derived.doTodayTasks, labelColor: Theme.blue)
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
            let byDoDateSortedTasks = byDoDateSortedTasks(derived)
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
            // The tie-break is the shared one, not a local `order`-then-`title` pair. `order` is
            // assigned per container, so this cross-list view routinely compares tasks with equal
            // `order` — and equal titles are not rare either. Without `createdAt` and `id` behind
            // them the rank ties were an unstable sort.
            return TaskOrdering.fallbackPrecedes(lhs, rhs)
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
