#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct MacTaskRow: View {
    @Bindable var task: AppTask
    var style: MacTaskRowStyle = .standard
    var contexts: [Context] = []
    var areas: [Area] = []
    var projects: [Project] = []
    var allTasks: [AppTask] = []
    var blockedTaskIDs: Set<UUID>? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self)    private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(FocusManager.self)          private var focusManager

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

            TaskCompletionButton(task: task)
                .padding(.horizontal, 8)

            if style != .todayGrouped && !task.scheduledDate.isEmpty {
                doDatePill
                    .padding(.trailing, 8)
            }

            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 15))
                .foregroundStyle(task.isDone || task.isCancelled ? Theme.dim : Theme.text)
                .strikethrough(task.isDone || task.isCancelled, color: Theme.dim)
                .lineLimit(1)

            if task.isCancelled {
                Text("Cancelled")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.dim.opacity(0.14))
                    .clipShape(Capsule())
                    .padding(.leading, 6)
            }

            if isBlocked {
                Text("Blocked")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.amber.opacity(0.14))
                    .clipShape(Capsule())
                    .padding(.leading, 6)
            }

            Spacer(minLength: 4)

            if isHovered && !task.isDone && !task.isCancelled && !isBlocked {
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
                .padding(.trailing, 6)
            }

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
        .background(TaskRowBackground(task: task, isHovered: isHovered, urgencyTint: urgencyBackgroundTint))
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
        .opacity(task.isDone || task.isCancelled ? 0.5 : 1.0)
    }

    private var doDatePill: some View {
        Button {
            openDoDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 10, alignment: .leading)

                ZStack {
                    Text("Tomorrow")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0)

                    Text(DateFormatters.relativeDate(from: task.scheduledDate))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            isOverdo
                                ? Theme.red
                                : (isDoToday ? Theme.amber.opacity(0.75) : Theme.dim.opacity(0.68))
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
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

    private var isBlocked: Bool {
        if let blockedTaskIDs {
            return blockedTaskIDs.contains(task.id)
        }
        return task.isBlocked(in: allTasks)
    }

    private var doDateBadge: some View {
        Button {
            openDoDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(task.scheduledDate.isEmpty ? Theme.dim : .yellow)
                    .frame(width: 12, alignment: .leading)

                ZStack {
                    Text("Tomorrow")
                        .font(.system(size: 13))
                        .opacity(0)

                    Text(task.scheduledDate.isEmpty ? "Do" : DateFormatters.relativeDate(from: task.scheduledDate))
                        .font(.system(size: 13))
                        .foregroundStyle(
                            isOverdo
                                ? Theme.red
                                : (isDoToday ? .yellow : (task.scheduledDate.isEmpty ? Theme.dim : Theme.muted))
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
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
        CadenceQuickDatePopover(
            selection: Binding(
                get: { dueDatePickerDate },
                set: {
                    dueDatePickerDate = $0
                    task.dueDate = DateFormatters.dateKey(from: $0)
                }
            ),
            viewMonth: $dueDateViewMonth,
            isOpen: $showDueDatePicker,
            showsClear: true,
            onClear: {
                task.dueDate = ""
            }
        )
    }

    private var doDatePickerPopover: some View {
        CadenceQuickDatePopover(
            selection: Binding(
                get: { doDatePickerDate },
                set: {
                    doDatePickerDate = $0
                    task.scheduledDate = DateFormatters.dateKey(from: $0)
                }
            ),
            viewMonth: $doDateViewMonth,
            isOpen: $showDoDatePicker,
            showsClear: true,
            onClear: {
                task.scheduledDate = ""
            }
        )
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

    private var urgencyBackgroundTint: Color {
        guard !task.isDone else { return isHovered ? Theme.blue.opacity(0.05) : .clear }
        if isOverdue {
            return Theme.red.opacity(isHovered ? 0.2 : 0.15)
        }
        return isHovered ? Theme.blue.opacity(0.05) : .clear
    }

}

// MARK: - Isolated sub-views to prevent full-row re-renders on animation state changes

private struct TaskCompletionButton: View {
    @Bindable var task: AppTask
    @Environment(TaskCompletionAnimationManager.self) private var manager

    var body: some View {
        Button { handleTap() } label: {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 18))
        }
        .buttonStyle(.cadencePlain)
    }

    private var isPendingCompletion: Bool { manager.isPending(task) }
    private var isPendingCancel: Bool { manager.isPendingCancel(task) }

    private var icon: String {
        if task.isCancelled { return "xmark.circle.fill" }
        if task.isDone      { return "checkmark.circle.fill" }
        if isPendingCancel  { return "xmark.circle" }
        if isPendingCompletion { return "circle.inset.filled" }
        return "circle"
    }

    private var color: Color {
        if task.isCancelled || isPendingCancel { return Theme.dim }
        if task.isDone || isPendingCompletion   { return Theme.green }
        return Theme.dim
    }

    private func handleTap() {
        if isPendingCompletion {
            manager.cancelPending(for: task.id)
            manager.toggleCancellation(for: task)
        } else if isPendingCancel {
            manager.cancelCancelPending(for: task.id)
        } else {
            manager.toggleCompletion(for: task)
        }
    }
}

private struct TaskRowBackground: View {
    let task: AppTask
    let isHovered: Bool
    let urgencyTint: Color
    @Environment(TaskCompletionAnimationManager.self) private var manager

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isHovered ? Theme.surfaceElevated.opacity(1.0) : Theme.surface)
            .overlay {
                if urgencyTint != .clear {
                    RoundedRectangle(cornerRadius: 8).fill(urgencyTint)
                }
            }
            .overlay {
                if manager.isPending(task) {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.green.opacity(0.24))
                                .frame(
                                    width: proxy.size.width * manager.progress(for: task, now: context.date),
                                    alignment: .leading
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if manager.isPendingCancel(task) {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.dim.opacity(0.18))
                                .frame(
                                    width: proxy.size.width * manager.cancelProgress(for: task, now: context.date),
                                    alignment: .leading
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
    }
}

#endif
