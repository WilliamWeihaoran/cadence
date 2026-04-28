#if os(macOS)
import SwiftUI
import SwiftData

private struct AllTasksFlatSection: Identifiable {
    let id: String
    let title: String
    let accent: Color
    let dropKey: String?
    let tasks: [AppTask]
}

struct AllTasksListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    let sortField: TaskSortField
    let sortDirection: TaskSortDirection
    let groupingMode: TaskGroupingMode

    @State private var collapsedSectionIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var dragOverTaskID: UUID?

    private var todayKey: String { DateFormatters.todayKey() }

    private var activeTasks: [AppTask] {
        allTasks
            .filter { !$0.isDone && !$0.isCancelled }
            .taskSorted(by: sortField, direction: sortDirection)
    }

    private var completedTasks: [AppTask] {
        allTasks
            .filter { $0.isDone || $0.isCancelled }
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.createdAt
                let rhsDate = rhs.completedAt ?? rhs.createdAt
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return taskSortPrecedes(lhs, rhs, field: .custom, direction: .ascending)
            }
    }

    private var completedTaskCount: Int {
        allTasks.reduce(into: 0) { count, task in
            if task.isDone || task.isCancelled {
                count += 1
            }
        }
    }

    private var tasksByID: [UUID: AppTask] {
        Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
    }

    private var blockedTaskIDs: Set<UUID> {
        let lookup = tasksByID
        return Set(
            allTasks.compactMap { task in
                guard !task.dependencyTaskIDs.isEmpty else { return nil }
                let hasUnresolvedDependency = task.dependencyTaskIDs.contains { dependencyID in
                    guard dependencyID != task.id, let dependency = lookup[dependencyID] else { return false }
                    return !dependency.isDone && !dependency.isCancelled
                }
                return hasUnresolvedDependency ? task.id : nil
            }
        )
    }

    private func flatSections(from activeTasks: [AppTask]) -> [AllTasksFlatSection] {
        switch groupingMode {
        case .none:
            return [
                AllTasksFlatSection(
                    id: "tasks",
                    title: "Tasks",
                    accent: Theme.dim,
                    dropKey: nil,
                    tasks: activeTasks
                )
            ].filter { !$0.tasks.isEmpty }
        case .byDate:
            let todayTasks = activeTasks.filter { $0.scheduledDate == todayKey }
            let scheduledTasks = activeTasks.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayKey }
            let unscheduledTasks = activeTasks.filter { $0.scheduledDate.isEmpty }
            return [
                AllTasksFlatSection(id: "do-today", title: "Do Today", accent: Theme.blue, dropKey: "date:today", tasks: todayTasks),
                AllTasksFlatSection(id: "scheduled", title: "Scheduled", accent: Theme.dim, dropKey: "date:scheduled", tasks: scheduledTasks),
                AllTasksFlatSection(id: "unscheduled", title: "Unscheduled", accent: Theme.amber, dropKey: "date:unscheduled", tasks: unscheduledTasks)
            ].filter { !$0.tasks.isEmpty }
        case .byList:
            return []
        case .byPriority:
            return TaskPriority.allCases.reversed().compactMap { priority in
                let tasks = activeTasks.filter { $0.priority == priority }
                guard !tasks.isEmpty else { return nil }
                return AllTasksFlatSection(
                    id: "priority-\(priority.rawValue)",
                    title: priority.label,
                    accent: Theme.priorityColor(priority),
                    dropKey: "priority:\(priority.rawValue)",
                    tasks: tasks
                )
            }
        }
    }

    private func listGroups(from activeTasks: [AppTask]) -> [TodayTaskGroup] {
        var groups: [String: TodayTaskGroup] = [:]

        for task in activeTasks {
            let key: String
            if let area = task.area {
                key = "a_\(area.id.uuidString)"
                groups[key] = groups[key] ?? TodayTaskGroup(
                    id: key,
                    contextID: area.context?.id.uuidString,
                    contextName: area.context?.name,
                    contextIcon: area.context?.icon,
                    contextColor: area.context.map { Color(hex: $0.colorHex) },
                    listIcon: area.icon,
                    listName: area.name,
                    listColor: Color(hex: area.colorHex),
                    tasks: []
                )
            } else if let project = task.project {
                key = "p_\(project.id.uuidString)"
                groups[key] = groups[key] ?? TodayTaskGroup(
                    id: key,
                    contextID: project.context?.id.uuidString,
                    contextName: project.context?.name,
                    contextIcon: project.context?.icon,
                    contextColor: project.context.map { Color(hex: $0.colorHex) },
                    listIcon: project.icon,
                    listName: project.name,
                    listColor: Color(hex: project.colorHex),
                    tasks: []
                )
            } else {
                key = "inbox"
                groups[key] = groups[key] ?? TodayTaskGroup(
                    id: "inbox",
                    contextID: nil,
                    contextName: nil,
                    contextIcon: nil,
                    contextColor: nil,
                    listIcon: "tray.fill",
                    listName: "Inbox",
                    listColor: Theme.dim,
                    tasks: []
                )
            }
            groups[key]?.tasks.append(task)
        }

        let orderedKeys = TasksPanelSupport.sidebarListOrder(contexts: contexts).filter { groups[$0] != nil }
        let unorderedKeys = groups.keys.filter { !orderedKeys.contains($0) }.sorted()
        return (orderedKeys + unorderedKeys).compactMap { groups[$0] }
    }

    var body: some View {
        let visibleTasks = activeTasks
        let completedCount = completedTaskCount
        let visibleCompletedTasks = isCompletedCollapsed ? [] : completedTasks
        let taskLookup = tasksByID
        let blockedIDs = blockedTaskIDs

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch groupingMode {
                case .byList:
                    ForEach(listGroups(from: visibleTasks)) { group in
                        AllTasksListGroupView(
                            group: group,
                            isCollapsed: collapsedSectionIDs.contains(group.id),
                            overdueCount: overdueCount(in: group.tasks),
                            regularCount: regularCount(in: group.tasks),
                            contexts: contexts,
                            areas: areas,
                            projects: projects,
                            allTasks: allTasks,
                            blockedTaskIDs: blockedIDs,
                            dragOverTaskID: $dragOverTaskID,
                            onToggle: { toggleSection(group.id) },
                            taskDragPayload: taskDragPayload,
                            onDropOnGroupPayload: { payload in
                                guard let droppedID = taskID(from: payload),
                                      let droppedTask = taskLookup[droppedID] else { return false }
                                assignTask(droppedTask, for: "list:\(group.id)")
                                return true
                            },
                            onDropOnTaskPayload: { payload, targetTask in
                                guard let droppedID = taskID(from: payload),
                                      droppedID != targetTask.id,
                                      let droppedTask = taskLookup[droppedID] else { return false }
                                assignTask(droppedTask, for: "list:\(group.id)")
                                reorderTask(droppedID: droppedID, targetID: targetTask.id, scopeTasks: group.tasks)
                                return true
                            }
                        )
                    }
                default:
                    ForEach(flatSections(from: visibleTasks)) { section in
                        AllTasksFlatSectionView(
                            section: section,
                            isCollapsed: collapsedSectionIDs.contains(section.id),
                            overdueCount: overdueCount(in: section.tasks),
                            regularCount: regularCount(in: section.tasks),
                            contexts: contexts,
                            areas: areas,
                            projects: projects,
                            allTasks: allTasks,
                            blockedTaskIDs: blockedIDs,
                            dragOverTaskID: $dragOverTaskID,
                            onToggle: { toggleSection(section.id) },
                            taskDragPayload: taskDragPayload,
                            onDropOnSectionPayload: { payload in
                                guard let dropKey = section.dropKey,
                                      let droppedID = taskID(from: payload),
                                      let droppedTask = taskLookup[droppedID] else { return false }
                                assignTask(droppedTask, for: dropKey)
                                return true
                            },
                            onDropOnTaskPayload: { payload, targetTask in
                                guard let droppedID = taskID(from: payload),
                                      droppedID != targetTask.id,
                                      let droppedTask = taskLookup[droppedID] else { return false }
                                if let dropKey = section.dropKey {
                                    assignTask(droppedTask, for: dropKey)
                                }
                                reorderTask(droppedID: droppedID, targetID: targetTask.id, scopeTasks: section.tasks)
                                return true
                            }
                        )
                    }
                }

                if completedCount > 0 {
                    AllTasksCompletedSectionView(
                        tasks: visibleCompletedTasks,
                        count: completedCount,
                        isCollapsed: isCompletedCollapsed,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        allTasks: allTasks,
                        blockedTaskIDs: blockedIDs,
                        onToggle: { isCompletedCollapsed.toggle() },
                        taskDragPayload: taskDragPayload
                    )
                }

                if visibleTasks.isEmpty && completedCount == 0 {
                    EmptyStateView(
                        message: "No tasks yet",
                        subtitle: "Add a task above to get started",
                        icon: "checkmark.circle"
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.bottom, 16)
        }
        .cadenceSoftPageBounce()
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
        )
        .background(Theme.surface)
        .onAppear {
            isCompletedCollapsed = true
        }
    }

    private func toggleSection(_ id: String) {
        if collapsedSectionIDs.contains(id) {
            collapsedSectionIDs.remove(id)
        } else {
            collapsedSectionIDs.insert(id)
        }
    }

    private func overdueCount(in tasks: [AppTask]) -> Int? {
        TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey)
    }

    private func regularCount(in tasks: [AppTask]) -> Int {
        TasksPanelSupport.regularCount(in: tasks, todayKey: todayKey)
    }

    private func taskDragPayload(for task: AppTask) -> String {
        TasksPanelSupport.taskDragPayload(for: task)
    }

    private func taskID(from payload: String) -> UUID? {
        TasksPanelSupport.taskID(from: payload)
    }

    private func reorderTask(droppedID: UUID, targetID: UUID, scopeTasks: [AppTask]) {
        TasksPanelSupport.reorderTask(
            droppedID: droppedID,
            targetID: targetID,
            scopeTasks: scopeTasks,
            modelContext: modelContext
        )
    }

    private func assignTask(_ task: AppTask, for dropKey: String) {
        TasksPanelSupport.assignTask(
            task,
            for: dropKey,
            todayKey: todayKey,
            areas: areas,
            projects: projects,
            modelContext: modelContext
        )
    }
}

