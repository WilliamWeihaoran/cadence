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
            // The header tile *is* the priority control. It used to be a decorative container
            // glyph, with the real priority control duplicated on the right — two affordances
            // for one field.
            Button { showPriorityPicker.toggle() } label: {
                TaskPriorityMarkControl(priority: task.priority)
            }
            .buttonStyle(.cadencePlain)
            .fixedSize()
            .help("Priority")
            .popover(isPresented: $showPriorityPicker, arrowEdge: .bottom) {
                TaskPriorityPickerPopover(priority: $task.priority, isPresented: $showPriorityPicker)
            }

            TaskTitleEntryField(
                title: $task.title,
                priority: $task.priority,
                placeholder: "Task title",
                font: .system(size: 13, weight: .medium),
                previewFont: .system(size: 13, weight: .medium),
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
            .lineSpacing(4)
            // minHeight + .leading centres the single-line title against the 28pt badge while
            // still letting a wrapped title grow downward.
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
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

/// "SCHEDULE" — do date, due date, estimate, repeat. Every row opens the same picker it
/// always has; only the row chrome changed.
struct TaskDetailScheduleGroupSection: View {
    @Bindable var task: AppTask

    var body: some View {
        TaskInspectorRecessedSection(title: "Schedule") {
            TaskInspectorDateControl(
                label: "Do",
                icon: "calendar",
                activeColor: Theme.blue,
                isOn: Binding(
                    get: { !task.scheduledDate.isEmpty },
                    set: { isOn in
                        // Clearing the do date has to unschedule too, or the task keeps a
                        // timeline slot (and a linked calendar event) it no longer has a day
                        // for. Same order as the inspector's Unschedule action.
                        guard !isOn else { return }
                        SchedulingActions.removeFromCalendar(task)
                        task.scheduledStartMin = -1
                        task.scheduledDate = ""
                    }
                ),
                date: Binding(
                    get: { DateFormatters.date(from: task.scheduledDate) ?? Date() },
                    set: { task.scheduledDate = DateFormatters.dateKey(from: $0) }
                )
            )

            TaskInspectorFieldDivider()

            TaskInspectorDateControl(
                label: "Due",
                // App-wide due-date glyph (MacTaskRow, kanban meta). Unrelated to priority,
                // which uses the "!" marks.
                icon: "flag.fill",
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

            TaskInspectorFieldDivider()

            // Glyph tints are the colours these concepts already carry elsewhere in the app:
            // planned time is purple (goal/effort planning), logged time is green (done work).
            TaskInspectorEstimateFieldRow(value: $task.estimatedMinutes, iconColor: Theme.purple)

            TaskInspectorFieldDivider()

            // Rendered unconditionally, like Do/Due/Estimate: when this row was gated on
            // `actualMinutes > 0`, the picker's Clear tore down the very row hosting the open
            // popover, and actual minutes then became unreachable from the inspector.
            TaskInspectorEstimateFieldRow(
                value: $task.actualMinutes,
                label: "Actual",
                icon: "stopwatch",
                iconColor: Theme.green
            )

            TaskInspectorFieldDivider()

            TaskInspectorRecurrenceControl(task: task)
        }
    }
}

/// "PLACEMENT" — list + section. Both rows present the full container/section pickers
/// (search box, arrow-key highlight, the lot); only the trigger is drawn as a field row.
struct TaskDetailPlacementGroupSection: View {
    @Bindable var task: AppTask
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let taskContainerBinding: Binding<TaskContainerSelection>
    let availableSections: [String]

    var body: some View {
        TaskInspectorRecessedSection(title: "Placement") {
            ContainerPickerBadge(
                selection: taskContainerBinding,
                contexts: contexts,
                areas: areas,
                projects: projects,
                inspectorRowLabel: "List"
            )

            TaskInspectorFieldDivider()

            TaskSectionPickerBadge(
                selection: $task.sectionName,
                sections: availableSections,
                inspectorRowLabel: "Section"
            )
        }
    }
}

#endif
