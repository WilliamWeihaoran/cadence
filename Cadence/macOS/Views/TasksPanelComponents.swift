#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct TasksPanelHeader: View {
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

struct MacTaskRow: View {
    @Bindable var task: AppTask
    var style: MacTaskRowStyle = .standard
    var contexts: [Context] = []
    var areas: [Area] = []
    var projects: [Project] = []
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self)    private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(FocusManager.self)          private var focusManager
    @Environment(TaskCompletionAnimationManager.self) private var taskCompletionAnimationManager

    @State private var showDueDatePicker  = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var dueDateViewMonth:  Date = Date()
    @State private var showDoDatePicker   = false
    @State private var doDatePickerDate: Date = Date()
    @State private var doDateViewMonth:   Date = Date()
    @State private var isHovered          = false
    @State private var showTaskInspector  = false
    @State private var isDoDateHovered    = false
    @State private var isDueDateHovered   = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(task.isDone ? Theme.dim.opacity(0.4) : Theme.priorityColor(task.priority))
                .frame(width: 3)
                .padding(.leading, 8)
                .padding(.vertical, 3)

            Button {
                taskCompletionAnimationManager.toggleCompletion(for: task)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : (isPendingCompletion ? "circle.inset.filled" : "circle"))
                    .foregroundStyle(task.isDone || isPendingCompletion ? Theme.green : Theme.dim)
                    .font(.system(size: 18))
            }
            .buttonStyle(.cadencePlain)
            .padding(.horizontal, 8)

            if style != .todayGrouped && !task.scheduledDate.isEmpty {
                doDatePill
                    .padding(.trailing, 8)
            }

            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 15))
                .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                .strikethrough(task.isDone, color: Theme.dim)
                .lineLimit(1)

            if isHovered {
                EstimatePickerControl(value: $task.estimatedMinutes, compact: true)
                    .padding(.leading, 8)

                if !task.isDone && !task.isCancelled {
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
                    .padding(.leading, 6)
                }
            }

            Spacer(minLength: 4)

            if !task.dueDate.isEmpty {
                dueDateBadgeList
            }

            if showsListContextChip {
                ContainerPickerBadge(
                    selection: taskContainerBinding,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    compact: true
                )
                .padding(.leading, 6)
                .padding(.trailing, 6)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { showTaskInspector = true }
        .background(completionAnimatedBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Theme.blue.opacity(0.44) : .white.opacity(0.04), lineWidth: isHovered ? 1.2 : 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(height: 0.5)
        }
        .animation(nil, value: isHovered)
        .animation(nil, value: isDoDateHovered)
        .animation(nil, value: isDueDateHovered)
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

    private var doDatePill: some View {
        Button {
            openDoDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text(DateFormatters.relativeDate(from: task.scheduledDate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        isOverdo
                            ? Theme.red
                            : (isDoToday ? Theme.amber.opacity(0.75) : Theme.dim.opacity(0.68))
                    )
            }
            .underline(isDoDateHovered)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isDoDateHovered ? Theme.surfaceElevated.opacity(0.55) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.cadencePlain)
        .onHover { hovering in
            isDoDateHovered = hovering
            if hovering {
                hoveredTaskManager.beginHoveringDate(.doDate, for: task)
            } else {
                hoveredTaskManager.endHoveringDate(for: task)
            }
        }
        .popover(isPresented: $showDoDatePicker) { doDatePickerPopover }
    }

    private var doDateBadge: some View {
        Button {
            openDoDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(task.scheduledDate.isEmpty ? Theme.dim : .yellow)
                Text(task.scheduledDate.isEmpty ? "Do" : DateFormatters.relativeDate(from: task.scheduledDate))
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isOverdo
                            ? Theme.red
                            : (isDoToday ? .yellow : (task.scheduledDate.isEmpty ? Theme.dim : Theme.muted))
                    )
            }
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showDoDatePicker) { doDatePickerPopover }
    }

    private var dueDateBadgeList: some View {
        Button {
            openDueDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isOverdue ? Theme.red : Theme.dim.opacity(0.68))
                Text(DateFormatters.relativeDate(from: task.dueDate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOverdue ? Theme.red : Theme.dim.opacity(0.68))
            }
            .underline(isDueDateHovered)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isDueDateHovered ? Theme.surfaceElevated.opacity(0.55) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.cadencePlain)
        .padding(.trailing, 8)
        .onHover { hovering in
            isDueDateHovered = hovering
            if hovering {
                hoveredTaskManager.beginHoveringDate(.dueDate, for: task)
            } else {
                hoveredTaskManager.endHoveringDate(for: task)
            }
        }
        .popover(isPresented: $showDueDatePicker) { dueDatePickerPopover }
    }

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

    private var showsDoDateOnFirstRow: Bool {
        style != .todayGrouped
    }

    private var showsListContextChip: Bool {
        style == .standard && !task.containerName.isEmpty
    }

    private var isPendingCompletion: Bool {
        taskCompletionAnimationManager.isPending(task)
    }

    private var urgencyBackgroundTint: Color {
        guard !task.isDone else { return isHovered ? Theme.blue.opacity(0.05) : .clear }
        if isOverdue {
            return Theme.red.opacity(isHovered ? 0.2 : 0.15)
        }
        return isHovered ? Theme.blue.opacity(0.05) : .clear
    }

    @ViewBuilder
    private var completionAnimatedBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isHovered ? Theme.surfaceElevated.opacity(1.0) : Theme.surface)
            .overlay {
                if urgencyBackgroundTint != .clear {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(urgencyBackgroundTint)
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

struct ContainerPickerBadge: View {
    @Binding var selection: TaskContainerSelection
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    var compact: Bool = false

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
                Image(systemName: labelIcon).font(.system(size: compact ? 9 : 10)).foregroundStyle(labelColor)
                Text(label).font(.system(size: compact ? 10 : 11)).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.down").font(.system(size: compact ? 7 : 8, weight: .semibold)).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 6)
            .frame(minHeight: compact ? 21 : 28)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 7))
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

struct TaskPickerRowHover: ViewModifier {
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

struct CollapsibleTaskGroupHeader: View {
    let title: String
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    var accent: Color = Theme.dim
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let overdueCount, overdueCount > 0 {
                    Text("\(overdueCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    Text("/")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                }
                Text("\(regularCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surface.opacity(0.5))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.borderSubtle.opacity(0.75))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .onTapGesture(count: 2, perform: onToggle)
    }
}

struct CompletedSectionHeader: View {
    let count: Int
    var isCollapsed: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        CollapsibleTaskGroupHeader(
            title: "Completed",
            isCollapsed: isCollapsed,
            overdueCount: nil,
            regularCount: count,
            accent: Theme.green,
            onToggle: { onToggle?() }
        )
        .allowsHitTesting(onToggle != nil)
        .overlay {
            if onToggle == nil {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct StaticTaskGroupHeader: View {
    let title: String
    let overdueCount: Int?
    let regularCount: Int

    var body: some View {
        CollapsibleTaskGroupHeader(
            title: title,
            isCollapsed: false,
            overdueCount: overdueCount,
            regularCount: regularCount,
            onToggle: {}
        )
        .allowsHitTesting(false)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
                .allowsHitTesting(false)
        }
    }
}
#endif
