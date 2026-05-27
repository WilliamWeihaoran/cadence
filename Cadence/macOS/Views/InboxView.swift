#if os(macOS)
import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var newTitle = ""
    @State private var isCompletedCollapsed = true
    @AppStorage("inboxSortField") private var sortField: TaskSortField = .custom
    @AppStorage("inboxSortDirection") private var sortDirection: TaskSortDirection = .ascending
    @AppStorage("inboxGroupingMode") private var groupingMode: TaskGroupingMode = .none
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenGroups: [FrozenTaskGroupSnapshot]? = nil
    @State private var dragOverTaskID: UUID? = nil
    @FocusState private var captureFocused: Bool

    private var inboxTasks: [AppTask] {
        allTasks.filter { $0.area == nil && $0.project == nil && !$0.isCancelled }
    }
    private var activeTasks: [AppTask] {
        let sorted = inboxTasks.filter { !$0.isDone }.taskSorted(by: sortField, direction: sortDirection)
        return applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }
    private var doneTasks: [AppTask] { inboxTasks.filter { $0.isDone || $0.isCancelled }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
    private var groupedActiveTasks: [InboxTaskGroup] {
        if let frozenGroups = resolveFrozenTaskGroups(frozenGroups, from: allTasks) {
            return frozenGroups.map { group in
                InboxTaskGroup(id: group.id, title: group.title, tasks: group.tasks, color: group.accent)
            }
        }
        let todayKey = DateFormatters.todayKey()
        switch groupingMode {
        case .none:
            return [InboxTaskGroup(id: "all", title: "Tasks", tasks: activeTasks, color: Theme.dim)]
        case .byDate:
            return CadenceTaskQuerySupport.dateDisplayGroups(from: activeTasks, todayKey: todayKey)
                .map { InboxTaskGroup(id: $0.id, title: $0.title, tasks: $0.tasks, color: $0.accent) }
        case .byList:
            return [InboxTaskGroup(id: "inbox", title: "Inbox", tasks: activeTasks, color: Theme.dim)]
        case .byPriority:
            return CadenceTaskQuerySupport.priorityDisplayGroups(from: activeTasks)
                .map { InboxTaskGroup(id: $0.id, title: $0.title, tasks: $0.tasks, color: $0.accent) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            InboxHeaderView(activeTaskCount: activeTasks.count) {
                taskCreationManager.present()
            }
            Divider().background(Theme.borderSubtle)
            InboxCaptureBarView(newTitle: $newTitle, isFocused: $captureFocused) {
                captureTask()
            }
            Divider().background(Theme.borderSubtle)
            InboxControlsBarView(sortField: $sortField, sortDirection: $sortDirection, groupingMode: $groupingMode)
            Divider().background(Theme.borderSubtle)

            if activeTasks.isEmpty && doneTasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedActiveTasks) { group in
                        InboxTaskGroupSectionView(
                            group: group,
                            contexts: contexts,
                            areas: areas,
                            projects: projects,
                            allTasks: allTasks,
                            dragOverTaskID: $dragOverTaskID,
                            onReorderTask: reorderTask
                        )
                    }

                    if !doneTasks.isEmpty {
                        InboxCompletedSectionView(
                            tasks: doneTasks,
                            contexts: contexts,
                            areas: areas,
                            projects: projects,
                            allTasks: allTasks,
                            isCollapsed: isCompletedCollapsed,
                            onToggle: { isCompletedCollapsed.toggle() }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .cadenceSoftPageBounce()
                .background(Theme.bg)
                .animation(.easeOut(duration: 0.26), value: activeTasks.map(\.id))
            }
        }
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
        )
        .background(Theme.bg)
        .onAppear {
            isCompletedCollapsed = true
        }
        .background {
            TaskGroupFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                frozenGroups: $frozenGroups,
                naturalTasks: inboxTasks.filter { !$0.isDone }.taskSorted(by: sortField, direction: sortDirection),
                groupSnapshot: groupedActiveTasks.map {
                    FrozenTaskGroupSnapshot(id: $0.id, title: $0.title, accent: $0.color, taskIDs: $0.tasks.map(\.id))
                }
            )
        }
    }

    private var emptyState: some View {
        InboxEmptyStateView(captureFocused: $captureFocused)
    }

    // MARK: - Actions

    private func captureTask() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let task = AppTask(title: t)
        task.order = activeTasks.count
        modelContext.insert(task)
        newTitle = ""
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

}

#endif
