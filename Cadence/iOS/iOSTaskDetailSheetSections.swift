#if os(iOS)
import SwiftData
import SwiftUI

/// Priority and milestone: the two properties that are neither a date nor placement.
///
/// The group carries no heading, because both rows already name themselves — the well it replaced
/// was titled "Overview", which named nothing that the rows below it did not already say. Each row
/// is the **only** control for its field: priority is displayed by the completion circle in the
/// header and edited here, and nothing else in the sheet writes either value.
struct iOSTaskPropertiesSection: View {
    @Bindable var task: AppTask
    let availableGoals: [Goal]

    @State private var showPriorityPicker = false
    @State private var showMilestonePicker = false

    private var selectedGoal: Goal? { task.goal }

    var body: some View {
        // No `contentSpacing`: `iOSEditorDivider` already pads itself by 9pt on each side, so
        // adding 10 more on both sides counted the same gap twice and gave a 44pt row an 83pt
        // pitch. The divider owns the spacing between rows; the section does not add to it.
        iOSEditorSection(title: nil, style: .ruled) {
            priorityRow
            iOSEditorDivider()
            milestoneRow
        }
    }

    /// The one place priority is set. Its icon is `Theme.dim` like every other ordinary field —
    /// the priority *value* still shows in the picker and in the completion circle's tint, which
    /// is where a priority colour actually earns its place.
    private var priorityRow: some View {
        iOSEditorFieldRow(label: "Priority", systemImage: "flag.fill", color: Theme.dim) {
            iOSChoiceValueButton(
                title: task.priority.label,
                color: task.priority == .none ? Theme.dim : Theme.text,
                // The row is 44pt, but the row is not what you tap — this button is. Without the
                // floor the target is the height of one line of 13pt text, about 18pt.
                minHeight: 44
            ) {
                showPriorityPicker = true
            }
            .popover(isPresented: $showPriorityPicker) {
                iOSChoicePopoverList(
                    rows: TaskPriority.allCases.map { priority in
                        iOSChoiceRow(
                            value: priority,
                            title: priority.label,
                            systemImage: "flag.fill",
                            color: Theme.priorityColor(priority)
                        )
                    },
                    selection: $task.priority,
                    isPresented: $showPriorityPicker
                )
            }
        }
    }

    private var milestoneRow: some View {
        iOSEditorFieldRow(label: "Milestone", systemImage: "target", color: Theme.dim) {
            iOSChoiceValueButton(
                title: selectedGoal.map { $0.title.isEmpty ? "Untitled Milestone" : $0.title } ?? "None",
                color: selectedGoal == nil ? Theme.dim : Theme.text,
                minHeight: 44
            ) {
                showMilestonePicker = true
            }
            .popover(isPresented: $showMilestonePicker) {
                iOSChoicePopoverList(
                    rows: [iOSChoiceRow<UUID?>(value: nil, title: "None", systemImage: "circle.dashed", color: Theme.dim)]
                        + availableGoals.map { goal in
                            iOSChoiceRow(
                                value: Optional(goal.id),
                                title: goal.title.isEmpty ? "Untitled Milestone" : goal.title,
                                systemImage: goal.icon,
                                // A goal's colour is the user's own, and it is what tells two
                                // milestones apart in a list of them.
                                color: Color(hex: goal.colorHex)
                            )
                        },
                    selection: goalSelection,
                    isPresented: $showMilestonePicker
                )
            }
        }
    }

    private var goalSelection: Binding<UUID?> {
        Binding(
            get: { task.goal?.id },
            set: { goalID in
                task.goal = goalID.flatMap { id in availableGoals.first { $0.id == id } }
            }
        )
    }
}

/// "SCHEDULE" — do date, time, due date, repeat, and whatever the focus timer has logged.
///
/// Each date is **one** control: the chip states the day and its popover offers Today / Tomorrow /
/// This Weekend, a month grid, and Clear. The toggle that used to sit beside it was a second
/// affordance for the same field, and the pair could disagree — the toggle said "on" while the
/// picker below it showed a day the task did not have.
struct iOSTaskScheduleSection: View {
    @Bindable var task: AppTask
    let recurrenceSelection: Binding<TaskRecurrenceRule>
    let hasScheduledDate: Binding<Bool>
    let scheduledDate: Binding<Date>
    let hasDueDate: Binding<Bool>
    let dueDate: Binding<Date>
    let scheduledStartSelection: Binding<Int>
    let scheduledTimeLabel: String

