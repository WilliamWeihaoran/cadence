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
    /// Local, unlike `showPriorityPicker`: nothing outside the inspector opens the roller, and the
    /// priority flag is a binding only because the inspector's own keyboard shortcut sets it.
    @State private var showEstimatePicker = false
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let tags: [Tag]
    let taskContainerBinding: Binding<TaskContainerSelection>
    let taskTagsBinding: Binding<[Tag]>
    let availableSections: [String]
    let onCreateTag: (String) -> Tag?

    /// Priority tile width + the title row's spacing, so everything under the title row lines up
    /// with the title text rather than with the tile.
    ///
    /// **The tile's size is `TaskPriorityMarkControl`'s own, by reference** (T-1600). It used to be
    /// `28` here and `minWidth: 28, minHeight: 28` in that control — one fact in two files, and the
    /// control is **shared**: the iOS inspector draws the same view, so the two could drift apart
    /// without anything failing. The header is the reader of the tile's width, not its owner.
    private static var tileSize: CGFloat { TaskPriorityMarkControl.side }
    private static let titleRowSpacing: CGFloat = 10
    private static var titleColumnInset: CGFloat { tileSize + titleRowSpacing }

    /// **T-1722. Both header panels are presented from the title ROW, not from the two controls
    /// that open them**, and that is the fix rather than a tidy-up.
    ///
    /// T-1510 gave each control the end of the content column its own anchor sits at. Measured on
    /// the running app, neither panel left by the end it was given: the tile's opened flush against
    /// the tile's *trailing* edge, inside the column, and the chip's flush against the chip's
    /// *leading* edge, across four rows. SwiftUI's horizontal `arrowEdge:` is not honoured as
    /// documented, so no call site can pick an end (see
    /// `TaskInspectorChildPopoverPlacement`'s comment for the frames).
    ///
    /// What is left is the anchor. The tile is 28pt at one end of the column and the chip is
    /// fixed-size at the other, so for either of them one end is safe and the other is the defect.
    /// **The row spans the column**, so both of its ends are the column's ends and a panel hung off
    /// either clears every row — which is the property T-1480's field rows have had all along and
    /// the reason those three survived the same inversion. One placement, no end to choose.
    private static let headerPanelPlacement = TaskInspectorChildPopoverPlacement.besideInspector

    /// Which of the two header panels is open.
    ///
    /// **One `.popover` modifier, not two.** Both panels hang off the same row now, and two
    /// `.popover`s chained onto one anchor do not both work: measured on the running app, the
    /// priority panel opened and the estimate roller then presented nothing at all. They are
    /// alternatives in any case — opening one closes the other, which is what a reader of a single
    /// row of controls expects — so they are one optional state rather than two booleans racing
    /// for one anchor.
    private enum HeaderPanel: String, Identifiable {
        case priority
        case estimate
        var id: String { rawValue }
    }

    /// The two flags read as one. `showPriorityPicker` stays a `Binding` because the inspector's
    /// own shortcut sets it from outside; this only projects the pair onto the anchor.
    private var presentedPanel: Binding<HeaderPanel?> {
        Binding(
            get: {
                if showPriorityPicker { return .priority }
                if showEstimatePicker { return .estimate }
                return nil
            },
            set: { panel in
                showPriorityPicker = panel == .priority
                showEstimatePicker = panel == .estimate
            }
        )
    }

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
                .accessibilityIdentifier(CadenceAccessibilityIdentifiers.inspectorPanelControl("Priority"))
                .accessibilityLabel("Priority")
                .accessibilityValue(task.priority.label)
                .help("Priority")

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

                TaskInspectorEstimateChip(
                    value: $task.estimatedMinutes,
                    isPickerPresented: $showEstimatePicker
                )
            }
            // Both panels hang off this row, which is the whole of T-1722's fix. The arrow points
            // at the row rather than at the control that opened it — the same trade T-1480 made
            // for the Schedule well, and the same reason: the arrow was never the part that was
            // wrong.
            .popover(item: presentedPanel, arrowEdge: Self.headerPanelPlacement.arrowEdge) { panel in
                switch panel {
                case .priority:
                    TaskPriorityPickerPopover(priority: $task.priority, isPresented: $showPriorityPicker)
                case .estimate:
                    EstimatePickerPopoverContent(value: $task.estimatedMinutes) {
                        showEstimatePicker = false
                    }
                }
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
