#if os(iOS)
import SwiftData
import SwiftUI

/// **The task's series and its measurement** — Repeat, the end condition under it, and whatever
/// the focus timer has logged — drawn in the schedule panel's host slot ([[T-3171]]).
///
/// It was the inspector's whole field list (T-1278: labelled rows on the sheet's plate with a
/// hairline between them and no box around them, chosen by the owner from three mockups). When the
/// inspector became `CadenceSchedulePanel` in edit mode, the panel took Do, Due, the time and the
/// estimate; what is left here is what the panel has no row for. **The end condition** is an edit
/// only an existing series has — a creating panel offers Repeat and stops — and it shares the one
/// scope question with the rule, so the two stay together with the Repeat row rather than splitting
/// across the panel and its host (`offersTaskRepeat: false` is how the panel is told). **Logged**
/// is the one figure in the sheet nobody sets.
///
/// Every control writes the **draft**: the rule and the bound reach the store on Save, through
/// `CadenceTaskEditDraftCommit`, after the series-scope question when the task has a series.
struct iOSTaskFieldListSection: View {
    @Binding var draft: CadenceScheduleDraft
    let loggedMinutes: Int

    @State private var showRepeatPicker = false
    @State private var showEndModePicker = false
    @State private var showEndCountPicker = false

    var body: some View {
        // Divider-separated rows, so no `contentSpacing`: `iOSEditorDivider` already pads itself by
        // 6pt on each side, and adding more on both sides counts the same gap twice.
        iOSEditorSection(title: nil, style: .ruled) {
            repeatRow

            // The rows are hidden outright for a one-off task: an end condition on something that
            // does not repeat has nothing to end (T-188).
            if CadenceTaskRecurrenceEndPresentation.showsEndControls(rule: draft.repeatRule) {
                iOSEditorDivider()
                endsRow

                switch CadenceTaskRecurrenceEndPresentation.detail(for: draft.effectiveSeriesEndMode) {
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

            loggedRow
        }
    }

    // MARK: - Repeat

    private var repeatRow: some View {
        iOSEditorFieldRow(label: "Repeat", systemImage: draft.repeatRule.systemImage, color: Theme.dim) {
            iOSChoiceValueButton(
                title: draft.repeatRule.label,
                color: draft.repeatRule == .none ? Theme.dim : Theme.text,
                minHeight: 44
            ) {
                showRepeatPicker = true
            }
            .popover(isPresented: $showRepeatPicker) {
                iOSChoicePopoverList(
                    rows: TaskRecurrenceRule.allCases.map { rule in
                        iOSChoiceRow(value: rule, title: rule.label, systemImage: rule.systemImage, color: Theme.dim)
                    },
                    selection: $draft.repeatRule,
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
    /// It reads `effectiveSeriesEndMode`, not the stored mode: a mode whose value cannot
    /// be honoured (an `.onDate` with no date) already behaves as `.never` everywhere else, so
    /// showing it as selected here would be the control disagreeing with the series.
    private var endsRow: some View {
        iOSEditorFieldRow(
            label: "Ends",
            systemImage: draft.effectiveSeriesEndMode.systemImage,
            color: Theme.dim
        ) {
            iOSChoiceValueButton(
                title: CadenceTaskRecurrenceEndPresentation.valueLabel(
                    mode: draft.effectiveSeriesEndMode,
                    endDateKey: draft.seriesEndDateKey,
                    occurrenceNumber: draft.seriesOccurrenceNumber,
                    endCount: draft.seriesEndCount
                ),
                color: draft.effectiveSeriesEndMode == .never ? Theme.dim : Theme.text,
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
                title: "\(CadenceTaskRecurrenceEndPresentation.resolvedEndCount(draft.seriesEndCount, occurrenceNumber: draft.seriesOccurrenceNumber))",
                color: Theme.text,
                minHeight: 44
            ) {
                showEndCountPicker = true
            }
            .popover(isPresented: $showEndCountPicker) {
                iOSChoicePopoverList(
                    rows: CadenceTaskRecurrenceEndPresentation.endCountChoices(
                        from: draft.seriesOccurrenceNumber,
                        including: endCountSelection.wrappedValue
                    ).map { count in
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
    /// to `.never` in `effectiveSeriesEndMode`, so writing the bare mode would look like the
    /// picker refusing the tap. Seeding here is the same fix macOS's `selectOnDate` makes, from the
    /// same two constants.
    private var endModeSelection: Binding<TaskRecurrenceEndMode> {
        Binding(
            get: { draft.effectiveSeriesEndMode },
            set: { mode in
                switch CadenceTaskRecurrenceEndPresentation.detail(for: mode) {
                case .none:
                    setEnd(mode, "", 0)
                case .date:
                    let key = draft.seriesEndDateKey.isEmpty
                        ? CadenceTaskRecurrenceEndPresentation.defaultEndDateKey()
                        : draft.seriesEndDateKey
                    setEnd(mode, key, 0)
                case .count:
                    setEnd(mode, "", CadenceTaskRecurrenceEndPresentation.resolvedEndCount(draft.seriesEndCount, occurrenceNumber: draft.seriesOccurrenceNumber))
                }
            }
        )
    }

    private var endDateSelection: Binding<Date> {
        Binding(
            get: { CadenceTaskRecurrenceEndPresentation.resolvedEndDate(draft.seriesEndDateKey) },
            set: { setEnd(.onDate, DateFormatters.dateKey(from: $0), 0) }
        )
    }

    private var endCountSelection: Binding<Int> {
        Binding(
            get: { CadenceTaskRecurrenceEndPresentation.resolvedEndCount(draft.seriesEndCount, occurrenceNumber: draft.seriesOccurrenceNumber) },
            set: { setEnd(.afterCount, "", $0) }
        )
    }

    /// The Ends rows' one write, normalized the way `applyRecurrenceEnd` will store it — values
    /// that do not belong to the chosen mode are dropped, so the draft and the saved series cannot
    /// disagree about what was chosen.
    private func setEnd(_ mode: TaskRecurrenceEndMode, _ dateKey: String, _ count: Int) {
        draft.seriesEndMode = mode
        draft.seriesEndDateKey = mode == .onDate ? dateKey : ""
        draft.seriesEndCount = mode == .afterCount
            ? CadenceTaskRecurrenceEndPresentation.normalizedEndCount(count, occurrenceNumber: draft.seriesOccurrenceNumber)
            : 0
    }

    // MARK: - Logged

    /// **Logged time keeps a row of its own** (T-1278). It is the one figure in the sheet nobody
    /// sets: the focus timer writes `actualMinutes` and this row reports it. It used to be an
    /// editable minutes picker, which invited a user to overwrite a measurement by hand, and macOS
    /// deleted its equivalent "Actual" row for that reason. Only when there is something to report
    /// — `loggedLabel` returns `nil` on zero.
    @ViewBuilder
    private var loggedRow: some View {
        if let logged = CadenceTaskInspectorSupport.loggedLabel(minutes: loggedMinutes) {
            iOSEditorDivider()
            iOSEditorFieldRow(label: "Logged", systemImage: "stopwatch", color: Theme.dim) {
                Text(logged)
                    .cadenceFont(.controlLabel)
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
/// `Theme.surface`, the fill the mockup named — and **one step below** the plate it sits on. Since
/// [[T-3171]] this block is inside `CadenceSchedulePanel`, which draws on `Theme.surfaceElevated`,
/// so the `surfaceElevated` it wore while the form was on `Theme.surface` would now be the same
/// colour on the same colour and there would be no block at all. A step down reads as a well, the
/// way the markdown well beneath it does; a step up would be `surfaceHighlight`, which `Theme`
/// reserves for hover and selection.
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
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }

    /// No "No subtasks" placeholder: this row is captioned "Add subtask", which says the same thing
    /// and can be typed into. It is shaped like the rows above it — leading glyph in the check
    /// circle's slot, then the field — so the block reads as one list.
    private var addSubtaskRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .cadenceFont(.controlLabel)
                .foregroundStyle(Theme.dim)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            TextField("Add subtask", text: newSubtaskTitle)
                .textFieldStyle(.plain)
                .cadenceFont(.rowTitle)
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
                    .cadenceFont(.rowTitle, base: 20, weight: .regular)
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
    /// The sheet's handle on typing the well has not yet written to `notesText` ([[T-5170]]).
    let flush: iOSMarkdownEditorFlush
    let referenceNotes: [Note]
    let referenceTasks: [AppTask]
    let onOpenReference: (MarkdownReferenceDisplayTarget) -> Void

    var body: some View {
        iOSEditorSection(title: "Notes", style: .ruled, contentSpacing: 10) {
            iOSMarkdownEditingSurface(
                text: notesText,
                isFocused: isFocused,
                placeholder: "Add notes…",
                referenceNotes: referenceNotes,
                referenceTasks: referenceTasks,
                onOpenReference: onOpenReference,
                flush: flush
            )
            .iOSMarkdownWell()
        }
    }
}

/// The task's status transitions, under no heading — a label over the buttons names what the
/// buttons already say.
///
/// Every status value a control can produce has exactly one: **Complete** owns `done` (it was the
/// title card's circle until [[T-3171]] gave the title row to the shared panel, which draws no
/// platform completion control) and "Cancel" owns `cancelled`, each its own undo back to `todo` —
/// on a cancelled task Complete restores rather than completes, T-344's rule. "Start" owned
/// `inProgress` until [[T-5015]] (b) retired that status; it is gone from here because it is gone
/// from `CadenceTaskInspectorSupport.StatusAction`, which this renders.
/// They land the moment they are tapped, as they always did: a status change is an action on the
/// record, not a field of the draft. Deleting is the panel's footer, and gains no second home here.
struct iOSTaskStatusActionsSection: View {
    @Bindable var task: AppTask
    let onToggleCompletion: () -> Void
    let onSetStatus: (TaskStatus) -> Void

    private var isFinished: Bool {
        CadenceTaskQuerySupport.isFinishedTask(task)
    }

    var body: some View {
        iOSEditorSection(title: nil, style: .ruled, contentSpacing: 10) {
            HStack(spacing: 10) {
                iOSActionButton(
                    title: isFinished ? "Reopen" : "Complete",
                    systemImage: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle",
                    role: task.isDone ? .primary : .secondary,
                    size: .compact,
                    tint: task.isDone ? CadenceTaskPresentationSupport.statusColor(.done) : Theme.muted,
                    fullWidth: true,
                    action: onToggleCompletion
                )
                // [[T-7010]]: the shared action-keyed name, as the row's circle has read since T-611.
                // It spelled `isFinished ? "Mark task todo" : "Complete task"`, so VoiceOver said
                // "Mark task todo" over a button whose visible word is "Reopen", and Voice Control's
                // "Tap Reopen" matched nothing. `resolve(task:)` is `.done`/`.cancelled` exactly when
                // `isFinished` is, so the name now says "Reopen task" wherever the button says Reopen.
                .accessibilityLabel(CadenceTaskCompletionState.resolve(task: task).accessibilityActionLabel)

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