private struct AllTasksFlatSectionView: View {
    let section: AllTasksFlatSection
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let blockedTaskIDs: Set<UUID>
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    let onDropOnSectionPayload: (String) -> Bool
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CollapsibleTaskGroupHeader(
                title: section.title,
                isCollapsed: isCollapsed,
                overdueCount: overdueCount,
                regularCount: regularCount,
                accent: section.accent,
                onToggle: onToggle
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 5)
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first else { return false }
                return onDropOnSectionPayload(payload)
            }

            if !isCollapsed {
                ForEach(section.tasks) { task in
                    AllTasksRowHost(
                        task: task,
                        style: .standard,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        allTasks: allTasks,
                        blockedTaskIDs: blockedTaskIDs,
                        dragOverTaskID: $dragOverTaskID,
                        taskDragPayload: taskDragPayload,
                        onDropOnTaskPayload: onDropOnTaskPayload
                    )
                    .padding(.leading, 16)
                }
            }
        }
    }
}

private struct AllTasksListGroupView: View {
    let group: TodayTaskGroup
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let blockedTaskIDs: Set<UUID>
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    let onDropOnGroupPayload: (String) -> Bool
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)

                    if let contextIcon = group.contextIcon, let contextColor = group.contextColor {
                        Image(systemName: contextIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(contextColor)
                            .frame(width: 22, height: 22)
                            .background(contextColor.opacity(0.15))
                            .clipShape(Circle())
                    }

                    Image(systemName: group.listIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(group.listColor)

                    Text(group.listName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)

                    Spacer()

                    if let overdueCount, overdueCount > 0 {
                        Text("\(overdueCount)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.red)
                        Text("/")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim.opacity(0.8))
                    }

                    Text("\(regularCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.surfaceElevated.opacity(0.75))
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 6)
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first else { return false }
                return onDropOnGroupPayload(payload)
            }

            if !isCollapsed {
                ForEach(group.tasks) { task in
                    AllTasksRowHost(
                        task: task,
                        style: .todayGrouped,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        allTasks: allTasks,
                        blockedTaskIDs: blockedTaskIDs,
                        dragOverTaskID: $dragOverTaskID,
                        taskDragPayload: taskDragPayload,
                        onDropOnTaskPayload: onDropOnTaskPayload
                    )
                    .padding(.leading, 20)
                    .padding(.trailing, 8)
                }
            }
        }
    }
}

