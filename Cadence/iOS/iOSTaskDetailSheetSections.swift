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
                title: selectedGoal.map { $0.title.isEmpty ? CadenceTitleNormalization.defaultMilestoneTitle : $0.title } ?? "None",
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
                                title: goal.title.isEmpty ? CadenceTitleNormalization.defaultMilestoneTitle : goal.title,
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
    /// The one way this section writes an end condition, and deliberately a callback rather than
    /// three bindings: every end edit has to reach
    /// `CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd` — which normalizes the values that
    /// do not belong to the chosen mode and propagates across the series — and it has to ask the
    /// same scope question the rule edit asks. Writing `task.recurrenceEndMode` from here would
    /// bypass both, and silently: the fields are plain stored properties.
    let applyRecurrenceEnd: (TaskRecurrenceEndMode, String, Int) -> Void
    let hasScheduledDate: Binding<Bool>
    let scheduledDate: Binding<Date>
    let hasDueDate: Binding<Bool>
    let dueDate: Binding<Date>
    let scheduledStartSelection: Binding<Int>
    let scheduledTimeLabel: String

    @State private var showRepeatPicker = false
    @State private var showTimePicker = false
    @State private var showEndModePicker = false
    @State private var showEndCountPicker = false

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

            // A recurring task created here used to repeat forever with no way to bound it, while
            // correctly honouring a bound set on a Mac — the end condition has been in the model
            // and in `applyRecurrenceEnd` all along and only macOS's inspector offered it (T-188).
            // The rows are hidden outright for a one-off task: an end condition on something that
            // does not repeat has nothing to end.
            if CadenceTaskRecurrenceEndPresentation.showsEndControls(rule: task.recurrenceRule) {
                iOSEditorDivider()
                endsRow

                switch CadenceTaskRecurrenceEndPresentation.detail(for: task.effectiveRecurrenceEndMode) {
                case .none:
                    EmptyView()
                case .date:
                    iOSEditorDivider()
                    endDateRow
                case .count:
                    iOSEditorDivider()
                    endCountRow
                }
            }

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
                                color: Theme.dim
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

    // MARK: - Ends

    /// States the bound and opens the mode picker. The value is
    /// `CadenceTaskRecurrenceEndPresentation.valueLabel`, which is the same sentence macOS's
    /// inspector puts under its Repeat row — including "3 of 5", which is the one fact about a
    /// counted series that this sheet has nowhere else to say.
    ///
    /// It reads `effectiveRecurrenceEndMode`, not `recurrenceEndMode`: a mode whose value cannot
    /// be honoured (an `.onDate` with no date) already behaves as `.never` everywhere else, so
    /// showing it as selected here would be the control disagreeing with the series.
    private var endsRow: some View {
        iOSEditorFieldRow(
            label: "Ends",
            systemImage: task.effectiveRecurrenceEndMode.systemImage,
            color: Theme.dim
        ) {
            iOSChoiceValueButton(
                title: CadenceTaskRecurrenceEndPresentation.valueLabel(
                    mode: task.effectiveRecurrenceEndMode,
                    endDateKey: task.recurrenceEndDate,
                    occurrenceNumber: task.recurrenceOccurrenceNumber,
                    endCount: task.recurrenceEndCount
                ),
                color: task.effectiveRecurrenceEndMode == .never ? Theme.dim : Theme.text,
                minHeight: 44
            ) {
                showEndModePicker = true
            }
            .popover(isPresented: $showEndModePicker) {
                iOSChoicePopoverList(
                    rows: TaskRecurrenceEndMode.allCases.map { mode in
                        iOSChoiceRow(
                            value: mode,
                            title: mode.label,
                            systemImage: mode.systemImage,
                            color: Theme.dim
                        )
                    },
                    selection: endModeSelection,
                    isPresented: $showEndModePicker
                )
            }
        }
    }

    private var endDateRow: some View {
        iOSEditorFieldRow(label: "End date", systemImage: "calendar", color: Theme.dim) {
            CadenceDatePicker(selection: endDateSelection, minHeight: 44)
        }
    }

    private var endCountRow: some View {
        iOSEditorFieldRow(label: "Occurrences", systemImage: "number", color: Theme.dim) {
            iOSChoiceValueButton(
                title: "\(CadenceTaskRecurrenceEndPresentation.resolvedEndCount(task.recurrenceEndCount))",
                color: Theme.text,
                minHeight: 44
            ) {
                showEndCountPicker = true
            }
            .popover(isPresented: $showEndCountPicker) {
                iOSChoicePopoverList(
                    rows: CadenceTaskRecurrenceEndPresentation.endCountChoices.map { count in
                        iOSChoiceRow(value: count, title: "\(count)", color: Theme.blue)
                    },
                    selection: endCountSelection,
                    isPresented: $showEndCountPicker
                )
            }
        }
    }

    /// Selecting a mode has to arrive with that mode's value already usable.
    ///
    /// `.onDate` with an empty key and `.afterCount` with a stored `0` both degrade straight back
    /// to `.never` in `effectiveRecurrenceEndMode`, so writing the bare mode would look like the
    /// picker refusing the tap. Seeding here is the same fix macOS's `selectOnDate` makes, from the
    /// same two constants.
    private var endModeSelection: Binding<TaskRecurrenceEndMode> {
        Binding(
            get: { task.effectiveRecurrenceEndMode },
            set: { mode in
                switch CadenceTaskRecurrenceEndPresentation.detail(for: mode) {
                case .none:
                    applyRecurrenceEnd(mode, "", 0)
                case .date:
                    let key = task.recurrenceEndDate.isEmpty
                        ? CadenceTaskRecurrenceEndPresentation.defaultEndDateKey()
                        : task.recurrenceEndDate
                    applyRecurrenceEnd(mode, key, 0)
                case .count:
                    applyRecurrenceEnd(
                        mode,
                        "",
                        CadenceTaskRecurrenceEndPresentation.resolvedEndCount(task.recurrenceEndCount)
                    )
                }
            }
        )
    }

    private var endDateSelection: Binding<Date> {
        Binding(
            get: { CadenceTaskRecurrenceEndPresentation.resolvedEndDate(task.recurrenceEndDate) },
            set: { applyRecurrenceEnd(.onDate, DateFormatters.dateKey(from: $0), 0) }
        )
    }

    private var endCountSelection: Binding<Int> {
        Binding(
            get: { CadenceTaskRecurrenceEndPresentation.resolvedEndCount(task.recurrenceEndCount) },
            set: { applyRecurrenceEnd(.afterCount, "", CadenceTaskRecurrenceEndPresentation.normalizedEndCount($0)) }
        )
    }
}

struct iOSTaskSubtasksSection: View {
    let subtasks: [Subtask]
    let newSubtaskTitle: Binding<String>
    let canAddSubtask: Bool
    /// The red line under the composer when an add or a delete was refused (T-634). `nil` when the
    /// last one landed, which is the only state the section had before.
    let failureNotice: String?
    let onAdd: () -> Void
    let onDelete: (Subtask) -> Void

    var body: some View {
        iOSEditorSection(title: "Subtasks", style: .ruled, contentSpacing: 10) {
            subtaskList
            subtaskComposer
            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
            }
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