    @State private var showRepeatPicker = false
    @State private var showTimePicker = false

    /// Colour is spent only on what is wrong. A do date in the past and an overdue deadline are the
    /// two things in this well that are, so everything else — including a do date of *today*, which
    /// is the common case — is `Theme.dim`.
    private var isOverdo: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
    }

    private var isOverdue: Bool {
        CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone) == .overdue
    }

    private var hasScheduledStartMin: Bool {
        task.scheduledStartMin >= 0
    }

    var body: some View {
        // Divider-separated rows, so no `contentSpacing` — see the note on the properties section.
        iOSEditorSection(title: "Schedule", style: .ruled) {
            iOSEditorFieldRow(
                label: "Do",
                systemImage: "sun.max.fill",
                color: isOverdo ? Theme.red : Theme.dim
            ) {
                CadenceDatePicker(
                    selection: doDateBinding,
                    placeholder: hasScheduledDate.wrappedValue ? nil : "No do date",
                    minHeight: 44,
                    showsClear: hasScheduledDate.wrappedValue,
                    onClear: { hasScheduledDate.wrappedValue = false }
                )
            }

            if hasScheduledDate.wrappedValue {
                iOSEditorDivider()
                timeRow
            }

            iOSEditorDivider()

            iOSEditorFieldRow(
                label: "Due",
                systemImage: "flag.fill",
                color: isOverdue ? Theme.red : Theme.dim
            ) {
                CadenceDatePicker(
                    selection: dueDateBinding,
                    placeholder: hasDueDate.wrappedValue ? nil : "No due date",
                    minHeight: 44,
                    showsClear: hasDueDate.wrappedValue,
                    onClear: { hasDueDate.wrappedValue = false }
                )
            }

            iOSEditorDivider()
            repeatRow

            // Logged time is **measured**, not typed: the focus timer writes it. This row used to
            // be an editable minutes picker, which invited a user to overwrite a measurement by
            // hand — macOS deleted its equivalent "Actual" row for the same reason. It appears
            // only when there is something to report.
            if let logged = CadenceTaskInspectorSupport.loggedLabel(minutes: task.actualMinutes) {
                iOSEditorDivider()
                iOSEditorFieldRow(label: "Logged", systemImage: "timer", color: Theme.dim) {
                    Text(logged)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }

    /// Picking a day is what gives the task a do date; there is no separate switch to flip first.
    private var doDateBinding: Binding<Date> {
        Binding(
            get: { scheduledDate.wrappedValue },
            set: { newValue in
                scheduledDate.wrappedValue = newValue
                hasScheduledDate.wrappedValue = true
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { dueDate.wrappedValue },
            set: { newValue in
                dueDate.wrappedValue = newValue
                hasDueDate.wrappedValue = true
            }
        )
    }

    /// One control, again: "No time" is the first row of the same picker that sets a time, rather
    /// than a toggle beside it that could contradict the value shown.
    private var timeRow: some View {
        iOSEditorFieldRow(label: "Time", systemImage: "clock.fill", color: Theme.dim) {
            iOSChoiceValueButton(
                title: scheduledTimeLabel,
                color: hasScheduledStartMin ? Theme.text : Theme.dim,
                minHeight: 44
            ) {
                showTimePicker = true
            }
            .popover(isPresented: $showTimePicker) {
                iOSChoicePopoverList(
                    rows: [iOSChoiceRow(value: -1, title: "No time", color: Theme.dim)]
                        + stride(from: 0, to: 1440, by: 15).map { minute in
                            iOSChoiceRow(
                                value: minute,
                                title: TimeFormatters.timeString(from: minute),
                                color: Theme.dim,
                                id: AnyHashable(minute)
                            )
                        },
                    selection: scheduledStartSelection,
                    isPresented: $showTimePicker
                )
            }
        }
    }

    private var repeatRow: some View {
        iOSEditorFieldRow(label: "Repeat", systemImage: task.recurrenceRule.systemImage, color: Theme.dim) {
            iOSChoiceValueButton(
                title: task.recurrenceRule.label,
                color: task.recurrenceRule == .none ? Theme.dim : Theme.text,
                minHeight: 44
            ) {
                showRepeatPicker = true
            }
            .popover(isPresented: $showRepeatPicker) {
                iOSChoicePopoverList(
                    rows: TaskRecurrenceRule.allCases.map { rule in
                        iOSChoiceRow(value: rule, title: rule.label, systemImage: rule.systemImage, color: Theme.dim)
                    },
                    selection: recurrenceSelection,
                    isPresented: $showRepeatPicker
                )
            }
        }
    }
}

struct iOSTaskSubtasksSection: View {
    let subtasks: [Subtask]
    let newSubtaskTitle: Binding<String>
    let canAddSubtask: Bool
    let onAdd: () -> Void
    let onDelete: (Subtask) -> Void

    var body: some View {
        iOSEditorSection(title: "Subtasks", style: .ruled, contentSpacing: 10) {
            subtaskList
            subtaskComposer
        }
    }

    @ViewBuilder
    private var subtaskList: some View {
        if !subtasks.isEmpty {
            VStack(spacing: 0) {
                ForEach(subtasks) { subtask in
                    iOSSubtaskRow(subtask: subtask) {
                        onDelete(subtask)
                    }
                }
            }
        }
    }

    /// No "No subtasks" placeholder: the field directly below it is captioned "Add subtask", which
    /// says the same thing and can be typed into.
    private var subtaskComposer: some View {
        HStack(spacing: 8) {
            TextField("Add subtask", text: newSubtaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Theme.surfaceElevated.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .onSubmit(onAdd)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 44, height: 44)
                    .background(canAddSubtask ? Theme.blue : Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.iosPressable)
            .disabled(!canAddSubtask)
            .opacity(canAddSubtask ? 1 : 0.45)
            .accessibilityLabel("Add subtask")
        }
    }
}

/// "NOTES" — the markdown editor and nothing else. Tags used to live under this heading, which read
/// as "these tag the note"; they are the task's tags and now sit under the title where the same
/// move put them on macOS.
struct iOSTaskNotesSection: View {
    let notesText: Binding<String>
    let isFocused: Binding<Bool>
    let referenceNotes: [Note]
    let referenceTasks: [AppTask]
    let onOpenReference: (MarkdownReferenceDisplayTarget) -> Void

    var body: some View {
        iOSEditorSection(title: "Notes", style: .ruled, contentSpacing: 10) {
            iOSMarkdownEditingSurface(
                text: notesText,
                isFocused: isFocused,
                placeholder: "Add notes...",
                referenceNotes: referenceNotes,
                referenceTasks: referenceTasks,
                onOpenReference: onOpenReference
            )
            .iOSMarkdownWell()
        }
    }
}

/// The two status transitions a checkbox cannot express, under no heading — a label over two
/// buttons names what the buttons already say.
///
/// Between these and the header's completion circle, every status value has exactly one control:
/// the circle owns `done`, "Start" owns `inProgress`, "Cancel" owns `cancelled`, and each of the
/// two buttons is its own undo back to `todo`. Deleting stays on the toolbar rather than gaining a
/// second home down here.
struct iOSTaskStatusActionsSection: View {
    @Bindable var task: AppTask
    let onSetStatus: (TaskStatus) -> Void

    var body: some View {
        iOSEditorSection(title: nil, style: .ruled, contentSpacing: 10) {
            HStack(spacing: 10) {
                ForEach(CadenceTaskInspectorSupport.StatusAction.allCases, id: \.self) { action in
                    let isActive = action.isActive(task.status)

                    iOSActionButton(
                        title: action.title(for: task.status),
                        systemImage: action.systemImage(for: task.status),
                        role: isActive ? .primary : .secondary,
                        size: .compact,
                        tint: isActive ? CadenceTaskPresentationSupport.statusColor(action.status) : Theme.muted,
                        fullWidth: true
                    ) {
                        onSetStatus(action.target(from: task.status))
                    }
                }
            }
        }
    }
}
#endif