private struct AllTasksCompletedSectionView: View {
    let tasks: [AppTask]
    let count: Int
    let isCollapsed: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let blockedTaskIDs: Set<UUID>
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompletedSectionHeader(
                count: count,
                isCollapsed: isCollapsed,
                onToggle: onToggle
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)

            if !isCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: .standard, contexts: contexts, areas: areas, projects: projects, allTasks: allTasks, blockedTaskIDs: blockedTaskIDs)
                        .draggable(taskDragPayload(task))
                        .padding(.leading, 16)
                }
            }
        }
    }
}

private struct AllTasksRowHost: View {
    let task: AppTask
    let style: MacTaskRowStyle
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let blockedTaskIDs: Set<UUID>
    @Binding var dragOverTaskID: UUID?
    let taskDragPayload: (AppTask) -> String
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        MacTaskRow(task: task, style: style, contexts: contexts, areas: areas, projects: projects, allTasks: allTasks, blockedTaskIDs: blockedTaskIDs)
            .draggable(taskDragPayload(task))
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first else { return false }
                return onDropOnTaskPayload(payload, task)
            } isTargeted: { isOver in
                if isOver {
                    dragOverTaskID = task.id
                } else if dragOverTaskID == task.id {
                    dragOverTaskID = nil
                }
            }
            .overlay(alignment: .top) {
                if dragOverTaskID == task.id {
                    Rectangle()
                        .fill(Theme.blue)
                        .frame(height: 2)
                        .padding(.leading, 16)
                }
            }
    }
}
#endif
