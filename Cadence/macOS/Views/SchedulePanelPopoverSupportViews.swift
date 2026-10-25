#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

enum TaskDetailPresentationMode {
    case full
    case subtasksOnly
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
        .frame(width: TaskInspectorPanelMetrics.priorityWidth)
    }
}

/// "SCHEDULE" — do date, due date, repeat. Every row opens the same picker it always has.
/// Estimate left this well for the title row: it is a property of the task, not a date.
struct TaskDetailScheduleGroupSection: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TaskInspectorRecessedSection(title: "Schedule") {
            TaskInspectorDateControl(
                label: "Do",
                icon: "calendar",
                activeColor: Theme.blue,
                childPlacement: .besideInspector,
                isOn: Binding(
                    get: { !task.scheduledDate.isEmpty },
                    set: { isOn in
                        // Clearing the do date has to unschedule too, or the task keeps a
                        // timeline slot (and a linked calendar event) it no longer has a day
                        // for. Same order as the inspector's Unschedule action.
                        guard !isOn else { return }
                        SchedulingActions.removeFromCalendar(task)
                        CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
                    }
                ),
                date: Binding(
                    get: { DateFormatters.date(from: task.scheduledDate) ?? Date() },
                    set: {
                        CadenceTaskDateEditing.setScheduledDate(
                            DateFormatters.dateKey(from: $0),
                            for: task,
                            in: modelContext
                        )
                    }
                )
            )

            TaskInspectorFieldDivider()

            TaskInspectorDateControl(
                label: "Due",
                // App-wide due-date glyph (MacTaskRow, kanban meta). Unrelated to priority,
                // which uses the "!" marks.
                icon: "flag.fill",
                activeColor: Theme.red,
                childPlacement: .besideInspector,
                isOn: Binding(
                    get: { !task.dueDate.isEmpty },
                    set: { isOn in
                        if !isOn { CadenceTaskDateEditing.clearDueDate(task, in: modelContext) }
                    }
                ),
                date: Binding(
                    get: { DateFormatters.date(from: task.dueDate) ?? Date() },
                    set: {
                        CadenceTaskDateEditing.setDueDate(
                            DateFormatters.dateKey(from: $0),
                            for: task,
                            in: modelContext
                        )
                    }
                )
            )

            // No "Actual" row: logged time is measured, not typed. The focus timer accumulates
            // `actualMinutes`, and Focus's log-session popover is where a session gets corrected —
            // an inspector field invited hand-editing a number that is supposed to be a record.
            // The value still reads out wherever it means something, e.g. the timeline's "45/60m".

            TaskInspectorFieldDivider()

            TaskInspectorRecurrenceControl(task: task, childPlacement: .besideInspector)
        }
    }
}

/// `China › Documents` — where the task lives, on one line under the title.
///
/// This replaced a "PLACEMENT" well holding a List row and a Section row. Both segments still
/// present the full container/section pickers (search box, arrow-key highlight, the lot); only
/// the trigger changed.
struct TaskDetailPlacementBreadcrumb: View {
    @Bindable var task: AppTask
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let taskContainerBinding: Binding<TaskContainerSelection>
    let availableSections: [String]

    /// A task in the Inbox has nowhere to be sectioned, so `Inbox › Default` would be a chevron
    /// pointing at a non-choice. The rule itself is `CadenceTaskInspectorSupport`, so the iOS
    /// inspector's breadcrumb hides the segment on exactly the same tasks this one does.
    private var showsSectionSegment: Bool {
        CadenceTaskInspectorSupport.showsSectionSegment(availableSections: availableSections)
    }

    var body: some View {
        HStack(spacing: 2) {
            ContainerPickerBadge(
                selection: taskContainerBinding,
                contexts: contexts,
                areas: areas,
                projects: projects,
                breadcrumbSegment: true
            )

            if showsSectionSegment {
                Text("›")
                    .font(TaskInspectorBreadcrumbMetrics.font)
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)

                TaskSectionPickerBadge(
                    selection: $task.sectionName,
                    sections: availableSections,
                    breadcrumbSegment: true
                )
            }

            Spacer(minLength: 0)
        }
    }
}

#endif
