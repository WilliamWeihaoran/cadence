#if os(macOS)
import SwiftUI
import SwiftData

enum TasksPanelMode {
    case todayOverview
    case byDoDate
}

struct TasksPanel: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
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
        let excludedIDs = Set(overdue.map(\.id)).union(dueTodayTasks.map(\.id))
        return allTasks.filter {
            !$0.isDone &&
            !$0.isCancelled &&
            $0.scheduledDate == todayKey &&
            !excludedIDs.contains($0.id)
        }
    }

    private var byDoDateTodayTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && $0.scheduledDate == todayKey }
    }

    private var byDoDateUpcomingTasks: [AppTask] {
        let todayIDs = Set(byDoDateTodayTasks.map(\.id))
        return allTasks.filter {
            !$0.isDone &&
            !$0.isCancelled &&
            !taskIsUnscheduled($0) &&
            $0.scheduledDate != todayKey &&
            !todayIDs.contains($0.id)
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
                        if !overdue.isEmpty { taskSection(label: "Overdue", tasks: overdue, labelColor: Theme.red) }
                        if !dueTodayTasks.isEmpty { taskSection(label: "Due Today", tasks: dueTodayTasks, labelColor: Theme.blue) }
                        if !doTodayTasks.isEmpty { taskSection(label: "Do Today", tasks: doTodayTasks, labelColor: Theme.amber) }
                    } else {
                        if !byDoDateTodayTasks.isEmpty { taskSection(label: "Do Today", tasks: byDoDateTodayTasks, labelColor: Theme.blue) }
                        if !byDoDateUpcomingTasks.isEmpty { taskSection(label: "Scheduled", tasks: byDoDateUpcomingTasks, labelColor: Theme.dim) }
                        if !byDoDateUnscheduledTasks.isEmpty { taskSection(label: "Unscheduled", tasks: byDoDateUnscheduledTasks, labelColor: Theme.amber) }
                    }
                    if !doneTasks.isEmpty { taskSection(label: "Done", tasks: doneTasks, labelColor: Theme.green) }
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
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
        .background(Theme.surface)
    }

    @ViewBuilder
    private func taskSection(label: String, tasks: [AppTask], labelColor: Color) -> some View {
        Section {
            ForEach(tasks) { task in
                MacTaskRow(task: task)
                    .draggable(task.id.uuidString)
            }
        } header: {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(labelColor)
                .kerning(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
        }
    }

    private var isEmptyState: Bool {
        switch mode {
        case .todayOverview:
            return overdue.isEmpty && dueTodayTasks.isEmpty && doTodayTasks.isEmpty && doneTasks.isEmpty
        case .byDoDate:
            return byDoDateTodayTasks.isEmpty && byDoDateUpcomingTasks.isEmpty && byDoDateUnscheduledTasks.isEmpty && doneTasks.isEmpty
        }
    }

    private var panelTitle: String {
        switch mode {
        case .todayOverview: return "Today"
        case .byDoDate: return "By Do Date"
        }
    }

    private func taskIsUnscheduled(_ task: AppTask) -> Bool {
        task.scheduledDate.isEmpty || task.scheduledStartMin < 0
    }
}

private struct TasksPanelHeader: View {
    let mode: TasksPanelMode

    @Environment(TaskCreationManager.self) private var taskCreationManager

    private var title: String {
        switch mode {
        case .todayOverview:
            return "Today"
        case .byDoDate:
            return "By Do Date"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TASKS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .kerning(0.8)
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                }

                Spacer()

                Button {
                    switch mode {
                    case .todayOverview:
                        taskCreationManager.present(doDateKey: DateFormatters.todayKey())
                    case .byDoDate:
                        taskCreationManager.present()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("New Task")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if mode == .todayOverview {
                Button {
                    taskCreationManager.present(doDateKey: DateFormatters.todayKey())
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.blue.opacity(0.14))
                                .frame(width: 38, height: 38)
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Capture something for today")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Opens the full task creator with Do Date already set to today.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }

                        Spacer()

                        Text("Ctrl-Space")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .padding(12)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.borderSubtle)
                    )
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, mode == .todayOverview ? 10 : 12)
    }
}

// MARK: - Task Row (always 2-row inline editing)

struct MacTaskRow: View {
    @Bindable var task: AppTask
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager

