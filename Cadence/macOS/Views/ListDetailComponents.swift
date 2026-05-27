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
        let sorted = tasks.filter { !$0.isDone && !$0.isCancelled }.taskSorted(by: sortField, direction: sortDirection)
        return applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }
    private var doneTasks: [AppTask] { tasks.filter { $0.isDone || $0.isCancelled }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
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
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
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
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 72)
                }
                .cadenceSoftPageBounce()
                .animation(.easeOut(duration: 0.26), value: activeTasks.map(\.id))
            }

            Button {
                taskCreationManager.present(
                    container: taskContainerSelection,
                    sectionName: sectionNames.first ?? TaskSectionDefaults.defaultName
                )
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Theme.blue)
                    .clipShape(Circle())
                    .shadow(color: Theme.blue.opacity(0.32), radius: 18, x: 0, y: 8)
            }
            .buttonStyle(.cadencePlain)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
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
                groupSnapshot: groupedActiveTasks.map { group in
                    FrozenTaskGroupSnapshot(
                        id: group.id,
                        title: group.title,
                        accent: group.accent,
                        taskIDs: group.tasks.map(\.id)
                    )
                }
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

    private func overdueCount(in tasks: [AppTask]) -> Int? {
        let count = tasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }.count
        return count > 0 ? count : nil
    }

    private func regularCount(in tasks: [AppTask]) -> Int {
        tasks.count - (overdueCount(in: tasks) ?? 0)
    }
}
#endif
