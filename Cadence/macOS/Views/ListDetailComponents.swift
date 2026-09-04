#if os(macOS)
import SwiftUI
import SwiftData

struct ListTasksView: View {
    let tasks: [AppTask]
    var area: Area?
    var project: Project?
    let sortField: TaskSortField
    let sortDirection: TaskSortDirection
    let groupingMode: TaskGroupingMode

    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.createdAt, order: .reverse) private var allTasks: [AppTask]
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenGroupedTasks: [FrozenTaskGroupSnapshot]? = nil
    @State private var dragOverTaskID: UUID? = nil
    /// Set when the store refused a row drop (T-869). The rows are already back where they were by
    /// then, so this tab and this sentence agree.
    @State private var reorderFailureNotice: String? = nil

    private var activeTasks: [AppTask] {
        let sorted = CadenceTaskQuerySupport.openTasks(from: tasks).taskSorted(by: sortField, direction: sortDirection)
        return applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }
    /// See `TasksListView.completedTasks`: the **desktop** tier, which
    /// `CadenceTaskSurfaceOptions` leaves uncapped, asked rather than assumed (T-290).
    private var doneTasks: [AppTask] {
        CadenceTaskSurfaceOptions.completedRows(
            from: tasks.filter { $0.isDone || $0.isCancelled }.taskCompletionSorted(),
            tier: .desktop
        )
    }

    /// What a list's own Tasks tab offers, from the shared table.
    private var options: CadenceTaskViewOptions {
        CadenceTaskSurfaceOptions.options(for: .listDetail)
    }
    private var sectionNames: [String] { area?.sectionNames ?? project?.sectionNames ?? [TaskSectionDefaults.defaultName] }
    private var todayKey: String { DateFormatters.todayKey() }

    private var groupedActiveTasks: [ListTasksGroup] {
        if let frozenGroupedTasks = resolveFrozenTaskGroups(frozenGroupedTasks, from: tasks) {
            return frozenGroupedTasks.map { group in
                ListTasksGroup(id: group.id, title: group.title, accent: group.accent, tasks: group.tasks)
            }
        }

        switch groupingMode {
        case .none:
            return [
                ListTasksGroup(id: "all", title: "Tasks", accent: Theme.dim, tasks: activeTasks)
            ]
        case .byDate:
            return CadenceTaskQuerySupport.dateDisplayGroups(from: activeTasks, todayKey: todayKey)
                .map { ListTasksGroup(id: $0.id, title: $0.title, accent: $0.accent, tasks: $0.tasks) }
        case .byList:
            return CadenceTaskQuerySupport.sectionGroups(from: activeTasks, sectionNames: sectionNames)
                .map { ListTasksGroup(id: $0.id, title: $0.title, accent: $0.accent, tasks: $0.tasks) }
        case .byPriority:
            return CadenceTaskQuerySupport.priorityDisplayGroups(from: activeTasks)
                .map { ListTasksGroup(id: $0.id, title: $0.title, accent: $0.accent, tasks: $0.tasks) }
        }
    }

    var body: some View {
        List {
            if let reorderFailureNotice {
                CadenceInlineFailureNotice(text: reorderFailureNotice)
                    .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
                    .padding(.top, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
            }
            if activeTasks.isEmpty && doneTasks.isEmpty {
                // The subtitle is the shared one because this page and `iOSListDetailView` are one
                // page at two widths, and because the copy that was here — "Create a task to get
                // started" — is a string T-285 retired from the Mac's task page and pinned only
                // against `TasksListView.swift`, which is how it survived in this file.
                EmptyStateView(
                    message: CadenceEmptyStateCopy.listDetailTitle,
                    subtitle: CadenceEmptyStateCopy.listDetailSubtitle,
                    icon: "checkmark.circle"
                )
                .padding(.top, 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(groupedActiveTasks) { group in
                ListTasksGroupSectionView(
                    group: group,
                    isCollapsed: collapsedGroupIDs.contains(group.id),
                    overdueCount: overdueCount(in: group.tasks),
                    regularCount: regularCount(in: group.tasks),
                    allTasks: allTasks,
                    dragOverTaskID: $dragOverTaskID,
                    onToggle: { toggleGroup(group.id) },
                    onReorderTask: reorderTask
                )
            }

            if options.showsCompletedToggle, !doneTasks.isEmpty {
                ListTasksCompletedSectionView(
                    tasks: doneTasks,
                    allTasks: allTasks,
                    isCollapsed: isCompletedCollapsed,
                    onToggle: { isCompletedCollapsed.toggle() }
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Keeps the last row reachable from under the floating "+".
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .cadenceSoftPageBounce()
        .animation(.easeOut(duration: 0.26), value: activeTasks.map(\.id))
        .floatingNewTaskButton {
            taskCreationManager.present(
                container: taskContainerSelection,
                sectionName: sectionNames.first ?? TaskSectionDefaults.defaultName
            )
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
        .background(Theme.bg)
        .onAppear {
            isCompletedCollapsed = true
        }
        .background {
            TaskGroupFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                frozenGroups: $frozenGroupedTasks,
                naturalTasks: tasks.filter { !$0.isDone && !$0.isCancelled }.taskSorted(by: sortField, direction: sortDirection),
                // Intentional: only freeze the group snapshot for byList (section) grouping.
                // Date/priority section trees must stay live while hovering — capturing those
                // snapshots swaps the row tree under the pointer and causes visible jitter.
                // Row order is still preserved separately via frozenTaskOrder.
                groupSnapshot: groupingMode == .byList
                    ? groupedActiveTasks.map { group in
                        FrozenTaskGroupSnapshot(
                            id: group.id,
                            title: group.title,
                            accent: group.accent,
                            taskIDs: group.tasks.map(\.id)
                        )
                    }
                    : []
            )
        }
    }

    private var taskContainerSelection: TaskContainerSelection {
        if let area {
            return .area(area.id)
        }
        if let project {
            return .project(project.id)
        }
        return .inbox
    }

    /// Drag a row into a new place on a list's own Tasks tab.
    ///
    /// **It reached no commit at all until T-869** — this whole file contained no `save()` — and the
    /// row nevertheless stayed where it was dropped until the next launch put it back. That is the
    /// failure T-614's rule is about, and it was invisible to `CadenceSaveCommitDisciplineTests`
    /// because there was no swallowed commit in the frame for half 2 to hang the rule on and no
    /// insert or delete for half 3 to see.
    ///
    /// **It renumbers the *displayed* order, not the stored one**, which is why it does not call
    /// `TasksPanelSupport.reorderTask`: `activeTasks` is sorted by the tab's active sort and its
    /// hover freeze, and writing that arrangement back is what makes a drag under a non-`order`
    /// sort mean anything here. The two surfaces disagree about which sequence a drag rewrites;
    /// they now agree about committing it, which is the part this ticket is about.
    ///
    /// - Returns: Whether the new order is in the store, so the row springs back on a refusal
    ///   rather than sitting in a place nothing holds.
    private func reorderTask(droppedID: UUID, targetID: UUID) -> Bool {
        var sorted = activeTasks
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return false }
        let element = sorted.remove(at: fromIndex)
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        let reordered = withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            CadenceOrderCommit.commit(
                sorted,
                readOrder: { $0.order },
                writeOrder: { $0.order = $1 },
                in: modelContext
            )
        }
        reorderFailureNotice = reordered ? nil : CadenceOrderCommit.failureNotice
        return reordered
    }

    private func toggleGroup(_ id: String) {
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
    }

    // Forwards to `TasksPanelSupport`, the same counts Today and All Tasks show. This file used to
    // carry its own bodies, and they had drifted: neither excluded completed tasks, so a finished
    // task with a past due date was counted as overdue here and not on the other two screens — the
    // same list reporting two different numbers depending on which screen you were on. It is
    // reachable in normal use because the hover-freeze snapshot keeps a just-completed task in its
    // group for a moment after you tick it.
    private func overdueCount(in tasks: [AppTask]) -> Int? {
        TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey)
    }

    private func regularCount(in tasks: [AppTask]) -> Int {
        TasksPanelSupport.regularCount(in: tasks, todayKey: todayKey)
    }
}
#endif
