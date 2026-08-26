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

        todayIntentSections(derived: derived, showsRollover: showsRollover)
    }

    /// Today's groups, and the whole of them: Overdue, Past Do, Due Today, Planned Today.
    ///
    /// **The buckets come from `CadenceTaskQuerySupport.todayGroups`** — the shared function both
    /// iOS Todays already called — rather than from a fourth macOS re-derivation of the same four
    /// predicates. `todayDateSections` was that re-derivation, spelling the same buckets "Past Due"
    /// and "Do Today", and it sat behind a Group picker that also offered by-list and by-priority
    /// while Today defaulted to by-list. A day's page groups by *why*, so there is nothing left for
    /// the picker to choose between and Today no longer draws one; sort and order still apply, and
    /// they apply *inside* each group.
    ///
    /// The rollover banner still withholds the over-do tasks it is offering to roll, so `.pastDo`
    /// is simply empty while the banner is up and `todayGroups` drops it.
    @ViewBuilder
    private func todayIntentSections(derived: TasksPanelDerivedState, showsRollover: Bool) -> some View {
        let tasks = applyFreeze(
            derived.todayGroupedTaskItems(showRolloverNotice: showsRollover)
                .sorted(by: compareTasksForCurrentSort)
        )

        ForEach(CadenceTaskQuerySupport.todayGroups(from: tasks, todayKey: todayKey)) { group in
            let dropKey = CadenceTaskDropSupport.dropKey(forGroup: .todayDate(group.kind))

            TasksPanelIntentSectionView(
                title: group.title,
                accent: CadenceTodayPresentationSupport.accent(for: group.kind),
                tasks: group.tasks,
                showsContainer: options.showsContainerChip,
                contexts: contexts,
                areas: areas,
                projects: projects,
                isCollapsed: collapsedGroupIDs.contains(intentGroupID(group.kind)),
                dragOverTaskID: $dragOverTaskID,
                onToggle: { toggleGroup(intentGroupID(group.kind)) },
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

    private func intentGroupID(_ kind: CadenceTodayTaskGroupKind) -> String {
        "today-intent-\(kind.rawValue)"
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
                message: mode == .byDoDate ? "No tasks yet" : CadenceTodayPresentationSupport.emptyTitle,
                subtitle: mode == .byDoDate ? "Add a task above to get started" : CadenceTodayPresentationSupport.emptySubtitle,
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

    /// List-group snapshots are a `.byDoDate` concern only: Today groups by intent and has no
    /// by-list mode to freeze. `frozenTaskOrder` still holds the row order steady under the
    /// pointer on both, which is what the freeze is for.
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
            // No grouping control on Today. Its sections are the day's four intents — see
            // `todayIntentSections` — and a picker offering "by list" beside them would be
            // offering to answer a different question than the page asks. It used to exclude
            // `.byDate` here for the mirror-image reason: Today's by-date grouping *was* the
            // intent grouping, spelled differently and reachable only by not choosing it.
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
            // Today has one grouping — the day's four intents — so there is no switch here any
            // more. The buckets are `CadenceTaskQuerySupport.todayGroups`', the same ones
            // `todayIntentSections` draws, rather than a second list of the same predicates under
            // the names "Past Due" and "Do Today".
            let todayTasks = applyFreeze(
                derived.todayGroupedTaskItems(showRolloverNotice: shouldShowRolloverNotice(derived))
                    .sorted(by: compareTasksForCurrentSort)
            )
            return CadenceTaskQuerySupport.todayGroups(from: todayTasks, todayKey: todayKey).compactMap { group in
                makeFlatSection(
                    id: intentGroupID(group.kind),
                    title: group.title,
                    tasks: group.tasks,
                    dropKey: CadenceTaskDropSupport.dropKey(forGroup: .todayDate(group.kind))
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
