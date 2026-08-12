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
    @Query(sort: \AppTask.createdAt, order: .reverse) private var allTasks: [AppTask]
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenGroupedTasks: [FrozenTaskGroupSnapshot]? = nil
    @State private var dragOverTaskID: UUID? = nil

    private var activeTasks: [AppTask] {
        let sorted = CadenceTaskQuerySupport.openTasks(from: tasks).taskSorted(by: sortField, direction: sortDirection)
        return applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }
    private var doneTasks: [AppTask] { tasks.filter { $0.isDone || $0.isCancelled }.taskCompletionSorted() }
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
            if activeTasks.isEmpty && doneTasks.isEmpty {
                EmptyStateView(message: "No tasks", subtitle: "Create a task to get started", icon: "checkmark.circle")
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

            if !doneTasks.isEmpty {
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

    private func reorderTask(droppedID: UUID, targetID: UUID) {
        var sorted = activeTasks
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (i, t) in sorted.enumerated() { t.order = i }
        }
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
