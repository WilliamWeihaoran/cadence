#if os(macOS)
import SwiftUI
import SwiftData

struct ListTasksView: View {
    private struct TaskGroup: Identifiable {
        let id: String
        let title: String
        let accent: Color
        let tasks: [AppTask]
    }

    struct FrozenTaskGroup {
        let id: String
        let title: String
        let accent: Color
        let taskIDs: [UUID]
    }

    let tasks: [AppTask]
    var area: Area?
    var project: Project?
    @Environment(\.modelContext) private var modelContext
    @State private var newTitle = ""
    @State private var selectedSectionName = TaskSectionDefaults.defaultName
    @State private var groupingMode: TaskGroupingMode = .byDate
    @State private var sortField: TaskSortField = .custom
    @State private var sortDirection: TaskSortDirection = .ascending
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var frozenGroupedTasks: [FrozenTaskGroup]? = nil
    @State private var dragOverTaskID: UUID? = nil

    private var udKeyPrefix: String {
        if let a = area { return "list_\(a.id.uuidString)" }
        if let p = project { return "list_\(p.id.uuidString)" }
        return "list_generic"
    }
    @FocusState private var addFocused: Bool

    private var activeTasks: [AppTask] {
        let sorted = tasks.filter { !$0.isDone && !$0.isCancelled }.taskSorted(by: sortField, direction: sortDirection)
        guard let frozen = frozenTaskOrder else { return sorted }
        let activeFrozen = frozen.filter { !$0.isDone }
        let frozenIDs = Set(activeFrozen.map(\.id))
        return activeFrozen + sorted.filter { !frozenIDs.contains($0.id) }
    }
    private var doneTasks: [AppTask] { tasks.filter { $0.isDone || $0.isCancelled }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
    private var sectionNames: [String] { area?.sectionNames ?? project?.sectionNames ?? [TaskSectionDefaults.defaultName] }
    private var todayKey: String { DateFormatters.todayKey() }

    private var groupedActiveTasks: [TaskGroup] {
        if let frozenGroupedTasks {
            let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            return frozenGroupedTasks.compactMap { group in
                let resolvedTasks = group.taskIDs.compactMap { tasksByID[$0] }.filter { !$0.isDone }
                guard !resolvedTasks.isEmpty else { return nil }
                return TaskGroup(id: group.id, title: group.title, accent: group.accent, tasks: resolvedTasks)
            }
        }

        switch groupingMode {
        case .none:
            return [
                TaskGroup(id: "all", title: "Tasks", accent: Theme.dim, tasks: activeTasks)
            ]
        case .byDate:
            var overdueIDs = Set<UUID>()
            var dueTodayIDs = Set<UUID>()
            var doTodayIDs = Set<UUID>()

            for task in activeTasks {
                if !task.dueDate.isEmpty && task.dueDate < todayKey {
                    overdueIDs.insert(task.id)
                } else if task.dueDate == todayKey {
                    dueTodayIDs.insert(task.id)
                }
            }
            for task in activeTasks where !overdueIDs.contains(task.id) && !dueTodayIDs.contains(task.id) {
                if task.scheduledDate == todayKey { doTodayIDs.insert(task.id) }
            }

            let overdue     = activeTasks.filter { overdueIDs.contains($0.id) }
            let dueToday    = activeTasks.filter { dueTodayIDs.contains($0.id) }
            let doToday     = activeTasks.filter { doTodayIDs.contains($0.id) }
            let scheduled   = activeTasks.filter {
                !$0.scheduledDate.isEmpty && $0.scheduledDate != todayKey &&
                !overdueIDs.contains($0.id) && !dueTodayIDs.contains($0.id) && !doTodayIDs.contains($0.id)
            }
            let unscheduled = activeTasks.filter {
                $0.scheduledDate.isEmpty &&
                !overdueIDs.contains($0.id) && !dueTodayIDs.contains($0.id) && !doTodayIDs.contains($0.id)
            }

            return [
                TaskGroup(id: "overdue",    title: "Overdue",    accent: Theme.red,              tasks: overdue),
                TaskGroup(id: "due-today",  title: "Due Today",  accent: Theme.red.opacity(0.8), tasks: dueToday),
                TaskGroup(id: "do-today",   title: "Do Today",   accent: Theme.blue,             tasks: doToday),
                TaskGroup(id: "scheduled",  title: "Scheduled",  accent: Theme.dim,              tasks: scheduled),
                TaskGroup(id: "unscheduled",title: "Unscheduled",accent: Theme.amber,            tasks: unscheduled)
            ]
            .filter { !$0.tasks.isEmpty }
        case .byList:
            return sectionNames.compactMap { sectionName in
                let sectionTasks = activeTasks.filter {
                    $0.resolvedSectionName.caseInsensitiveCompare(sectionName) == .orderedSame
                }
                guard !sectionTasks.isEmpty else { return nil }
                return TaskGroup(id: "section-\(sectionName.lowercased())", title: sectionName, accent: Theme.blue, tasks: sectionTasks)
            }
        case .byPriority:
            return TaskPriority.allCases.reversed().compactMap { priority in
                let sectionTasks = activeTasks.filter { $0.priority == priority }
                guard !sectionTasks.isEmpty else { return nil }
                return TaskGroup(id: "priority-\(priority.rawValue)", title: priority.label, accent: Theme.priorityColor(priority), tasks: sectionTasks)
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
                    CollapsibleTaskGroupHeader(
                        title: group.title,
                        isCollapsed: collapsedGroupIDs.contains(group.id),
                        overdueCount: overdueCount(in: group.tasks),
                        regularCount: regularCount(in: group.tasks),
                        accent: group.accent,
                        onToggle: { toggleGroup(group.id) }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())

                    if !collapsedGroupIDs.contains(group.id) {
                        ForEach(group.tasks) { task in
                            MacTaskRow(task: task, style: .list)
                                .padding(.leading, 16)
                                .listRowInsets(.init())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                                .overlay(alignment: .top) {
                                    if dragOverTaskID == task.id {
                                        Rectangle().fill(Theme.blue).frame(height: 2).padding(.leading, 16).transition(.opacity)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                                .draggable("listTask:\(task.id.uuidString)")
                                .dropDestination(for: String.self) { items, _ in
                                    guard let payload = items.first,
                                          payload.hasPrefix("listTask:"),
                                          let droppedID = UUID(uuidString: String(payload.dropFirst(9))),
                                          droppedID != task.id else { return false }
                                    reorderTask(droppedID: droppedID, targetID: task.id)
                                    return true
                                } isTargeted: { isOver in
                                    if isOver { dragOverTaskID = task.id }
                                    else if dragOverTaskID == task.id { dragOverTaskID = nil }
                                }
                        }
                    }
                }

                if !doneTasks.isEmpty {
                    CompletedSectionHeader(
                        count: doneTasks.count,
                        isCollapsed: isCompletedCollapsed,
                        onToggle: { isCompletedCollapsed.toggle() }
                    )
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init())
                    if !isCompletedCollapsed {
                        ForEach(doneTasks) { task in
                            MacTaskRow(task: task, style: .list)
                                .padding(.leading, 16)
                                .listRowInsets(.init())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                        }
                    }
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
            ListTasksHoverFreezeObserver(
                frozenOrder: $frozenTaskOrder,
                frozenGroups: $frozenGroupedTasks,
                naturalTasks: tasks.filter { !$0.isDone && !$0.isCancelled }.taskSorted(by: sortField, direction: sortDirection)
                ,groupSnapshot: groupedActiveTasks.map { group in
                    FrozenTaskGroup(
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

struct ListLogView: View {
    let tasks: [AppTask]

    private var doneTasks: [AppTask] {
        tasks.filter { $0.isDone || $0.isCancelled }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    var body: some View {
        ZStack {
            Theme.bg

            if doneTasks.isEmpty {
                EmptyStateView(message: "No completed tasks", subtitle: "Completed tasks will appear here", icon: "checkmark.circle")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(doneTasks.count) COMPLETED")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .kerning(0.8)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(doneTasks) { task in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.green)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.dim)
                                        .strikethrough(true, color: Theme.dim)
                                    if !task.dueDate.isEmpty {
                                        Text(task.dueDate)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.dim.opacity(0.6))
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Theme.borderSubtle.opacity(0.4)).frame(height: 0.5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
    }
}

struct TabButton: View {
    let tab: ListDetailPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon).font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
            .frame(minWidth: 78, minHeight: 34)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle().fill(Theme.blue).frame(height: 2)
                }
            }
        }
        .buttonStyle(.cadencePlain)
    }
}

private struct ListTasksHoverFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenOrder: [AppTask]?
    @Binding var frozenGroups: [ListTasksView.FrozenTaskGroup]?
    let naturalTasks: [AppTask]
    let groupSnapshot: [ListTasksView.FrozenTaskGroup]
    @State private var isPointerInsideSurface = false
    private let releaseAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if newID != nil {
                    if frozenOrder == nil { frozenOrder = naturalTasks }
                    if frozenGroups == nil { frozenGroups = groupSnapshot }
                } else if !isPointerInsideSurface, frozenOrder != nil || frozenGroups != nil {
                    withAnimation(releaseAnimation) {
                        frozenOrder = nil
                        frozenGroups = nil
                    }
                }
            }
            .onHover { isPointerInsideSurface = $0 }
    }
}
#endif
