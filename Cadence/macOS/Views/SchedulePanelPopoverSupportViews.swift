#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

enum TaskDetailPresentationMode {
    case full
    case subtasksOnly
}

struct TaskDetailHeaderSection: View {
    @Bindable var task: AppTask
    @Binding var showPriorityPicker: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let tags: [Tag]
    let taskContainerBinding: Binding<TaskContainerSelection>
    let taskTagsBinding: Binding<[Tag]>
    let onCreateTag: (String) -> Tag

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
                TaskTitleEntryField(
                    title: $task.title,
                    priority: $task.priority,
                    placeholder: "Task title",
                    font: .system(size: 16, weight: .bold),
                    previewFont: .system(size: 17, weight: .bold),
                    lineLimit: 1...8,
                    suppressInitialSelection: true,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    allTags: tags,
                    containerSelection: taskContainerBinding,
                    sectionName: $task.sectionName,
                    selectedTags: taskTagsBinding,
                    onCreateTag: onCreateTag
                )
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
                        Text(TaskTitleSupport.priorityMark(for: value))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(value == .none ? Theme.dim : Theme.priorityColor(value))
                            .frame(width: 24, alignment: .leading)
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

struct TaskDetailCompactOverviewSection: View {
    @Bindable var task: AppTask
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let taskContainerBinding: Binding<TaskContainerSelection>
    let availableSections: [String]

    var body: some View {
        TaskInspectorInfoCard {
            // Single narrow column — reads top to bottom like the inspector metaphor
            // rather than a 2-up form grid.
            VStack(alignment: .leading, spacing: 8) {
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

                EstimatePickerControl(value: $task.estimatedMinutes, compact: true)

                TaskInspectorRecurrenceControl(task: task)

                if task.actualMinutes > 0 {
                    MinutesField(value: $task.actualMinutes)
                }

                Divider().background(Theme.borderSubtle.opacity(0.75))

                ContainerPickerBadge(selection: taskContainerBinding, contexts: contexts, areas: areas, projects: projects, compact: true, outlined: true)

                TaskSectionPickerBadge(selection: $task.sectionName, sections: availableSections, compact: true)
            }
        }
    }
}

#endif
