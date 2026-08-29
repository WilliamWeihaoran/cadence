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
    @AppStorage(CadenceTodayRolloverSupport.dismissedDateStorageKey) private var rolloverNoticeDismissedDate = ""
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

    /// Which `CadenceTaskSurface` this panel is drawing, so the chrome answers come from the
    /// shared table rather than from four inline decisions (T-290). Today's panel is `.today`; the
    /// `.byDoDate` mode is the All Tasks shape of the same panel.
    private var surface: CadenceTaskSurface {
        mode == .todayOverview ? .today : .allTasks
    }

    /// See `surface`. Read for the sort chips, the Completed section, and whether a row names its
    /// list — the three things this panel used to answer for itself.
    private var options: CadenceTaskViewOptions {
        CadenceTaskSurfaceOptions.options(for: surface)
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

    /// The `mode` clause is this surface's own — `TasksPanel` also draws All Tasks, which has no
    /// Today and therefore no rollover. Everything after it is
    /// `CadenceTodayRolloverSupport.isNoticeVisible`, the same predicate iOS's Today asks.
    private func shouldShowRolloverNotice(_ derived: TasksPanelDerivedState) -> Bool {
        mode == .todayOverview && CadenceTodayRolloverSupport.isNoticeVisible(
            pastDoTaskCount: derived.overdoTasks.count,
            dismissedDateKey: rolloverNoticeDismissedDate,
            todayKey: todayKey
        )
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

    /// T-342 reached here too. These two resolvers are hand-rolled copies of
    /// `resolveFrozenTaskGroups` — same snapshot-rehydration shape, different result type — and they
    /// carried the same half-rule: a task **cancelled** while the panel was frozen is not `isDone`,
    /// so it stayed pinned in an active frozen group until the freeze released, while a task
    /// completed beside it left at once. `isFinishedTask` is the whole rule, and the audit's "two
    /// places" was really four.
    private var resolvedFrozenListGroups: [TodayTaskGroup]? {
        guard let frozenListGroups else { return nil }
        let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        return frozenListGroups.compactMap { group in
            let resolvedTasks = group.taskIDs
                .compactMap { tasksByID[$0] }
                .filter { !CadenceTaskQuerySupport.isFinishedTask($0) }
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
            let resolvedTasks = section.taskIDs
                .compactMap { tasksByID[$0] }
                .filter { !CadenceTaskQuerySupport.isFinishedTask($0) }
            guard !resolvedTasks.isEmpty else { return nil }
            return FrozenFlatTaskSection(
                id: section.id,
                title: section.title,
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
                headerSection(derived: derived)
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

    private func headerSection(derived: TasksPanelDerivedState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TasksPanelHeader(mode: mode, summary: todaySummary(derived: derived))
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
            CadenceTodayRolloverBanner(tasks: derived.overdoTasks, style: .panelBand) {
                rollOverPastDoTasks()
            }
        }
        if !derived.overdueListSummaries.isEmpty {
            overdueListsSection(summaries: derived.overdueListSummaries)
        }
        if !derived.overdueSectionSummaries.isEmpty {
            overdueSectionsSection(summaries: derived.overdueSectionSummaries)
        }

        todayGroupSections(derived: derived, showsRollover: showsRollover)
    }

    /// Today's groups, and the whole of them: **Overdue, then the day's work by list** (T-305).
    ///
    /// They come from `CadenceTaskQuerySupport.todayGroups`, the shared function both iOS Todays
    /// already called, so the page's shape is decided once for both platforms. It used to be four
    /// date buckets — Overdue, Past Do, Due Today, Planned Today; the last of those restated the
    /// page, and Today was the app's only task surface not grouped by list. What the date axis is
    /// still worth is inside each group: `compareTasksForCurrentSort` leads with
    /// `todayTaskSortRank`, so a list reads past-do, then due-today, then do-today without four
    /// headings to say so.
    ///
    /// One section component for both kinds of group, because a group is a group: what changes is
    /// the tint (the list's own colour, or Overdue's red), whether the rows still name their list
    /// (`showsContainerChip` — off under a header that already prints the name), and whether the
    /// header accepts a dropped `+`.
    ///
    /// The rollover banner still withholds the over-do tasks it is offering to roll. Those rows are
    /// now missing from *their lists'* groups rather than from a "Past Do" section, which is what
    /// makes confirming the roll do something visible.
    @ViewBuilder
    private func todayGroupSections(derived: TasksPanelDerivedState, showsRollover: Bool) -> some View {
        let tasks = applyFreeze(
            derived.todayGroupedTaskItems(showRolloverNotice: showsRollover)
                .sorted(by: compareTasksForCurrentSort)
        )

        ForEach(CadenceTaskQuerySupport.todayGroups(from: tasks, todayKey: todayKey, contexts: contexts)) { group in
            let dropKey = CadenceTaskDropSupport.dropKey(forGroup: group.dropIdentity)

            TasksPanelIntentSectionView(
                title: group.title,
                accent: group.accent,
                tasks: group.tasks,
                showsContainer: options.showsContainerChip && group.showsContainerChip,
                contexts: contexts,
                areas: areas,
                projects: projects,
                isCollapsed: collapsedGroupIDs.contains(group.id),
                dragOverTaskID: $dragOverTaskID,
                onToggle: { toggleGroup(group.id) },
                taskDragPayload: taskDragPayload,
                onDropOnSectionPayload: dropCoordinator.sectionDropHandler(for: dropKey),
                onDropOnTaskPayload: { payload, targetTask in
                    dropCoordinator.handleTaskDrop(
                        payload: payload,
                        targetTask: targetTask,
                        scopeTasks: group.tasks,
                        dropKey: dropKey
                    )
                }
            )
        }
    }

    private func todaySummary(derived: TasksPanelDerivedState) -> CadenceTodaySummary? {
        guard mode == .todayOverview else { return nil }
        return CadenceTodayPresentationSupport.summary(
            activeTasks: derived.todayEligibleTasks,
            timedTasks: CadenceScheduleSupport.scheduledTasks(
                on: todayKey,
                from: allTasks,
                includeCompleted: false,
                excludeBundled: false
            )
            .filter { $0.scheduledStartMin >= 0 },
            completedTasks: derived.doneTasks
        )
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
                tasks: sortedTasks
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
            liveFlatSection(label: "Do Today", tasks: todayTasks, dropKey: "date:today")
        }
        if !upcomingTasks.isEmpty {
            liveFlatSection(label: "Scheduled", tasks: upcomingTasks, dropKey: "date:scheduled")
        }
        if !unscheduledTasks.isEmpty {
            liveFlatSection(label: "Unscheduled", tasks: unscheduledTasks, dropKey: "date:unscheduled")
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
        tasks: [AppTask]
    ) -> some View {
        if let frozenSections {
            frozenFlatSections(frozenSections, tasksByID: tasksByID)
        } else if !tasks.isEmpty {
            liveFlatSection(label: label, tasks: tasks)
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
                        dropKey: "priority:\(priority.rawValue)"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func completedSection(derived: TasksPanelDerivedState) -> some View {
        if options.showsCompletedToggle, !derived.doneTasks.isEmpty {
            TasksPanelCompletedSectionView(
                // The **desktop** tier, which `CadenceTaskSurfaceOptions` leaves uncapped — the
                // reasoning is in that file. Asked rather than assumed: the panel's own
                // `doneTasks` stays whole because `CadenceTodaySummary.completedCount` and
                // `isEmptyState` both count it, and a cap applied there would be a wrong number
                // rather than a shorter list.
                tasks: CadenceTaskSurfaceOptions.completedRows(from: derived.doneTasks, tier: .desktop),
                showsContainer: options.showsContainerChip,
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
            // Today's copy is `CadenceTodayPresentationSupport`'s, which is what iOS's
            // `iOSCompactTodayEmptyState` draws. macOS said "Nothing for today" over
            // "Due-today and do-today tasks will appear here" — a restatement of the page's scope
            // where the shared subtitle names the next thing to do.
            EmptyStateView(
                // `.byDoDate` is the All Tasks shape of this panel, so it says what the All Tasks
                // page says. It used to spell "No tasks yet" / "Add a task above to get started"
                // inline: the first is a string T-285 retired, and the second names a field that
                // does not exist — this panel's affordance is the `+` glyph on its own header
                // (`TasksPanelSupportViews`).
                message: mode == .byDoDate ? CadenceEmptyStateCopy.allTasksTitle : CadenceTodayPresentationSupport.emptyTitle,
                subtitle: mode == .byDoDate ? CadenceEmptyStateCopy.allTasksSubtitle : CadenceTodayPresentationSupport.emptySubtitle,
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

    /// List-group snapshots are a `.byDoDate` concern only. Today groups by list too now, but it
    /// draws its groups through `TasksPanelIntentSectionView` rather than `TodayTaskGroup`, so
    /// there is no `FrozenTodayTaskGroup` for it to snapshot. `frozenTaskOrder` still holds the row
    /// order steady under the pointer on both, which is what the freeze is for.
    private func currentFrozenListSnapshotForHover(_ derived: TasksPanelDerivedState) -> [FrozenTodayTaskGroup] {
        guard mode == .byDoDate, activeGroupingMode == .byList else { return [] }
        return currentFrozenListGroupSnapshot(for: byDoDateSortedTasks(derived))
    }

    private func rollOverPastDoTasks() {
        withAnimation(.easeOut(duration: 0.2)) {
            rolloverNoticeDismissedDate = CadenceTodayRolloverSupport.rollOver(
                derivedState.overdoTasks,
                todayKey: todayKey,
                modelContext: modelContext
            )
        }
    }

    @ViewBuilder
    private func liveFlatSection(label: String, tasks: [AppTask], dropKey: String? = nil) -> some View {
        TasksPanelFlatSectionView(
            label: label,
            tasks: tasks,
            showsContainer: options.showsContainerChip,
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
        liveFlatSection(label: section.title, tasks: sectionTasks, dropKey: section.dropKey)
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            if options.showsSort {
                CadenceEnumPickerBadge(title: "Sort", selection: $localSortField)
                CadenceEnumPickerBadge(title: "Order", selection: $localSortDirection)
            }
            // No grouping control on Today. Its sections are Overdue and then the day's lists —
            // see `todayGroupSections` — which is the one grouping the page has, so there is
            // nothing for a picker to choose between. `_localGroupingMode` still falls back to
            // `.byList` for this mode, which is now a description of what Today actually does
            // rather than a mode it declines to use.
            if mode != .todayOverview {
                CadenceEnumPickerBadge(title: "Group", selection: $localGroupingMode)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Theme.surface)
    }

    private func overdueListsSection(summaries: [CadenceTodayOverdueListSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            overdueSectionHeading(CadenceTodayOverdueSummarySupport.listsHeading, count: summaries.count)

            VStack(spacing: 8) {
                ForEach(summaries) { summary in
                    CadenceTodayOverdueListCard(summary: summary) {
                        openOverdueListSummary(summary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func overdueSectionsSection(summaries: [CadenceTodayOverdueSectionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            overdueSectionHeading(CadenceTodayOverdueSummarySupport.sectionsHeading, count: summaries.count)

            VStack(spacing: 8) {
                ForEach(summaries) { summary in
                    CadenceTodayOverdueSectionCard(summary: summary) {
                        openOverdueSectionSummary(summary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    /// The shared heading, with this column's own gutter. Neutral rather than `Theme.red` — see
    /// `CadenceTodayOverdueSummaryHeading`, which iOS's Today draws too.
    private func overdueSectionHeading(_ title: String, count: Int) -> some View {
        CadenceTodayOverdueSummaryHeading(title: title, count: count)
            .padding(.horizontal, 16)
    }

    // MARK: - Grouping

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
        dropKey: String? = nil
    ) -> FrozenFlatTaskSection? {
        guard !tasks.isEmpty else { return nil }
        return TasksPanelSupport.makeFlatSection(
            id: id,
            title: title,
            tasks: tasks,
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
            // Today has one grouping — Overdue, then by list — so there is no switch here any
            // more. The groups are `CadenceTaskQuerySupport.todayGroups`', the same ones
            // `todayGroupSections` draws, rather than a second list of the same predicates under
            // names of their own.
            let todayTasks = applyFreeze(
                derived.todayGroupedTaskItems(showRolloverNotice: shouldShowRolloverNotice(derived))
                    .sorted(by: compareTasksForCurrentSort)
            )
            let groups = CadenceTaskQuerySupport.todayGroups(from: todayTasks, todayKey: todayKey, contexts: contexts)
            return groups.compactMap { group in
                makeFlatSection(
                    id: group.id,
                    title: group.title,
                    tasks: group.tasks,
                    dropKey: CadenceTaskDropSupport.dropKey(forGroup: group.dropIdentity)
                )
            }
        case .byDoDate:
            let todayK = todayKey
            let byDoDateSortedTasks = byDoDateSortedTasks(derived)
            switch activeGroupingMode {
            case .none:
                return [makeFlatSection(id: "tasks", title: "Tasks", tasks: byDoDateSortedTasks)].compactMap { $0 }
            case .byDate:
                let todayTasks = byDoDateSortedTasks.filter { $0.scheduledDate == todayK }
                let upcomingTasks = byDoDateSortedTasks.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayK }
                let unscheduledTasks = byDoDateSortedTasks.filter { taskIsUnscheduled($0) }
                return [
                    makeFlatSection(id: "do-today", title: "Do Today", tasks: todayTasks, dropKey: "date:today"),
                    makeFlatSection(id: "scheduled", title: "Scheduled", tasks: upcomingTasks, dropKey: "date:scheduled"),
                    makeFlatSection(id: "unscheduled", title: "Unscheduled", tasks: unscheduledTasks, dropKey: "date:unscheduled")
                ].compactMap { $0 }
            case .byList:
                return []
            case .byPriority:
                return TaskPriority.allCases.reversed().compactMap { priority in
                    makeFlatSection(
                        id: "priority-\(priority.rawValue)",
                        title: priority.label,
                        tasks: byDoDateSortedTasks.filter { $0.priority == priority },
                        dropKey: "priority:\(priority.rawValue)"
                    )
                }
            }
        }
    }

    /// **Today ranks by urgency first, then by whatever the Sort chips say** — and the `!enableControls`
    /// half of this condition is gone (T-305).
    ///
    /// It used to read `mode == .todayOverview && !enableControls`, and the only `TasksPanel` that
    /// is a Today (`TodayView`) passes `enableControls: true`, so the rank never ran: macOS Today
    /// sorted purely by the Sort/Order chips. That was invisible while the page was *grouped* by
    /// the same four date states — the headings carried the urgency the sort had dropped. Grouping
    /// by list takes the headings away, and with them the only thing keeping a due-today task with
    /// no do date off the bottom of its list, where `.date` ascending files an empty
    /// `scheduledDate`.
    ///
    /// So the rank leads, exactly as iOS's `sortTodayTasks` has always had it, and the user's
    /// chosen field and direction order the rows *inside* each rank. `.byDoDate` — All Tasks — is
    /// untouched and still sorts purely by the chips.
    private func compareTasksForCurrentSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        if mode == .todayOverview {
            let leftRank = todayTaskSortRank(lhs)
            let rightRank = todayTaskSortRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return taskSortPrecedes(lhs, rhs, field: activeSortField, direction: activeSortDirection)
        }

        return taskSortPrecedes(lhs, rhs, field: activeSortField, direction: activeSortDirection)
    }

    /// `CadenceTaskQuerySupport.todayRank`, not a local copy of it. The copy that used to live here
    /// tested `scheduledDate < todayKey` *before* `dueDate == todayKey`, which is the opposite of
    /// what every other Today rule does — see that function for what the disagreement cost.
    private func todayTaskSortRank(_ task: AppTask) -> Int {
        CadenceTaskQuerySupport.todayRank(task, todayKey: todayKey)
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

    private func openOverdueListSummary(_ summary: CadenceTodayOverdueListSummary) {
        TasksPanelSupport.openOverdueListSummary(summary, listNavigationManager: listNavigationManager)
    }

    private func openOverdueSectionSummary(_ summary: CadenceTodayOverdueSectionSummary) {
        TasksPanelSupport.openOverdueSectionSummary(summary, listNavigationManager: listNavigationManager)
    }


    private func taskDragPayload(for task: AppTask) -> String {
        TasksPanelSupport.taskDragPayload(for: task)
    }
}

#endif
