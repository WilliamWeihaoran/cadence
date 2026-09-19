#if os(iOS)
import SwiftData
import SwiftUI

/// **The inspector's one quiet field list** — do date, due date, time, estimate, repeat (and its end
/// condition), milestone, and whatever the focus timer has logged.
///
/// **T-1278, chosen by the owner from three drawn mockups.** It was two groups: an untitled
/// "properties" pair (Priority, Milestone) above a "SCHEDULE" well. Two of the three drafts — a chip
/// summary strip and a 2×2 tile grid — were rejected for the same reason, that each introduced a
/// tile or card layer this app does not otherwise draw, against the standing *one hover/selection
/// layer at one radius* rule. What is left is the layer the app already has: labelled rows on the
/// sheet's own plate with a hairline between them and no box around them, which is exactly what
/// `iOSEditorSection(style: .ruled)` is for.
///
/// **No heading, because every row names itself.** The group the properties pair used to carry was
/// titled "Overview" and was deleted for saying nothing the rows did not; "Schedule" over a list
/// that now also holds an estimate and a milestone would be the same mistake with a truer-sounding
/// word.
///
/// **Priority is not here.** It moved to the title row as the `!` / `!!` / `!!!` mark control both
/// platforms now share — see `iOSTaskEditorTitleCard`. Nothing else in the sheet writes it.
///
/// Each date is **one** control: the picker states the day and its popover offers Today / Tomorrow /
/// This Weekend, a month grid, and Clear. The toggle that used to sit beside it was a second
/// affordance for the same field, and the pair could disagree — the toggle said "on" while the
/// picker below it showed a day the task did not have.
struct iOSTaskFieldListSection: View {
    @Bindable var task: AppTask
    let availableGoals: [Goal]
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
    /// Committing: answers whether the minute landed, so the picker below can stay open over a
    /// refusal instead of closing over it (T-761). See `iOSTaskDetailSheet.selectScheduledTime`.
    let selectScheduledTime: (Int) -> Bool
    let scheduledTimeLabel: String

    @State private var showRepeatPicker = false
    @State private var showTimePicker = false
    @State private var showEndModePicker = false
    @State private var showEndCountPicker = false
    @State private var showEstimatePicker = false
    @State private var showMilestonePicker = false

    /// Colour is spent only on what is wrong. A do date in the past and an overdue deadline are the
    /// two things in this list that are, so everything else — including a do date of *today*, which
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

    private var selectedGoal: Goal? { task.goal }

    var body: some View {
        // Divider-separated rows, so no `contentSpacing`: `iOSEditorDivider` already pads itself by
        // 6pt on each side, and adding more on both sides counts the same gap twice. The divider
        // owns the spacing between rows; the section does not add to it.
        iOSEditorSection(title: nil, style: .ruled) {
            doRow

            iOSEditorDivider()
            dueRow

            // The time belongs to the do date and cannot mean anything without one, so it appears
            // with it rather than sitting empty above a task that has no day.
            if hasScheduledDate.wrappedValue {
                iOSEditorDivider()
                timeRow
            }

            iOSEditorDivider()
            estimateRow

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

            iOSEditorDivider()
            milestoneRow

            loggedRow
        }
    }

    // MARK: - Dates

    private var doRow: some View {
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
    }

