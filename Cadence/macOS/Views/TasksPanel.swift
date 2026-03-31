#if os(macOS)
import SwiftUI
import SwiftData

enum TasksPanelMode {
    case todayOverview
    case byDoDate
}

// MARK: - Task group (context → list)

private struct TodayTaskGroup: Identifiable {
    let id: String
    let contextIcon: String?
    let contextColor: Color?
    let listIcon: String
    let listName: String
    let listColor: Color
    var tasks: [AppTask]
}

private struct TodayDueSectionItem: Identifiable {
    let id: String
    let listIcon: String
    let listName: String
    let listColor: Color
    let sectionName: String
    let taskCount: Int
    let completedTaskCount: Int
}

// MARK: - Task Row Style

enum MacTaskRowStyle {
    case standard      // full 2-line row with list picker
    case todayGrouped  // no list picker, due date on line 1 right (existing showListBadge: false behavior)
    case list          // do-date pill left of title, due text right, no list picker
}

// MARK: - Tasks Panel

struct TasksPanel: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    let mode: TasksPanelMode
    let showsHeader: Bool

    init(mode: TasksPanelMode = .todayOverview, showsHeader: Bool = true) {
        self.mode = mode
        self.showsHeader = showsHeader
    }

    private var todayKey: String { DateFormatters.todayKey() }

    private var overdue: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && !$0.dueDate.isEmpty && $0.dueDate < todayKey }
    }
    private var dueTodayTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && $0.dueDate == todayKey }
    }
    private var doTodayTasks: [AppTask] {
        let excluded = Set(overdue.map(\.id)).union(dueTodayTasks.map(\.id))
        return allTasks.filter {
            !$0.isDone && !$0.isCancelled && $0.scheduledDate == todayKey && !excluded.contains($0.id)
        }
    }
    private var dueTodaySections: [TodayDueSectionItem] {
        let areaItems = areas.flatMap { area in
            area.sectionConfigs.compactMap { section -> TodayDueSectionItem? in
                guard !section.isArchived, !section.isCompleted, section.dueDate == todayKey else { return nil }
                let sectionTasks = (area.tasks ?? []).filter {
                    !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
                }
                return TodayDueSectionItem(
                    id: "area-\(area.id.uuidString)-\(section.id.uuidString)",
                    listIcon: area.icon,
                    listName: area.name,
                    listColor: Color(hex: area.colorHex),
                    sectionName: section.name,
                    taskCount: sectionTasks.filter { !$0.isDone }.count,
                    completedTaskCount: sectionTasks.filter(\.isDone).count
                )
            }
        }

        let projectItems = projects.flatMap { project in
            project.sectionConfigs.compactMap { section -> TodayDueSectionItem? in
                guard !section.isArchived, !section.isCompleted, section.dueDate == todayKey else { return nil }
                let sectionTasks = (project.tasks ?? []).filter {
                    !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
                }
                return TodayDueSectionItem(
                    id: "project-\(project.id.uuidString)-\(section.id.uuidString)",
                    listIcon: project.icon,
                    listName: project.name,
                    listColor: Color(hex: project.colorHex),
                    sectionName: section.name,
                    taskCount: sectionTasks.filter { !$0.isDone }.count,
                    completedTaskCount: sectionTasks.filter(\.isDone).count
                )
            }
        }

        return (areaItems + projectItems).sorted {
            if $0.listName != $1.listName {
                return $0.listName.localizedCaseInsensitiveCompare($1.listName) == .orderedAscending
            }
            return $0.sectionName.localizedCaseInsensitiveCompare($1.sectionName) == .orderedAscending
        }
    }
    private var byDoDateTodayTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && $0.scheduledDate == todayKey }
    }
    private var byDoDateUpcomingTasks: [AppTask] {
        let todayIDs = Set(byDoDateTodayTasks.map(\.id))
        return allTasks.filter {
            !$0.isDone && !$0.isCancelled && !taskIsUnscheduled($0) &&
            $0.scheduledDate != todayKey && !todayIDs.contains($0.id)
        }
    }
    private var byDoDateUnscheduledTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && taskIsUnscheduled($0) }
    }
    private var doneTasks: [AppTask] { allTasks.filter { $0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                TasksPanelHeader(mode: mode)
                Divider().background(Theme.borderSubtle)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if mode == .todayOverview {
                        if !dueTodaySections.isEmpty {
                            dueSectionsSection(items: dueTodaySections)
                        }
                        if !overdue.isEmpty {
                            flatSection(label: "Overdue", tasks: overdue, labelColor: Theme.red)
                        }
                        if !dueTodayTasks.isEmpty {
                            flatSection(label: "Due Today", tasks: dueTodayTasks, labelColor: Theme.blue)
                        }
                        // Do Today: grouped by context → list
                        let groups = groupedTasks(doTodayTasks)
                        if !groups.isEmpty {
                            ForEach(groups) { group in
                                groupSection(group: group)
                            }
                        }
                    } else {
                        if !byDoDateTodayTasks.isEmpty  { flatSection(label: "Do Today",    tasks: byDoDateTodayTasks,    labelColor: Theme.blue)  }
                        if !byDoDateUpcomingTasks.isEmpty { flatSection(label: "Scheduled",  tasks: byDoDateUpcomingTasks,  labelColor: Theme.dim)   }
                        if !byDoDateUnscheduledTasks.isEmpty { flatSection(label: "Unscheduled", tasks: byDoDateUnscheduledTasks, labelColor: Theme.amber) }
                    }
                    if !doneTasks.isEmpty { flatSection(label: "Done", tasks: doneTasks, labelColor: Theme.green) }
                    if isEmptyState {
                        EmptyStateView(
                            message: mode == .byDoDate ? "No tasks yet" : "Nothing for today",
                            subtitle: mode == .byDoDate ? "Add a task above to get started" : "Due-today and do-today tasks will appear here",
                            icon: "checkmark.circle"
                        )
                        .padding(.top, 40)
                    }
                }
                .padding(.top, showsHeader && mode == .todayOverview ? 12 : 0)
                .padding(.bottom, 16)
            }
        }
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
        )
        .background(Theme.surface)
    }

    // MARK: - Grouping

    private func groupedTasks(_ tasks: [AppTask]) -> [TodayTaskGroup] {
        var groups: [String: TodayTaskGroup] = [:]
        var order: [String] = []

        for task in tasks {
            let key: String
            if let area = task.area {
                key = "a_\(area.id)"
                if groups[key] == nil {
                    groups[key] = TodayTaskGroup(
                        id: key,
                        contextIcon: area.context?.icon,
                        contextColor: area.context.map { Color(hex: $0.colorHex) },
                        listIcon: area.icon,
                        listName: area.name,
                        listColor: Color(hex: area.colorHex),
                        tasks: []
                    )
                    order.append(key)
                }
            } else if let project = task.project {
                key = "p_\(project.id)"
                if groups[key] == nil {
                    groups[key] = TodayTaskGroup(
                        id: key,
                        contextIcon: project.context?.icon,
                        contextColor: project.context.map { Color(hex: $0.colorHex) },
                        listIcon: project.icon,
                        listName: project.name,
                        listColor: Color(hex: project.colorHex),
                        tasks: []
                    )
                    order.append(key)
                }
            } else {
                key = "inbox"
                if groups[key] == nil {
                    groups[key] = TodayTaskGroup(
                        id: "inbox",
                        contextIcon: nil, contextColor: nil,
                        listIcon: "tray.fill",
                        listName: "Inbox",
                        listColor: Theme.dim,
                        tasks: []
                    )
                    order.append(key)
                }
            }
            groups[key]!.tasks.append(task)
        }
        return order.compactMap { groups[$0] }
    }

    // MARK: - Section builders

    @ViewBuilder
    private func groupSection(group: TodayTaskGroup) -> some View {
        // Group header: context badge + list name
        HStack(spacing: 10) {
            if let ctxIcon = group.contextIcon, let ctxColor = group.contextColor {
                Image(systemName: ctxIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ctxColor)
                    .frame(width: 22, height: 22)
                    .background(ctxColor.opacity(0.15))
                    .clipShape(Circle())
            }
            Image(systemName: group.listIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(group.listColor)
            Text(group.listName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 6)

        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(height: 0.5)
            .padding(.horizontal, 16)

        ForEach(group.tasks) { task in
            MacTaskRow(task: task, style: .todayGrouped)
                .draggable(task.id.uuidString)
        }
    }

    @ViewBuilder
    private func flatSection(label: String, tasks: [AppTask], labelColor: Color) -> some View {
        Section {
            ForEach(tasks) { task in
                MacTaskRow(task: task, style: .standard)
                    .draggable(task.id.uuidString)
            }
        } header: {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(labelColor)
                .kerning(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
        }
    }

    private var isEmptyState: Bool {
        switch mode {
        case .todayOverview:
            return dueTodaySections.isEmpty && overdue.isEmpty && dueTodayTasks.isEmpty && doTodayTasks.isEmpty && doneTasks.isEmpty
        case .byDoDate:
            return byDoDateTodayTasks.isEmpty && byDoDateUpcomingTasks.isEmpty && byDoDateUnscheduledTasks.isEmpty && doneTasks.isEmpty
        }
    }

    private func taskIsUnscheduled(_ task: AppTask) -> Bool {
        task.scheduledDate.isEmpty || task.scheduledStartMin < 0
    }

    @ViewBuilder
    private func dueSectionsSection(items: [TodayDueSectionItem]) -> some View {
        Section {
            ForEach(items) { item in
                TodayDueSectionCard(item: item)
            }
        } header: {
            Text("SECTIONS DUE TODAY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .kerning(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
        }
    }
}

// MARK: - Panel Header

private struct TasksPanelHeader: View {
    let mode: TasksPanelMode

    @Environment(TaskCreationManager.self) private var taskCreationManager

    private var title: String {
        switch mode {
        case .todayOverview: return "Today"
        case .byDoDate:      return "By Do Date"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TASKS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .kerning(0.8)
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                Spacer()
                Button {
                    switch mode {
                    case .todayOverview: taskCreationManager.present(doDateKey: DateFormatters.todayKey())
                    case .byDoDate:      taskCreationManager.present()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("New Task").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Task Row

struct MacTaskRow: View {
    @Bindable var task: AppTask
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self)    private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(FocusManager.self)          private var focusManager
    @Environment(TaskCompletionAnimationManager.self) private var taskCompletionAnimationManager

    /// Controls the row layout and which metadata elements are shown.
    var style: MacTaskRowStyle = .standard

    @State private var showDueDatePicker  = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var dueDateViewMonth:  Date = Date()
    @State private var showDoDatePicker   = false
    @State private var doDatePickerDate: Date = Date()
    @State private var doDateViewMonth:   Date = Date()
    @State private var showPriorityPicker = false
    @State private var isHovered          = false
    @State private var showTaskInspector  = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Priority bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(task.isDone ? Theme.dim.opacity(0.4) : Theme.priorityColor(task.priority))
                .frame(width: 3)
                .padding(.leading, 8)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 5) {

                // ── Line 1 ──────────────────────────────────────────────────────
                HStack(spacing: 0) {
                    // Checkbox
                    Button {
                        taskCompletionAnimationManager.toggleCompletion(for: task)
                    } label: {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : (isPendingCompletion ? "circle.inset.filled" : "circle"))
                            .foregroundStyle(task.isDone || isPendingCompletion ? Theme.green : Theme.dim)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.cadencePlain)
                    .padding(.horizontal, 8)

                    // Do-date pill (list style only)
                    if style == .list && !task.scheduledDate.isEmpty {
                        doDatePill
                            .padding(.trailing, 6)
                    }

                    // Title (tap opens inspector; editing is done in the inspector)
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 15))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Due date flushed right
                    switch style {
                    case .todayGrouped:
                        // flag + short date on line 1 (existing grouped behaviour)
                        if !task.dueDate.isEmpty {
                            dueDateBadgeGrouped
                        }
                    case .list:
                        // flag + days-left text on line 1
                        if !task.dueDate.isEmpty {
                            dueDateBadgeList
                        }
                    case .standard:
                        EmptyView()
                    }

                    // Focus button (shown on hover)
                    if isHovered && !task.isDone && !task.isCancelled {
                        Button { focusManager.startFocus(task: task) } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Theme.blue)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.cadencePlain)
                        .help("Start focus session")
                        .padding(.trailing, 4)
                    }
                }

                // ── Line 2: time · priority · [due date + list picker (standard only)] ──
                HStack(spacing: 6) {
                    EstimatePickerControl(value: $task.estimatedMinutes)
                        .scaleEffect(0.86, anchor: .leading)
                        .frame(maxWidth: 78, alignment: .leading)
                    metaDivider

                    // Priority
                    Button { showPriorityPicker.toggle() } label: {
                        HStack(spacing: 4) {
                            if task.priority == .none {
                                Text("—").font(.system(size: 11)).foregroundStyle(Theme.dim)
                            } else {
                                Circle().fill(Theme.priorityColor(task.priority)).frame(width: 6, height: 6)
                            }
                            Text(task.priority.label)
                                .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim)
                        }
                    }
                    .buttonStyle(.cadencePlain)
                    .popover(isPresented: $showPriorityPicker) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(TaskPriority.allCases, id: \.self) { p in
                                Button {
                                    task.priority = p
                                    showPriorityPicker = false
                                } label: {
                                    HStack(spacing: 8) {
                                        if p == .none {
                                            Text("—").font(.system(size: 13)).foregroundStyle(Theme.dim).frame(width: 7)
                                        } else {
                                            Circle().fill(Theme.priorityColor(p)).frame(width: 7, height: 7)
                                        }
                                        Text(p.label).font(.system(size: 13)).foregroundStyle(Theme.text)
                                        Spacer()
                                        if task.priority == p {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                                        }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }
                                .buttonStyle(.cadencePlain)
                            }
                        }
                        .padding(.vertical, 6).frame(minWidth: 150).background(Theme.surfaceElevated)
                    }

                    // Due date + list picker (standard mode only)
                    if style == .standard {
                        metaDivider
                        dueDateBadgeStandard
                        metaDivider
                        ContainerPickerBadge(selection: taskContainerBinding, contexts: contexts, areas: areas, projects: projects)
                    }
                }
                .padding(.leading, 34)
                .padding(.trailing, 12)

                // ── Subtasks ──────────────────────────────────────────────
                let sortedSubtasks = (task.subtasks ?? []).sorted { $0.order < $1.order }
                if !sortedSubtasks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(sortedSubtasks) { subtask in
                            SubtaskRow(subtask: subtask)
                        }
                    }
                    .padding(.leading, 30)
                    .padding(.trailing, 12)
                    .padding(.bottom, 4)
                }
            }
            .padding(.vertical, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture { showTaskInspector = true }
        .background(
            completionAnimatedBackground
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Theme.blue.opacity(0.44) : .white.opacity(0.04), lineWidth: isHovered ? 1.2 : 1)
        }
        .shadow(color: isHovered ? Theme.blue.opacity(0.12) : .clear, radius: 10, y: 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(height: 0.5)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredTaskManager.beginHovering(task, source: .list)
                hoveredEditableManager.beginHovering(id: "task-row-\(task.id.uuidString)") {
                    showTaskInspector = true
                } onDelete: {
                    deleteConfirmationManager.present(
                        title: "Delete Task?",
                        message: "This will permanently delete \"\(task.title.isEmpty ? "Untitled" : task.title)\"."
                    ) {
                        if hoveredTaskManager.hoveredTask?.id == task.id {
                            hoveredTaskManager.hoveredTask = nil
                        }
                        modelContext.delete(task)
                    }
                }
            } else {
                hoveredTaskManager.endHovering(task)
                hoveredEditableManager.endHovering(id: "task-row-\(task.id.uuidString)")
            }
        }
        .popover(isPresented: $showTaskInspector, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
        .opacity(task.isDone ? 0.5 : 1.0)
    }

    // MARK: - Do-date pill (list style)

    private var doDatePill: some View {
        Button {
            openDoDatePicker()
        } label: {
            Text(DateFormatters.relativeDate(from: task.scheduledDate))
                .font(.system(size: 11))
                .foregroundStyle(
                    isOverdo
                        ? Theme.red
                        : (isDoToday ? Theme.amber : Theme.dim)
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showDoDatePicker) { doDatePickerPopover }
    }

    // MARK: - Due date badge: standard (line 2, small)

    private var dueDateBadgeStandard: some View {
        Button {
            openDueDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(task.dueDate.isEmpty ? Theme.dim : Theme.red)
                if !task.dueDate.isEmpty {
                    Text(DateFormatters.relativeDate(from: task.dueDate))
                        .font(.system(size: 11))
                        .foregroundStyle(isOverdue ? Theme.red : Theme.muted)
                } else {
                    Text("Due")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showDueDatePicker) { dueDatePickerPopover }
    }

    // MARK: - Due date badge: todayGrouped (line 1, larger)

    private var dueDateBadgeGrouped: some View {
        Button {
            openDueDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
                Text(DateFormatters.relativeDate(from: task.dueDate))
                    .font(.system(size: 13))
                    .foregroundStyle(isOverdue ? Theme.red : Theme.muted)
            }
        }
        .buttonStyle(.cadencePlain)
        .padding(.trailing, 8)
        .popover(isPresented: $showDueDatePicker) { dueDatePickerPopover }
    }

    // MARK: - Due date badge: list style (line 1, days-left text)

    private var dueDateBadgeList: some View {
        Button {
            openDueDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
                Text(DateFormatters.relativeDate(from: task.dueDate))
                    .font(.system(size: 13))
                    .foregroundStyle(isOverdue ? Theme.red : Theme.muted)
            }
        }
        .buttonStyle(.cadencePlain)
        .padding(.trailing, 8)
        .popover(isPresented: $showDueDatePicker) { dueDatePickerPopover }
    }

    // MARK: - Date picker popover (shared)

    private var dueDatePickerPopover: some View {
        VStack(spacing: 0) {
            MonthCalendarPanel(
                selection: $dueDatePickerDate,
                viewMonth: $dueDateViewMonth,
                isOpen: Binding(
                    get: { showDueDatePicker },
                    set: { newVal in
                        if !newVal { task.dueDate = DateFormatters.dateKey(from: dueDatePickerDate) }
                        showDueDatePicker = newVal
                    }
                )
            )
            if !task.dueDate.isEmpty {
                Divider().background(Theme.borderSubtle)
                Button("Clear date") { task.dueDate = ""; showDueDatePicker = false }
                    .font(.system(size: 11)).foregroundStyle(Theme.red)
                    .buttonStyle(.cadencePlain).padding(.vertical, 8)
            }
        }
    }

    private var doDatePickerPopover: some View {
        VStack(spacing: 0) {
            MonthCalendarPanel(
                selection: $doDatePickerDate,
                viewMonth: $doDateViewMonth,
                isOpen: Binding(
                    get: { showDoDatePicker },
                    set: { newVal in
                        if !newVal { task.scheduledDate = DateFormatters.dateKey(from: doDatePickerDate) }
                        showDoDatePicker = newVal
                    }
                )
            )
            if !task.scheduledDate.isEmpty {
                Divider().background(Theme.borderSubtle)
                Button("Clear date") { task.scheduledDate = ""; showDoDatePicker = false }
                    .font(.system(size: 11)).foregroundStyle(Theme.red)
                    .buttonStyle(.cadencePlain).padding(.vertical, 8)
            }
        }
    }

    // MARK: - Helpers

    private func openDueDatePicker() {
        let resolved = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
        dueDatePickerDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        dueDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showDueDatePicker.toggle()
    }

    private func openDoDatePicker() {
        let resolved = task.scheduledDate.isEmpty ? Date() : (DateFormatters.date(from: task.scheduledDate) ?? Date())
        doDatePickerDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        doDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showDoDatePicker.toggle()
    }

    private var taskContainerBinding: Binding<TaskContainerSelection> {
        Binding(
            get: {
                if let a = task.area    { return .area(a.id) }
                if let p = task.project { return .project(p.id) }
                return .inbox
            },
            set: { newSelection in
                switch newSelection {
                case .inbox:
                    task.area = nil; task.project = nil; task.context = nil; task.sectionName = TaskSectionDefaults.defaultName
                case .area(let id):
                    if let area = areas.first(where: { $0.id == id }) {
                        task.area = area; task.project = nil; task.context = area.context; task.sectionName = area.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                case .project(let id):
                    if let project = projects.first(where: { $0.id == id }) {
                        task.project = project; task.area = nil; task.context = project.context; task.sectionName = project.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                }
            }
        )
    }

    private var metaDivider: some View {
        Rectangle().fill(Theme.borderSubtle).frame(width: 0.5, height: 12)
    }

    private var isOverdue: Bool {
        guard !task.dueDate.isEmpty, !task.isDone else { return false }
        return task.dueDate < DateFormatters.todayKey()
    }

    private var isOverdo: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
    }

    private var isDoToday: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return task.scheduledDate == DateFormatters.todayKey()
    }

    private var isPendingCompletion: Bool {
        taskCompletionAnimationManager.isPending(task)
    }

    @ViewBuilder
    private var completionAnimatedBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isHovered ? Theme.surfaceElevated.opacity(1.0) : Theme.surface)
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.blue.opacity(0.05))
                }
            }
            .overlay {
                if isPendingCompletion {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.green.opacity(0.24))
                                .frame(
                                    width: proxy.size.width * taskCompletionAnimationManager.progress(for: task, now: context.date),
                                    alignment: .leading
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
    }


}

