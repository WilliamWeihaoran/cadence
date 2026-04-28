#if os(macOS)
import SwiftUI
import SwiftData

struct ListTasksView: View {
    let tasks: [AppTask]
    var area: Area?
    var project: Project?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.createdAt, order: .reverse) private var allTasks: [AppTask]
    @State private var newTitle = ""
    @State private var selectedSectionName = TaskSectionDefaults.defaultName
    @State private var groupingMode: TaskGroupingMode = .byDate
    @State private var sortField: TaskSortField = .custom
    @State private var sortDirection: TaskSortDirection = .ascending
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenGroupedTasks: [FrozenTaskGroupSnapshot]? = nil
    @State private var dragOverTaskID: UUID? = nil

    private var udKeyPrefix: String {
        if let a = area { return "list_\(a.id.uuidString)" }
        if let p = project { return "list_\(p.id.uuidString)" }
        return "list_generic"
    }
    @FocusState private var addFocused: Bool

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
            let buckets = classifyTasksByDate(activeTasks, todayKey: todayKey)
            let overdue     = activeTasks.filter { buckets.overdueIDs.contains($0.id) }
            let dueToday    = activeTasks.filter { buckets.dueTodayIDs.contains($0.id) }
            let doToday     = activeTasks.filter { buckets.doTodayIDs.contains($0.id) }
            let scheduled   = activeTasks.filter {
                !$0.scheduledDate.isEmpty && $0.scheduledDate != todayKey &&
                !buckets.contains($0)
            }
            let unscheduled = activeTasks.filter {
                $0.scheduledDate.isEmpty &&
                !buckets.contains($0)
            }

            return [
                ListTasksGroup(id: "overdue",    title: "Overdue",    accent: Theme.red,              tasks: overdue),
                ListTasksGroup(id: "due-today",  title: "Due Today",  accent: Theme.red.opacity(0.8), tasks: dueToday),
                ListTasksGroup(id: "do-today",   title: "Do Today",   accent: Theme.blue,             tasks: doToday),
                ListTasksGroup(id: "scheduled",  title: "Scheduled",  accent: Theme.dim,              tasks: scheduled),
                ListTasksGroup(id: "unscheduled",title: "Unscheduled",accent: Theme.amber,            tasks: unscheduled)
            ]
            .filter { !$0.tasks.isEmpty }
        case .byList:
            return sectionNames.compactMap { sectionName in
                let sectionTasks = activeTasks.filter {
                    $0.resolvedSectionName.caseInsensitiveCompare(sectionName) == .orderedSame
                }
                guard !sectionTasks.isEmpty else { return nil }
                return ListTasksGroup(id: "section-\(sectionName.lowercased())", title: sectionName, accent: Theme.blue, tasks: sectionTasks)
            }
        case .byPriority:
            return TaskPriority.allCases.reversed().compactMap { priority in
                let sectionTasks = activeTasks.filter { $0.priority == priority }
                guard !sectionTasks.isEmpty else { return nil }
                return ListTasksGroup(id: "priority-\(priority.rawValue)", title: priority.label, accent: Theme.priorityColor(priority), tasks: sectionTasks)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.blue).font(.system(size: 13))
                TextField("Add a task…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .focused($addFocused)
                    .onSubmit { addTask() }
                TaskSectionPickerBadge(selection: $selectedSectionName, sections: sectionNames)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.surfaceElevated)

            HStack(spacing: 8) {
                CadenceEnumPickerBadge(title: "Sort", selection: $sortField)
                CadenceEnumPickerBadge(title: "Order", selection: $sortDirection)
                CadenceEnumPickerBadge(title: "Group", selection: $groupingMode)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            List {
                if activeTasks.isEmpty && doneTasks.isEmpty {
                    EmptyStateView(message: "No tasks", subtitle: "Add a task above", icon: "checkmark.circle")
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
            .cadenceSoftPageBounce()
            .animation(.easeOut(duration: 0.26), value: activeTasks.map(\.id))
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
            if !sectionNames.contains(where: { $0.caseInsensitiveCompare(selectedSectionName) == .orderedSame }) {
                selectedSectionName = sectionNames.first ?? TaskSectionDefaults.defaultName
            }
            let ud = UserDefaults.standard
            if let raw = ud.string(forKey: "\(udKeyPrefix)_sortField"), let v = TaskSortField(rawValue: raw) { sortField = v }
            if let raw = ud.string(forKey: "\(udKeyPrefix)_sortDir"), let v = TaskSortDirection(rawValue: raw) { sortDirection = v }
            if let raw = ud.string(forKey: "\(udKeyPrefix)_grouping"), let v = TaskGroupingMode(rawValue: raw) { groupingMode = v }
        }
        .onChange(of: sortField) { _, v in UserDefaults.standard.set(v.rawValue, forKey: "\(udKeyPrefix)_sortField") }
        .onChange(of: sortDirection) { _, v in UserDefaults.standard.set(v.rawValue, forKey: "\(udKeyPrefix)_sortDir") }
        .onChange(of: groupingMode) { _, v in UserDefaults.standard.set(v.rawValue, forKey: "\(udKeyPrefix)_grouping") }
        .background {
            TaskGroupFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                frozenGroups: $frozenGroupedTasks,
                naturalTasks: tasks.filter { !$0.isDone && !$0.isCancelled }.taskSorted(by: sortField, direction: sortDirection)
                ,groupSnapshot: groupedActiveTasks.map { group in
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

    private func addTask() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let task = AppTask(title: t)
        task.area = area
        task.project = project
        task.context = area?.context ?? project?.context
        task.sectionName = selectedSectionName
        task.order = tasks.count
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