    private var dueRow: some View {
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
                    selection: task.scheduledStartMin,
                    isPresented: $showTimePicker,
                    select: selectScheduledTime
                )
            }
        }
    }

    // MARK: - Estimate

    /// **The estimate is a row now, not a chip beside the title (T-1278).** It sat in the title row
    /// because "an estimate is a property of the task the way its priority is" — which is true, and
    /// is why the *priority* is what sits there now: there is one trailing slot on that line and
    /// the two platforms had to agree on what fills it. The estimate reads as a field the moment it
    /// is asked "how long", which is the question every other row on this list answers.
    ///
    /// It opens the shared roller directly rather than drawing `EstimatePickerControl`: that
    /// control carries its own `timer` glyph and its own filled pill, and in a row already labelled
    /// `timer` that is the glyph twice and the only tile in a list with no tiles. The words are
    /// `CadenceTaskPresentationSupport.estimateValueLabel`, which is what the pill says too.
    private var estimateRow: some View {
        iOSEditorFieldRow(label: "Estimate", systemImage: "timer", color: Theme.dim) {
            iOSChoiceValueButton(
                title: CadenceTaskPresentationSupport.estimateValueLabel(minutes: task.estimatedMinutes),
                color: task.estimatedMinutes > 0 ? Theme.text : Theme.dim,
                minHeight: 44
            ) {
                showEstimatePicker = true
            }
            .popover(isPresented: $showEstimatePicker) {
                EstimatePickerPopoverContent(value: $task.estimatedMinutes) {
                    showEstimatePicker = false
                }
                // Same reason as `CadenceDatePicker`: compact width otherwise promotes this to a
                // full-height sheet wrapped around a 260pt panel.
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    // MARK: - Repeat

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

    // MARK: - Milestone

    /// **Labelled "Milestone", which is the mockup's "Goal" in this app's own words.** The model
    /// type is `Goal` and the drawn mockup said Goal; every surface that names one to a *user* says
    /// milestone — `CadenceTitleNormalization.defaultMilestoneTitle` is "Untitled Milestone" and
    /// `CadenceTaskControlAccessibility.milestone` exists precisely so a chip cannot be the one
    /// place it is called something else. A row reading "Goal" over a picker offering "Untitled
    /// Milestone" would be that place.
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
                                title: CadenceTitleNormalization.display(goal.title, fallback: CadenceTitleNormalization.defaultMilestoneTitle),
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

    // MARK: - Logged

    /// **Logged time keeps a row of its own, and T-1278 had to decide that rather than inherit it.**
    /// None of the three mockups drew it — they were drawn from the fields a user *sets*, and this
    /// is the one figure in the sheet nobody sets: the focus timer writes `actualMinutes` and this
    /// row reports it. It used to be an editable minutes picker, which invited a user to overwrite a
    /// measurement by hand, and macOS deleted its equivalent "Actual" row for that reason.
    ///
    /// The two alternatives were both worse. Dropping it strands the only readout of time this app
    /// measured, with no other surface in the sheet showing it. Folding it into the Estimate row's
    /// value ("30m · 12m logged") puts a measurement and an editable field on one line under one
    /// label, so the row would no longer have a single answer — and the Estimate row is a *control*,
    /// which this is deliberately not.
    ///
    /// So: its own row, last, and only when there is something to report — which is what
    /// `loggedLabel` returning `nil` on zero already encodes, so on the common task the list ends at
    /// Milestone and costs nothing.
    @ViewBuilder
    private var loggedRow: some View {
        if let logged = CadenceTaskInspectorSupport.loggedLabel(minutes: task.actualMinutes) {
            iOSEditorDivider()
            iOSEditorFieldRow(label: "Logged", systemImage: "stopwatch", color: Theme.dim) {
                Text(logged)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
        }
    }
}

/// **The subtasks, as one grouped surface (T-1278).** The owner took the field list from mockup B
/// and the subtasks from mockup C: *"make sure to show subtask just like how option C is doing"*.
///
/// **This block is the one surface the redesign keeps, and it survives the rule that killed the
/// other two mockups because it is a container for a list rather than a decoration.** A and C were
/// rejected for introducing tile/card layers around fields that are not lists; a run of checkable
/// rows genuinely is one thing, and boxing it is what tells a reader where the list ends and the
/// Notes begin. One surface, one radius, no border, no hover layer.
///
/// `Theme.surfaceElevated`, **not** the `Theme.surface` the mockup named: the form this block sits
/// in is already drawn on `Theme.surface` (`iOSTaskDetailSheet.editorScrollView`), so a
/// `Theme.surface` block inside it is the same colour on the same colour and there is no block at
/// all. `surfaceElevated` is the ramp's next stop and is what `Theme`'s own note calls the fill for
/// content nested inside an already-elevated surface. The mockups were drawn standalone against
/// `Theme.bg`, where `surface` *is* the readable step; inside the card it is one step short.
///
/// The count beside the label is live and comes from the same `CadenceSubtaskProgress` the task row
/// draws its `2/5` badge from, so the panel and the row cannot disagree about how far along a task
/// is. There is no count at all when there are no subtasks — `subtaskProgress` returns `nil` on an
/// empty list, which is right: `0 of 0` is a figure about nothing.
struct iOSTaskSubtasksSection: View {
    let subtasks: [Subtask]
    let newSubtaskTitle: Binding<String>
    let canAddSubtask: Bool
    /// The red line under the composer when an add or a delete was refused (T-634). `nil` when the
    /// last one landed, which is the only state the section had before.
    let failureNotice: String?
    let onAdd: () -> Void
    let onDelete: (Subtask) -> Void

    private var progressLabel: String? {
        CadenceTaskPresentationSupport.subtaskProgress(for: subtasks)?.countLabel
    }

    var body: some View {
        iOSEditorSection(
            title: "Subtasks",
            trailing: progressLabel,
            style: .ruled,
            contentSpacing: 10
        ) {
            subtaskBlock

            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
            }
        }
    }

    /// The rows and the composer are one block, in that order, so "Add subtask" reads as the last
    /// line of the list rather than as a separate control parked under it. The composer used to be
    /// a filled well with a blue `+` tile beside it — two more surfaces at two more radii, directly
    /// under a section that is now a surface of its own.
    private var subtaskBlock: some View {
        VStack(spacing: 0) {
            ForEach(subtasks) { subtask in
                iOSSubtaskRow(subtask: subtask) {
                    onDelete(subtask)
                }
            }

            addSubtaskRow
        }
        .padding(.horizontal, 10)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }

    /// No "No subtasks" placeholder: this row is captioned "Add subtask", which says the same thing
    /// and can be typed into. It is shaped like the rows above it — leading glyph in the check
    /// circle's slot, then the field — so the block reads as one list.
    private var addSubtaskRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            TextField("Add subtask", text: newSubtaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(onAdd)

            Spacer(minLength: 8)

            // Kept as a control rather than relying on the keyboard's return key alone: the field
            // is inside a scrolling sheet, and the hardware-keyboard and VoiceOver paths both need
            // something to press. Dimmed rather than absent while there is nothing to add, so the
            // row does not change width as the user types.
            Button(action: onAdd) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(canAddSubtask ? Theme.blue : Theme.dim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .iOSExpandedHitArea(8)
            }
            .buttonStyle(.iosPressable)
            .disabled(!canAddSubtask)
            .opacity(canAddSubtask ? 1 : 0.45)
            .accessibilityLabel("Add subtask")
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 44)
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
