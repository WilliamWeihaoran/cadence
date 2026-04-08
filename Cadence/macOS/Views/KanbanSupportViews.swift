#if os(macOS)
import SwiftUI
import SwiftData

let kanbanSectionDragPrefix = "kanban-section::"
let kanbanSectionColorOptions: [String] = [
    "#6b7a99", "#4a9eff", "#4ecb71", "#f59e0b", "#ef4444", "#a855f7", "#14b8a6", "#f97316"
]
let kanbanColumnReorderAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.12)
let kanbanColumnStateAnimation = Animation.spring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.08)
let kanbanColumnWidth: CGFloat = 248

struct TaskListsKanbanView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    var sortField: TaskSortField = .date
    var sortDirection: TaskSortDirection = .ascending
    var groupingMode: TaskGroupingMode = .byList

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                switch groupingMode {
                case .none:
                    TaskListBoardSection(
                        title: "Tasks",
                        icon: "square.stack.3d.up",
                        color: Theme.dim,
                        taskCount: activeTasks.taskSorted(by: sortField, direction: sortDirection).count
                    ) {
                        let sorted = activeTasks.taskSorted(by: sortField, direction: sortDirection)
                        ListSectionsKanbanView(
                            tasks: sorted,
                            universeTasks: activeTasks,
                            explicitSectionConfigs: [TaskSectionConfig(name: TaskSectionDefaults.defaultName)],
                            sortField: sortField,
                            sortDirection: sortDirection,
                            sectionTaskProvider: { _ in sorted }
                        )
                    }
                case .byList:
                    let byAreaID = groupedTasksByAreaID
                    let byProjectID = groupedTasksByProjectID
                    TaskListBoardSection(
                        title: "Inbox",
                        icon: "tray.fill",
                        color: Theme.dim,
                        taskCount: inboxTasks.count
                    ) {
                        ListSectionsKanbanView(
                            tasks: inboxTasks,
                            universeTasks: activeTasks,
                            explicitSectionConfigs: [TaskSectionConfig(name: TaskSectionDefaults.defaultName)],
                            onTaskDroppedIntoColumn: { task, _ in
                                task.area = nil
                                task.project = nil
                                task.context = nil
                            }
                        )
                    }

                    ForEach(areas) { area in
                        let areaTasks = byAreaID[area.id] ?? []
                        TaskListBoardSection(
                            title: area.name,
                            icon: area.icon,
                            color: Color(hex: area.colorHex),
                            taskCount: areaTasks.count
                        ) {
                            ListSectionsKanbanView(tasks: areaTasks, universeTasks: activeTasks, area: area)
                        }
                    }

                    ForEach(projects) { project in
                        let projectTasks = byProjectID[project.id] ?? []
                        TaskListBoardSection(
                            title: project.name,
                            icon: project.icon,
                            color: Color(hex: project.colorHex),
                            taskCount: projectTasks.count
                        ) {
                            ListSectionsKanbanView(tasks: projectTasks, universeTasks: activeTasks, project: project)
                        }
                    }
                case .byPriority:
                    ForEach(Array(TaskPriority.allCases.reversed()), id: \.self) { priority in
                        let bucket = activeTasks.filter { $0.priority == priority }.taskSorted(by: sortField, direction: sortDirection)
                        if !bucket.isEmpty {
                            TaskListBoardSection(
                                title: priority.label,
                                icon: "flag.fill",
                                color: Theme.priorityColor(priority),
                                taskCount: bucket.count
                            ) {
                                ListSectionsKanbanView(
                                    tasks: bucket,
                                    universeTasks: activeTasks,
                                    explicitSectionConfigs: [TaskSectionConfig(name: TaskSectionDefaults.defaultName)],
                                    onTaskDroppedIntoColumn: { task, _ in
                                        task.priority = priority
                                    }
                                )
                            }
                        }
                    }
                case .byDate:
                    ForEach(dateBuckets, id: \.title) { bucket in
                        if !bucket.tasks.isEmpty {
                            TaskListBoardSection(
                                title: bucket.title,
                                icon: bucket.icon,
                                color: bucket.color,
                                taskCount: bucket.tasks.count
                            ) {
                                ListSectionsKanbanView(
                                    tasks: bucket.tasks,
                                    universeTasks: activeTasks,
                                    explicitSectionConfigs: [TaskSectionConfig(name: TaskSectionDefaults.defaultName)],
                                    onTaskDroppedIntoColumn: { task, _ in
                                        applyDateBucketDrop(task: task, bucketTitle: bucket.title)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.bg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .clipped()
    }

    private var activeTasks: [AppTask] {
        allTasks.filter { !$0.isCancelled }
    }

    private var groupedTasksByAreaID: [UUID: [AppTask]] {
        Dictionary(grouping: activeTasks.compactMap { task -> (UUID, AppTask)? in
            guard let areaID = task.area?.id else { return nil }
            return (areaID, task)
        }, by: \.0).mapValues { entries in
            entries.map(\.1).taskSorted(by: sortField, direction: sortDirection)
        }
    }

    private var groupedTasksByProjectID: [UUID: [AppTask]] {
        Dictionary(grouping: activeTasks.compactMap { task -> (UUID, AppTask)? in
            guard let projectID = task.project?.id else { return nil }
            return (projectID, task)
        }, by: \.0).mapValues { entries in
            entries.map(\.1).taskSorted(by: sortField, direction: sortDirection)
        }
    }

    private var inboxTasks: [AppTask] {
        activeTasks.filter { $0.area == nil && $0.project == nil }.taskSorted(by: sortField, direction: sortDirection)
    }

    private var dateBuckets: [(title: String, icon: String, color: Color, tasks: [AppTask])] {
        let todayKey = DateFormatters.todayKey()
        let overdue = activeTasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }.taskSorted(by: sortField, direction: sortDirection)
        let doToday = activeTasks.filter { $0.scheduledDate == todayKey }.taskSorted(by: sortField, direction: sortDirection)
        let scheduled = activeTasks.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate != todayKey }.taskSorted(by: sortField, direction: sortDirection)
        let unscheduled = activeTasks.filter { $0.scheduledDate.isEmpty || $0.scheduledStartMin < 0 }.taskSorted(by: sortField, direction: sortDirection)
        return [
            ("Overdue", "exclamationmark.triangle.fill", Theme.red, overdue),
            ("Do Today", "sun.max.fill", Theme.blue, doToday),
            ("Scheduled", "calendar", Theme.dim, scheduled),
            ("Unscheduled", "questionmark.circle", Theme.amber, unscheduled)
        ]
    }

    private func applyDateBucketDrop(task: AppTask, bucketTitle: String) {
        let todayKey = DateFormatters.todayKey()
        switch bucketTitle {
        case "Do Today":
            task.scheduledDate = todayKey
        case "Scheduled":
            if task.scheduledDate.isEmpty || task.scheduledDate == todayKey {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
            }
        case "Unscheduled":
            task.scheduledDate = ""
            task.scheduledStartMin = -1
        case "Overdue":
            if task.dueDate.isEmpty || task.dueDate >= todayKey {
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                task.dueDate = DateFormatters.dateKey(from: yesterday)
            }
        default:
            break
        }
    }
}

struct ListSectionsKanbanView: View {
    let tasks: [AppTask]
    var universeTasks: [AppTask]? = nil
    var area: Area? = nil
    var project: Project? = nil
    var explicitSectionConfigs: [TaskSectionConfig]? = nil
    var showArchived: Binding<Bool>? = nil
    var onTaskDroppedIntoColumn: ((AppTask, String) -> Void)? = nil
    var assignSectionOnDrop: Bool = true
    var sortField: TaskSortField = .date
    var sortDirection: TaskSortDirection = .ascending
    var sectionTaskProvider: ((TaskSectionConfig) -> [AppTask])? = nil
    var highlightedSectionName: String? = nil

    @State private var localShowArchived = false
    @State private var draggingSectionName: String?
    @State private var activeHighlightSectionName: String?

    private var baseSectionConfigs: [TaskSectionConfig] {
        explicitSectionConfigs ?? area?.sectionConfigs ?? project?.sectionConfigs ?? [TaskSectionConfig(name: TaskSectionDefaults.defaultName)]
    }

    private var sectionConfigs: [TaskSectionConfig] {
        let configs = baseSectionConfigs
        return showArchivedBinding.wrappedValue ? configs.filter(\.isArchived) : configs.filter { !$0.isArchived }
    }

    private var allowsSectionEditing: Bool {
        area != nil || project != nil
    }

    private var showArchivedBinding: Binding<Bool> {
        showArchived ?? $localShowArchived
    }

    var body: some View {
        ZStack {
            Theme.bg

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(sectionConfigs, id: \.id) { section in
                            let sectionTasks = sortedTasksForSection(section)
                            ListSectionKanbanColumn(
                                section: section,
                                tasks: sectionTasks,
                                universeTasks: universeTasks ?? tasks,
                                area: area,
                                project: project,
                                onTaskDroppedIntoColumn: onTaskDroppedIntoColumn,
                                assignSectionOnDrop: assignSectionOnDrop,
                                isBeingDragged: draggingSectionName?.caseInsensitiveCompare(section.name) == .orderedSame,
                                isAnotherSectionBeingDragged: draggingSectionName != nil && draggingSectionName?.caseInsensitiveCompare(section.name) != .orderedSame,
                                isHighlighted: activeHighlightSectionName?.caseInsensitiveCompare(section.name) == .orderedSame,
                                onReorderBefore: { movingName in
                                    reorderSection(named: movingName, before: section.name)
                                    DispatchQueue.main.async {
                                        draggingSectionName = nil
                                    }
                                }
                            )
                            .id(section.id)
                            .onDrag {
                                draggingSectionName = section.name
                                return NSItemProvider(object: NSString(string: "\(kanbanSectionDragPrefix)\(section.name)"))
                            } preview: {
                                columnDragPreview(for: section)
                            }
                        }

                        if allowsSectionEditing && !showArchivedBinding.wrappedValue {
                            addSectionRail
                        }
                    }
                    .padding(20)
                    .background(Theme.bg)
                }
                .background(Theme.bg)
                .onAppear {
                    applyHighlightIfNeeded(with: proxy)
                }
                .onChange(of: highlightedSectionName) { _, _ in
                    applyHighlightIfNeeded(with: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func applyHighlightIfNeeded(with proxy: ScrollViewProxy) {
        guard let highlightedSectionName,
              let matchingSection = sectionConfigs.first(where: {
                  $0.name.caseInsensitiveCompare(highlightedSectionName) == .orderedSame
              }) else {
            activeHighlightSectionName = nil
            return
        }

        activeHighlightSectionName = matchingSection.name
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(matchingSection.id, anchor: .center)
        }

        let highlightedName = matchingSection.name
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard activeHighlightSectionName?.caseInsensitiveCompare(highlightedName) == .orderedSame else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                activeHighlightSectionName = nil
            }
        }
    }

    private func sortedTasksForSection(_ section: TaskSectionConfig) -> [AppTask] {
        let source = sectionTaskProvider?(section) ?? tasks.filter {
            !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
        }
        return source.taskSorted(by: sortField, direction: sortDirection)
    }

    @ViewBuilder
    private var addSectionRail: some View {
        Button {
            addSection()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface.opacity(0.72))
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.borderSubtle.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))

                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .frame(width: 42)
            .frame(minHeight: 360)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.cadencePlain)
    }

    private func addSection() {
        let trimmed = nextSectionName()
        if let area {
            var configs = area.sectionConfigs
            guard !configs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            configs.append(TaskSectionConfig(name: trimmed, colorHex: area.colorHex))
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard !configs.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            configs.append(TaskSectionConfig(name: trimmed, colorHex: project.colorHex))
            project.sectionConfigs = configs
        }
    }

    private func nextSectionName() -> String {
        let existingNames = Set(baseSectionConfigs.map { $0.name.lowercased() })
        if !existingNames.contains("new section") {
            return "New Section"
        }

        var index = 2
        while existingNames.contains("new section \(index)") {
            index += 1
        }
        return "New Section \(index)"
    }

    private func reorderSection(named movingName: String, before targetName: String) {
        guard movingName.caseInsensitiveCompare(targetName) != .orderedSame else { return }

        func reordered(_ configs: [TaskSectionConfig]) -> [TaskSectionConfig] {
            guard let from = configs.firstIndex(where: { $0.name.caseInsensitiveCompare(movingName) == .orderedSame }),
                  let to = configs.firstIndex(where: { $0.name.caseInsensitiveCompare(targetName) == .orderedSame }) else { return configs }
            var updated = configs
            let item = updated.remove(at: from)
            let insertAt = from < to ? to - 1 : to
            updated.insert(item, at: max(0, insertAt))
            if let defaultIndex = updated.firstIndex(where: \.isDefault), defaultIndex != 0 {
                let def = updated.remove(at: defaultIndex)
                updated.insert(def, at: 0)
            }
            return updated
        }

        if let area {
            withAnimation(kanbanColumnReorderAnimation) {
                area.sectionConfigs = reordered(area.sectionConfigs)
            }
        } else if let project {
            withAnimation(kanbanColumnReorderAnimation) {
                project.sectionConfigs = reordered(project.sectionConfigs)
            }
        }
    }

    @ViewBuilder
    private func columnDragPreview(for section: TaskSectionConfig) -> some View {
        let tint = section.isDefault ? Theme.dim : Color(hex: section.colorHex)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint.opacity(section.isDefault ? 0.55 : 0.9))
                    .frame(width: 8, height: 8)
                Text(section.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surfaceElevated.opacity(0.95))
                .frame(height: 54)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.opacity(section.isDefault ? 0.18 : 0.24))
                        .frame(width: 86, height: 10)
                        .padding(10)
                }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tint.opacity(section.isDefault ? 0.06 : 0.11))
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
    }
}

struct KanbanFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenTasks: [AppTask]?
    let columnTaskIDs: Set<UUID>
    let capturedTasks: [AppTask]
    private let releaseAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if let newID, columnTaskIDs.contains(newID) {
                    if frozenTasks == nil { frozenTasks = capturedTasks }
                } else if frozenTasks != nil {
                    withAnimation(releaseAnimation) {
                        frozenTasks = nil
                    }
                }
            }
    }
}
#endif