// MARK: - Subtask Row

struct SubtaskRow: View {
    @Bindable var subtask: Subtask
    var showDelete: Bool = false
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button { subtask.isDone.toggle() } label: {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(subtask.isDone ? Theme.green : Theme.dim.opacity(0.6))
            }
            .buttonStyle(.cadencePlain)

            Text(subtask.title.isEmpty ? "Untitled" : subtask.title)
                .font(.system(size: 13))
                .foregroundStyle(subtask.isDone ? Theme.dim : Theme.muted)
                .strikethrough(subtask.isDone, color: Theme.dim)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showDelete, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim.opacity(0.5))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Container Picker Badge

struct ContainerPickerBadge: View {
    @Binding var selection: TaskContainerSelection
    let contexts: [Context]
    let areas:    [Area]
    let projects: [Project]

    @State private var showPicker = false

    private var label: String {
        switch selection {
        case .inbox:           return "Inbox"
        case .area(let id):    return areas.first(where: { $0.id == id })?.name ?? "Area"
        case .project(let id): return projects.first(where: { $0.id == id })?.name ?? "Project"
        }
    }
    private var labelIcon: String {
        switch selection {
        case .inbox:           return "tray"
        case .area(let id):    return areas.first(where: { $0.id == id })?.icon ?? "tray"
        case .project(let id): return projects.first(where: { $0.id == id })?.icon ?? "tray"
        }
    }
    private var labelColor: Color {
        switch selection {
        case .inbox:           return Theme.dim
        case .area(let id):    return areas.first(where: { $0.id == id }).map { Color(hex: $0.colorHex) } ?? Theme.dim
        case .project(let id): return projects.first(where: { $0.id == id }).map { Color(hex: $0.colorHex) } ?? Theme.dim
        }
    }

