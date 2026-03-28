#if os(macOS)
import SwiftUI
import SwiftData

struct TasksPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var newTaskTitle = ""
    @FocusState private var quickAddFocused: Bool

    private var todayKey: String { DateFormatters.todayKey() }

    private var overdue: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && !$0.dueDate.isEmpty && $0.dueDate < todayKey }
    }

    private var todayTasks: [AppTask] {
        allTasks.filter { !$0.isDone && !$0.isCancelled && ($0.dueDate == todayKey || $0.scheduledDate == todayKey) }
    }

    private var otherTasks: [AppTask] {
        let overdueIDs = Set(overdue.map { $0.id })
        let todayIDs   = Set(todayTasks.map { $0.id })
        return allTasks.filter {
            !$0.isDone && !$0.isCancelled && !overdueIDs.contains($0.id) && !todayIDs.contains($0.id)
        }
    }

    private var doneTasks: [AppTask] { allTasks.filter { $0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(eyebrow: "Tasks", title: "All Tasks")

            Divider().background(Theme.borderSubtle)

            // Quick-add bar
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.blue)
                    .font(.system(size: 14))
                TextField("Add a task…", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($quickAddFocused)
                    .onSubmit { addTask() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surfaceElevated)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if !overdue.isEmpty    { taskSection(label: "Overdue",  tasks: overdue,    labelColor: Theme.red)   }
                    if !todayTasks.isEmpty { taskSection(label: "Today",    tasks: todayTasks, labelColor: Theme.blue)  }
                    if !otherTasks.isEmpty { taskSection(label: "Upcoming", tasks: otherTasks, labelColor: Theme.dim)   }
                    if !doneTasks.isEmpty  { taskSection(label: "Done",     tasks: doneTasks,  labelColor: Theme.green) }
                    if allTasks.isEmpty {
                        EmptyStateView(message: "No tasks yet", subtitle: "Add a task above to get started", icon: "checkmark.circle")
                            .padding(.top, 40)
                    }
                }
                .padding(.bottom, 16)
            }
        }
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

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = AppTask(title: title)
        task.scheduledDate = todayKey
        modelContext.insert(task)
        newTaskTitle = ""
    }
}

// MARK: - Task Row (always 2-row inline editing)

struct MacTaskRow: View {
    @Bindable var task: AppTask
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var showDatePicker = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var dueDateViewMonth: Date = Date()
    @State private var showPriorityPicker = false

    var body: some View {
        HStack(spacing: 0) {
            // Priority color bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.priorityColor(task.priority))
                .frame(width: 3, height: 32)
                .padding(.leading, 8)

            // Checkbox
            Button {
                task.status = task.isDone ? "todo" : "done"
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

            // Metadata: priority | due | list (fixed size — never squishes)
            HStack(spacing: 6) {
                // Priority Badge
                Button { showPriorityPicker.toggle() } label: {
                    HStack(spacing: 4) {
                        if task.priority == "none" {
                            Text("—").font(.system(size: 10)).foregroundStyle(Theme.dim)
                        } else {
                            Circle().fill(Theme.priorityColor(task.priority)).frame(width: 6, height: 6)
                        }
                        Text(priorityLabel(task.priority)).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold)).foregroundStyle(Theme.dim)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPriorityPicker) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach([("none", "None"), ("low", "Low"), ("medium", "Medium"), ("high", "High")], id: \.0) { p, label in
                            Button {
                                task.priority = p
                                showPriorityPicker = false
                            } label: {
                                HStack(spacing: 8) {
                                    if p == "none" {
                                        Text("—").font(.system(size: 12)).foregroundStyle(Theme.dim).frame(width: 7)
                                    } else {
                                        Circle().fill(Theme.priorityColor(p)).frame(width: 7, height: 7)
                                    }
                                    Text(label).font(.system(size: 12)).foregroundStyle(Theme.text)
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
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(height: 0.5)
        }
    }

    private var isOverdue: Bool {
        guard !task.dueDate.isEmpty, !task.isDone else { return false }
        return task.dueDate < DateFormatters.todayKey()
    }

    private func shortDate(_ s: String) -> String {
        DateFormatters.shortDateString(from: s)
    }

    private func priorityLabel(_ p: String) -> String {
        switch p {
        case "none":   return "None"
        case "low":    return "Low"
        case "medium": return "Med"
        case "high":   return "High"
        default:       return "None"
        }
    }
}
// MARK: - Container Picker Badge

private struct ContainerPickerBadge: View {
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