    @State private var showDatePicker = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var dueDateViewMonth: Date = Date()
    @State private var showPriorityPicker = false
    @State private var isHovered = false
    @State private var showTaskInspector = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Priority color bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.priorityColor(task.priority))
                .frame(width: 3, height: 32)
                .padding(.leading, 8)

            // Checkbox
            Button {
                task.status = task.isDone ? .todo : .done
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            // Title (lower layout priority — compresses first when space is tight)
            TextField("Task title", text: $task.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                .strikethrough(task.isDone, color: Theme.dim)
                .lineLimit(1)
                .layoutPriority(-1)
                .focused($titleFocused)

            // Metadata: priority | due | list (fixed size — never squishes)
            HStack(spacing: 6) {
                // Priority Badge
                Button { showPriorityPicker.toggle() } label: {
                    HStack(spacing: 4) {
                        if task.priority == .none {
                            Text("—").font(.system(size: 10)).foregroundStyle(Theme.dim)
                        } else {
                            Circle().fill(Theme.priorityColor(task.priority)).frame(width: 6, height: 6)
                        }
                        Text(task.priority.label).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold)).foregroundStyle(Theme.dim)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPriorityPicker) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Button {
                                task.priority = p
                                showPriorityPicker = false
                            } label: {
                                HStack(spacing: 8) {
                                    if p == .none {
                                        Text("—").font(.system(size: 12)).foregroundStyle(Theme.dim).frame(width: 7)
                                    } else {
                                        Circle().fill(Theme.priorityColor(p)).frame(width: 7, height: 7)
                                    }
                                    Text(p.label).font(.system(size: 12)).foregroundStyle(Theme.text)
                                    Spacer()
                                    if task.priority == p {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.blue)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6).frame(minWidth: 140).background(Theme.surfaceElevated)
                }

                Rectangle().fill(Theme.borderSubtle).frame(width: 0.5, height: 14)

                // Due date
                Button {
                    let resolved = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
                    dueDatePickerDate = resolved
                    var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
                    comps.day = 1
                    dueDateViewMonth = Calendar.current.date(from: comps) ?? resolved
                    showDatePicker.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar").font(.system(size: 9))
                        Text(task.dueDate.isEmpty ? "Due" : shortDate(task.dueDate)).font(.system(size: 10))
                    }
                    .foregroundStyle(isOverdue ? Theme.red : (task.dueDate.isEmpty ? Theme.dim : Theme.muted))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePicker) {
                    VStack(spacing: 0) {
                        MonthCalendarPanel(
                            selection: $dueDatePickerDate,
                            viewMonth: $dueDateViewMonth,
                            isOpen: Binding(
                                get: { showDatePicker },
                                set: { newVal in
                                    if !newVal {
                                        task.dueDate = DateFormatters.dateKey(from: dueDatePickerDate)
                                    }
                                    showDatePicker = newVal
                                }
                            )
                        )
                        if !task.dueDate.isEmpty {
                            Divider().background(Theme.borderSubtle)
                            Button("Clear date") { task.dueDate = ""; showDatePicker = false }
                                .font(.system(size: 11)).foregroundStyle(Theme.red).buttonStyle(.plain).padding(.vertical, 8)
                        }
                    }
                }

                Rectangle().fill(Theme.borderSubtle).frame(width: 0.5, height: 14)

                // List picker
                ContainerPickerBadge(task: task, areas: areas, projects: projects)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Theme.surfaceElevated.opacity(0.9) : Theme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Theme.blue.opacity(0.28) : .white.opacity(0.04), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(height: 0.5)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredTaskManager.beginHovering(task)
                hoveredEditableManager.beginHovering(id: "task-row-\(task.id.uuidString)") {
                    showTaskInspector = true
                }
            } else {
                hoveredTaskManager.endHovering(task)
                hoveredEditableManager.endHovering(id: "task-row-\(task.id.uuidString)")
            }
        }
        .popover(isPresented: $showTaskInspector, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
    }

    private var isOverdue: Bool {
        guard !task.dueDate.isEmpty, !task.isDone else { return false }
        return task.dueDate < DateFormatters.todayKey()
    }

    private func shortDate(_ s: String) -> String {
        DateFormatters.shortDateString(from: s)
    }

}
// MARK: - Container Picker Badge

struct ContainerPickerBadge: View {
    @Bindable var task: AppTask
    let areas: [Area]
    let projects: [Project]

    @State private var showPicker = false

    private var label: String {
        if let a = task.area    { return a.name }
        if let p = task.project { return p.name }
        return "Inbox"
    }
    private var labelIcon: String {
        if let a = task.area    { return a.icon }
        if let p = task.project { return p.icon }
        return "tray"
    }
    private var labelColor: Color {
        if let a = task.area    { return Color(hex: a.colorHex) }
        if let p = task.project { return Color(hex: p.colorHex) }
        return Theme.dim
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: labelIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(labelColor)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 2) {
                // Inbox
                containerRow(icon: "tray", name: "Inbox", color: Theme.dim,
                             isSelected: task.area == nil && task.project == nil) {
                    task.area = nil; task.project = nil; showPicker = false
                }

                if !areas.isEmpty {
                    Divider().background(Theme.borderSubtle).padding(.vertical, 2)
                    Text("AREAS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .kerning(0.6)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                    ForEach(areas) { area in
                        containerRow(icon: area.icon, name: area.name, color: Color(hex: area.colorHex),
                                     isSelected: task.area?.id == area.id) {
                            task.area = area; task.project = nil; showPicker = false
                        }
                    }
                }

                if !projects.isEmpty {
                    Divider().background(Theme.borderSubtle).padding(.vertical, 2)
                    Text("PROJECTS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .kerning(0.6)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                    ForEach(projects) { project in
                        containerRow(icon: project.icon, name: project.name, color: Color(hex: project.colorHex),
                                     isSelected: task.project?.id == project.id) {
                            task.project = project; task.area = nil; showPicker = false
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 180)
            .background(Theme.surfaceElevated)
        }
    }

    @ViewBuilder
    private func containerRow(icon: String, name: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#endif
