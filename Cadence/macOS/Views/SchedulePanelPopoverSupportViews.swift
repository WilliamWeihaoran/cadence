#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

enum TaskDetailPresentationMode {
    case full
    case subtasksOnly
}

/// The inspector's identity block: priority tile + title + estimate on one row, then the task's
/// tags and its `List › Section` breadcrumb indented under the title.
///
/// Tags used to sit under a heading that said NOTES, which read as "these tag the note" — they
/// are the task's tags and always were. Placement used to be a labelled two-row well; here it is
/// one line of context under the title, which is where "where does this live" belongs.
struct TaskDetailHeaderSection: View {
    @Bindable var task: AppTask
    @Binding var showPriorityPicker: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let tags: [Tag]
    let taskContainerBinding: Binding<TaskContainerSelection>
    let taskTagsBinding: Binding<[Tag]>
    let availableSections: [String]
    let onCreateTag: (String) -> Tag

    /// Priority tile width + the title row's spacing, so everything under the title row lines up
    /// with the title text rather than with the tile.
    private static let tileSize: CGFloat = 28
    private static let titleRowSpacing: CGFloat = 10
    private static var titleColumnInset: CGFloat { tileSize + titleRowSpacing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Self.titleRowSpacing) {
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
                // still letting a wrapped title grow downward. The title keeps the flexible slot;
                // the estimate chip is fixed-size, so a long title wraps instead of squeezing it.
                .frame(maxWidth: .infinity, minHeight: Self.tileSize, alignment: .leading)

                TaskInspectorEstimateChip(value: $task.estimatedMinutes)
            }

            VStack(alignment: .leading, spacing: 6) {
                // The task's tags, bound to `task.tags`. `AppTask.notes` is a `String`, so there
                // is no note here to tag — the old placement under NOTES only implied one.
                TagPickerControl(
                    selectedTags: taskTagsBinding,
                    allTags: tags,
                    onCreateTag: onCreateTag,
                    triggerSymbol: "plus"
                )

                TaskDetailPlacementBreadcrumb(
                    task: task,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    taskContainerBinding: taskContainerBinding,
                    availableSections: availableSections
                )
            }
            .padding(.leading, Self.titleColumnInset)
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

/// "SCHEDULE" — do date, due date, repeat. Every row opens the same picker it always has.
/// Estimate left this well for the title row: it is a property of the task, not a date.
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

            // No "Actual" row: logged time is measured, not typed. The focus timer accumulates
            // `actualMinutes`, and Focus's log-session popover is where a session gets corrected —
            // an inspector field invited hand-editing a number that is supposed to be a record.
            // The value still reads out wherever it means something, e.g. the timeline's "45/60m".

            TaskInspectorFieldDivider()

            TaskInspectorRecurrenceControl(task: task)
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
    /// pointing at a non-choice. The segment appears as soon as there is a section worth naming:
    /// more than one to pick from, or a single one the user actually named.
    private var showsSectionSegment: Bool {
        let sections = availableSections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sections.count > 1 { return true }
        guard let only = sections.first else { return false }
        return only.caseInsensitiveCompare(TaskSectionDefaults.defaultName) != .orderedSame
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