    private var groupedContainers: [(context: Context, areas: [Area], projects: [Project])] {
        contexts.compactMap { context in
            let matchingAreas = areas
                .filter { $0.context?.id == context.id }
                .sorted { $0.order < $1.order }
            let matchingProjects = projects
                .filter { $0.context?.id == context.id }
                .sorted { $0.order < $1.order }
            guard !matchingAreas.isEmpty || !matchingProjects.isEmpty else { return nil }
            return (context, matchingAreas, matchingProjects)
        }
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: labelIcon).font(.system(size: 10)).foregroundStyle(labelColor)
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 2) {
                containerRow(icon: "tray", name: "Inbox", color: Theme.dim, tag: .inbox)

                if !groupedContainers.isEmpty {
                    Divider().background(Theme.borderSubtle).padding(.vertical, 2)

                    ForEach(groupedContainers, id: \.context.id) { group in
                        Text(group.context.name.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(hex: group.context.colorHex))
                            .kerning(0.6)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 2)

                        ForEach(group.areas) { area in
                            containerRow(icon: area.icon, name: area.name, color: Color(hex: area.colorHex), tag: .area(area.id))
                        }

                        ForEach(group.projects) { project in
                            containerRow(icon: project.icon, name: project.name, color: Color(hex: project.colorHex), tag: .project(project.id))
                        }
                    }
                }
            }
            .padding(.vertical, 6).frame(minWidth: 190).background(Theme.surfaceElevated)
        }
    }

    @ViewBuilder
    private func containerRow(icon: String, name: String, color: Color, tag: TaskContainerSelection) -> some View {
        let isSelected = selection == tag
        Button { selection = tag; showPicker = false } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).frame(width: 16)
                Text(name).font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .background(isSelected ? Theme.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
        .modifier(TaskPickerRowHover())
    }
}

