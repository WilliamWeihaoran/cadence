#if os(macOS)
import SwiftUI
import SwiftData

enum TaskDetailPresentationMode {
    case full
    case subtasksOnly
}

struct TaskDetailHeaderSection: View {
    @Bindable var task: AppTask
    @Binding var showPriorityPicker: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: task.containerColor).opacity(0.22))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: task.scheduledStartMin >= 0 ? "calendar.badge.clock" : "checklist")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: task.containerColor))
                }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Task title", text: $task.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                Text(scheduleDescriptor)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { showPriorityPicker.toggle() } label: {
                TaskPriorityPill(priority: task.priority, selected: task.priority != .none)
            }
            .buttonStyle(.cadencePlain)
            .fixedSize()
            .popover(isPresented: $showPriorityPicker, arrowEdge: .bottom) {
                TaskPriorityPickerPopover(priority: $task.priority, isPresented: $showPriorityPicker)
            }
        }
    }

    private var timeRange: String {
        TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledStartMin + max(task.estimatedMinutes, 5))
    }

    private var scheduleDescriptor: String {
        if task.scheduledStartMin >= 0 {
            return "Scheduled • \(timeRange)"
        }
        if !task.dueDate.isEmpty {
            return "Due \(DateFormatters.relativeDate(from: task.dueDate))"
        }
        return "Inbox task"
    }
}

struct TaskPriorityPickerPopover: View {
    @Binding var priority: TaskPriority
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskPriority.allCases, id: \.self) { value in
                Button {
                    priority = value
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.priorityColor(value))
                            .frame(width: 7, height: 7)
                        Text(value.label)
                            .font(.system(size: 13))
                            .foregroundStyle(priority == value ? Theme.text : Theme.muted)
                        Spacer()
                        if priority == value {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(priority == value ? Theme.blue.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .modifier(InspectorPickerHover())
            }
        }
        .padding(6)
        .frame(width: 160)
    }
}

struct TaskDetailMetadataSection: View {
    @Bindable var task: AppTask
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let taskContainerBinding: Binding<TaskContainerSelection>

    var body: some View {
        TaskInspectorInfoCard {
            TaskInspectorDetailRow(title: "Time", icon: "clock") {
                Text(task.scheduledStartMin >= 0 ? timeRange : "Not time-blocked")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(task.scheduledStartMin >= 0 ? Theme.text : Theme.dim)
            }

            TaskInspectorDetailRow(title: "Do", icon: "calendar") {
                TaskInspectorDateControl(
                    label: "Set do",
                    icon: "calendar",
                    activeColor: Theme.blue,
                    isOn: Binding(
                        get: { !task.scheduledDate.isEmpty },
                        set: { isOn in
                            if !isOn { task.scheduledDate = "" }
                        }
                    ),
                    date: Binding(
                        get: { DateFormatters.date(from: task.scheduledDate) ?? Date() },
                        set: { task.scheduledDate = DateFormatters.dateKey(from: $0) }
                    )
                )
            }

            TaskInspectorDetailRow(title: "Due", icon: "calendar.badge.exclamationmark") {
                TaskInspectorDateControl(
                    label: "Set due",
                    icon: "calendar.badge.exclamationmark",
                    activeColor: Theme.red,
                    isOn: Binding(
                        get: { !task.dueDate.isEmpty },
                        set: { isOn in
                            if !isOn { task.dueDate = "" }
                        }
                    ),
                    date: Binding(
                        get: { DateFormatters.date(from: task.dueDate) ?? Date() },
                        set: { task.dueDate = DateFormatters.dateKey(from: $0) }
                    )
                )
            }

            TaskInspectorDetailRow(title: "List", icon: "tray.full") {
                ContainerPickerBadge(selection: taskContainerBinding, contexts: contexts, areas: areas, projects: projects)
            }

            TaskInspectorDetailRow(title: "Estimated", icon: "clock") {
                EstimatePickerControl(value: $task.estimatedMinutes)
            }

            TaskInspectorDetailRow(title: "Actual", icon: "clock.badge.checkmark") {
                MinutesField(value: $task.actualMinutes)
            }
        }
    }

    private var timeRange: String {
        TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledStartMin + max(task.estimatedMinutes, 5))
    }
}

struct TaskDetailNotesSection: View {
    @Bindable var task: AppTask

    var body: some View {
        TaskInspectorInfoCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                TextEditor(text: Binding(
                    get: { task.notes },
                    set: { task.notes = $0 }
                ))
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 44)
                .padding(8)
                .background(Theme.surfaceElevated.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct TaskDetailSubtasksSection: View {
    @Bindable var task: AppTask
    @Binding var newSubtaskTitle: String
    @FocusState.Binding var subtaskFieldFocused: Bool
    let onAddSubtask: () -> Void
    let onDeleteSubtask: (Subtask) -> Void

    var body: some View {
        TaskInspectorInfoCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Subtasks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                let sortedSubtasks = (task.subtasks ?? []).sorted { $0.order < $1.order }
                ForEach(sortedSubtasks) { subtask in
                    SubtaskRow(subtask: subtask, showDelete: true) {
                        onDeleteSubtask(subtask)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim.opacity(0.6))
                    TextField("Add subtask…", text: $newSubtaskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .focused($subtaskFieldFocused)
                        .onSubmit { onAddSubtask() }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct TaskDetailActionsSection: View {
    @Bindable var task: AppTask

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if task.isDone {
                    task.completedAt = nil
                    task.status = .todo
                } else {
                    task.completedAt = Date()
                    task.status = .done
                }
            } label: {
                Label(task.isDone ? "Unmark Done" : "Mark Done",
                      systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.cadencePlain)

            if task.scheduledStartMin >= 0 {
                Button {
                    SchedulingActions.removeFromCalendar(task)
                    task.scheduledStartMin = -1
                    task.scheduledDate = ""
                } label: {
                    Label("Unschedule", systemImage: "calendar.badge.minus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.cadencePlain)
            }
        }
    }
}
#endif