struct TaskSectionPickerBadge: View {
    @Binding var selection: String
    let sections: [String]

    @State private var showPicker = false

    private var resolvedSections: [String] {
        let cleaned = sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? [TaskSectionDefaults.defaultName] : cleaned
    }

    private var label: String {
        resolvedSections.first(where: { $0.caseInsensitiveCompare(selection) == .orderedSame }) ?? TaskSectionDefaults.defaultName
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SECTIONS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.6)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)

                ForEach(resolvedSections, id: \.self) { section in
                    sectionRow(section)
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 170)
            .background(Theme.surfaceElevated)
        }
    }

    @ViewBuilder
    private func sectionRow(_ section: String) -> some View {
        let isSelected = section.caseInsensitiveCompare(selection) == .orderedSame
        Button {
            selection = section
            showPicker = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.caseInsensitiveCompare(TaskSectionDefaults.defaultName) == .orderedSame ? "square.grid.2x2" : "rectangle.split.3x1")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 16)
                Text(section)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? Theme.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
        .modifier(TaskPickerRowHover())
    }
}

private struct TaskPickerRowHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

private struct TodayDueSectionCard: View {
    let item: TodayDueSectionItem
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.amber)
                .frame(width: 3)
                .padding(.leading, 8)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.sectionName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Image(systemName: item.listIcon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(item.listColor)
                            Text(item.listName)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    Spacer(minLength: 6)

                    Text("Due Today")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.amber.opacity(0.12))
                        .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    infoChip(icon: "checklist", text: item.taskCount == 1 ? "1 open task" : "\(item.taskCount) open tasks", tint: Theme.blue)
                    if item.completedTaskCount > 0 {
                        infoChip(icon: "checkmark.circle.fill", text: item.completedTaskCount == 1 ? "1 done" : "\(item.completedTaskCount) done", tint: Theme.green)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Theme.surfaceElevated.opacity(0.9) : Theme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Theme.amber.opacity(0.28) : .white.opacity(0.04), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func infoChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#endif
