import SwiftUI

/// One row in the panel's list, section or calendar picker, as data.
///
/// The panel takes **choices**, not an `[Area]`, a `[Project]` or an `[EKCalendar]`. That is the
/// seam that lets one view serve both platforms: SwiftData models and EventKit objects are the two
/// things a shared view cannot hold, and "a token, a name and a colour" is all a picker row ever
/// needed from either.
struct CadenceSchedulePanelChoice: Identifiable, Hashable {
    let id: String
    let name: String
    var color: Color = Theme.blue
    var systemImage: String = "circle.fill"
}

/// What the title says about the record's state, beside the words themselves.
///
/// Only an existing task has one: an eyebrow for the two statuses a checkbox cannot express (In
/// Progress, Cancelled) and a struck-through, dimmed title once it is settled — what the iOS task
/// inspector's title row has always drawn, carried over when that inspector became this panel
/// ([[T-3171]]). Data, not a view, so the panel stays free of either platform's completion control.
struct CadenceSchedulePanelTitleStatus: Equatable {
    var eyebrow: String?
    var eyebrowTint: Color = Theme.dim
    var isSettled = false
}

/// What the host can do, handed in rather than reached for.
///
/// Every write returns `String?` — `nil` when it landed, the sentence to show when it did not.
/// That is the shape `CadenceChoicePopoverList` and `EstimatePickerPopoverContent` already use for
/// a committing form, and it is what keeps the panel from needing a `ModelContext`, an
/// `EKEventStore` or an opinion about which one it is talking to.
struct CadenceSchedulePanelActions {
    /// Create or save, depending on `CadenceScheduleDraft.subject`.
    let commit: () -> String?
    let cancel: () -> Void
    /// Present **only** when a record exists. This is the one control that differs between creating
    /// and editing; everything else about the form is identical, which is the whole claim of
    /// [[T-3171]].
    var delete: (() -> String?)?
}

/// **The one panel that creates and edits, tasks and events, on both platforms** ([[T-3171]]).
///
/// Eight surfaces spell these fields today — four on iOS, four on macOS, 4,576 lines between them —
/// and the drift that produced is exactly why the iPad's Today timeline could create a task and not
/// an event ([[T-3169]]). This is the shape they adopt.
///
/// ## What it is made of, and what it refuses to be made of
///
/// Shared components throughout: `CadenceFieldSection` / `CadenceFieldRow` for every row,
/// `CadenceChoiceValueButton` + `CadenceChoicePopoverList` for every picker,
/// **`CadenceDatePicker`'s own grid** for every date — never a system `DatePicker`, by the owner's
/// ruling — `CadenceTimeRoller` for every clock time, `EstimatePickerControl` for the length, and
/// `CadenceInlineNotice` for anything it has to say. No `iOS*` type appears here; that is not
/// incidental tidiness but the condition of macOS being able to adopt it.
///
/// ## Date first, time second — for a task
///
/// Expanding **Do** or **Due** opens a calendar, not a clock. The date is what matters for a task,
/// and the model agrees: `AppTask.dueDate` is a date string with no time field anywhere beside it,
/// and `scheduledStartMin == -1` is already a first-class "planned today, no particular time". So
/// Due expands to the grid and nothing else, and Do expands to the grid plus one quiet Time row
/// that reveals the roller only if asked. An **event** keeps time prominent, because an event with
/// no time is only meaningful as an all-day one and the all-day toggle is what says that.
///
/// ## What a host may hand in besides the draft
///
/// Every addition is data or a closure, never a platform type, so the panel stays one file with no
/// conditional compilation:
///
/// - `readOnlyNotice` — the record exists and cannot be written (a Birthdays or subscribed
///   calendar). The panel says so first, every field it owns goes inert, and Save and Delete are
///   **absent** rather than disabled, because an enabled Save over a calendar EventKit refuses was
///   exactly the false promise the event sheet this replaces had removed.
/// - `failureNotice` — a refusal the host learned *after* the panel's own call returned. A
///   recurring event asks "this one, or all future ones?" between the tap and the write, so the
///   write's answer cannot come back through `actions.commit`'s return value.
/// - `canCommit` — a gate the draft cannot see, such as "the chosen calendar is one this event
///   can be moved to". Save greys out exactly as it does for an empty title.
/// - `offersEventRepeat` — `false` where the host cannot write a recurrence (an existing event
///   whose rules Cadence cannot spell, [[T-3171]] (ii)), so no Repeat row offers a choice that
///   would be dropped or would overwrite a rule it cannot show.
/// - `titleStatus` — an existing task's state, drawn on the title row. See the type.
/// - `offersTaskRepeat` — `false` where the host draws a task's series itself. The task editor
///   does, because its Repeat row is followed by the end condition and the series-scope question,
///   neither of which a creating panel has.
/// - `offersTaskDue` — `false` where the host has nowhere to write a due date: a Due row whose
///   value is dropped on the way to the store is the inert control T-470 went through this app
///   removing. (The macOS drag-create popover was that host until [[T-3171]] (iii) gave its task
///   write a due date.)
/// - `offersEventLocation` — `false` for the same reason, one field over, where the host's event
///   write has no location. No current host is: the macOS drag-create popover's write,
///   `CalendarManager.createStandaloneEvent`, gained one under [[T-3171]] (iii).
/// - `offersSubtasks` — off unless a creation host can carry checklist titles into storage.
///   The macOS drag-create host opts in; existing iOS hosts keep their present fields.
/// - `notesField` — the host's own notes editor. A sheet has room for the platform's full
///   markdown well and its reference sheets; a popover hanging off a block does not, and gets the
///   plain field below. Both write the same `draft.notes`.
struct CadenceSchedulePanel<NotesField: View>: View {
    @Binding var draft: CadenceScheduleDraft
    var listChoices: [CadenceSchedulePanelChoice] = []
    var sectionChoices: [String] = []
    var calendarChoices: [CadenceSchedulePanelChoice] = []
    /// Drawn in place of the calendar picker when the host has no calendar to offer — no access, or
    /// none writable. The panel never asks for a permission: a popover hanging off a block is not
    /// the place to raise a system prompt, so it says what is missing and leaves the request to the
    /// surface that owns it.
    var calendarUnavailableNotice: String?
    var readOnlyNotice: String?
    var failureNotice: String?
    var canCommit = true
    var offersEventRepeat = true
    var titleStatus: CadenceSchedulePanelTitleStatus?
    var offersTaskRepeat = true
    var offersTaskDue = true
    var offersEventLocation = true
    /// Opt-in: only a host that can persist creation subtasks offers this editor.
    var offersSubtasks = false
    let actions: CadenceSchedulePanelActions
    private let notesField: NotesField?
    private var captureOptions: CadenceScheduleCaptureOptions?

    /// Capture changes the presentation, not the draft, picker vocabulary or commit contract.
    func capturePresentation(_ options: CadenceScheduleCaptureOptions) -> Self {
        var panel = self
        panel.captureOptions = options
        return panel
    }

    /// Why this appearance is happening, which decides whether the title field takes focus on it.
    /// Defaulted to `.opened`, so every host that does not say otherwise keeps the focus it had.
    private var titleFocusAppearance: CadenceSchedulePanelTitleFocus.Appearance = .opened

    /// See `CadenceSchedulePanelTitleFocus`. A modifier rather than an init parameter, so the
    /// panel's other call sites stay byte-identical.
    func appearing(_ appearance: CadenceSchedulePanelTitleFocus.Appearance) -> Self {
        var panel = self
        panel.titleFocusAppearance = appearance
        return panel
    }

    /// Opens the panel with `row` already expanded ([[T-3253]] (a)): a click on a task card's Due
    /// chip should land on the Due grid, not on a panel with every row closed. `nil` opens every
    /// row closed, as before. Seeds the `@State` itself rather than toggling it in `onAppear`, so
    /// the height a host measures before the panel is laid out already includes the open row.
    func expanding(_ row: CadenceSchedulePanelRow?) -> Self {
        var panel = self
        let expansion = CadenceSchedulePanelRow.initialExpansion(row)
        panel._isDoExpanded = State(initialValue: expansion.isDoExpanded)
        panel._isDueExpanded = State(initialValue: expansion.isDueExpanded)
        return panel
    }

    @State private var isDoExpanded = false
    @State private var isDueExpanded = false
    @State private var isDoTimeExpanded = false
    @State private var isEventScheduleExpanded = false
    @State private var showListPicker = false
    @State private var showSectionPicker = false
    @State private var showCalendarPicker = false
    @State private var showRepeatPicker = false
    @State private var showSeriesEndPicker = false
    @State private var doViewMonth = Date()
    @State private var dueViewMonth = Date()
    @State private var actionError: String?
    @FocusState private var isTitleFocused: Bool

    /// The host's own notes editor in place of the plain field. See the type note.
    init(
        draft: Binding<CadenceScheduleDraft>,
        listChoices: [CadenceSchedulePanelChoice] = [],
        sectionChoices: [String] = [],
        calendarChoices: [CadenceSchedulePanelChoice] = [],
        calendarUnavailableNotice: String? = nil,
        readOnlyNotice: String? = nil,
        failureNotice: String? = nil,
        canCommit: Bool = true,
        offersEventRepeat: Bool = true,
        titleStatus: CadenceSchedulePanelTitleStatus? = nil,
        offersTaskRepeat: Bool = true,
        offersTaskDue: Bool = true,
        offersEventLocation: Bool = true,
        offersSubtasks: Bool = false,
        actions: CadenceSchedulePanelActions,
        @ViewBuilder notesField: () -> NotesField
    ) {
        self.init(
            draft: draft,
            listChoices: listChoices,
            sectionChoices: sectionChoices,
            calendarChoices: calendarChoices,
            calendarUnavailableNotice: calendarUnavailableNotice,
            readOnlyNotice: readOnlyNotice,
            failureNotice: failureNotice,
            canCommit: canCommit,
            offersEventRepeat: offersEventRepeat,
            titleStatus: titleStatus,
            offersTaskRepeat: offersTaskRepeat,
            offersTaskDue: offersTaskDue,
            offersEventLocation: offersEventLocation,
            offersSubtasks: offersSubtasks,
            actions: actions,
            customNotesField: notesField()
        )
    }

    fileprivate init(
        draft: Binding<CadenceScheduleDraft>,
        listChoices: [CadenceSchedulePanelChoice],
        sectionChoices: [String],
        calendarChoices: [CadenceSchedulePanelChoice],
        calendarUnavailableNotice: String?,
        readOnlyNotice: String?,
        failureNotice: String?,
        canCommit: Bool,
        offersEventRepeat: Bool,
        titleStatus: CadenceSchedulePanelTitleStatus?,
        offersTaskRepeat: Bool,
        offersTaskDue: Bool,
        offersEventLocation: Bool,
        offersSubtasks: Bool,
        actions: CadenceSchedulePanelActions,
        customNotesField: NotesField?
    ) {
        self._draft = draft
        self.listChoices = listChoices
        self.sectionChoices = sectionChoices
        self.calendarChoices = calendarChoices
        self.calendarUnavailableNotice = calendarUnavailableNotice
        self.readOnlyNotice = readOnlyNotice
        self.failureNotice = failureNotice
        self.canCommit = canCommit
        self.offersEventRepeat = offersEventRepeat
        self.titleStatus = titleStatus
        self.offersTaskRepeat = offersTaskRepeat
        self.offersTaskDue = offersTaskDue
        self.offersEventLocation = offersEventLocation
        self.offersSubtasks = offersSubtasks
        self.actions = actions
        self.notesField = customNotesField
    }

    private var isReadOnly: Bool { readOnlyNotice != nil }

    @ViewBuilder
    var body: some View {
        if let captureOptions {
            CadenceScheduleCaptureCard(
                draft: $draft,
                listChoices: listChoices,
                sectionChoices: sectionChoices,
                calendarChoices: calendarChoices,
                calendarUnavailableNotice: calendarUnavailableNotice,
                failureNotice: failureNotice,
                canCommit: canCommit,
                readOnlyNotice: readOnlyNotice,
                titleStatus: titleStatus,
                offersTaskRepeat: offersTaskRepeat,
                offersEventRepeat: offersEventRepeat,
                options: captureOptions,
                actions: actions,
                notesField: notesField
            )
        } else {
            standardPanel
        }
    }

    private var standardPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let readOnlyNotice {
                CadenceInlineNotice(text: readOnlyNotice, tone: .informational)
            }
            Group {
                kindSwitch
                titleRow
                if draft.kind == .task {
                    taskSchedule
                    listAndSection
                    if offersSubtasks { subtasksEditor }
                } else {
                    eventSchedule
                    locationRow
                    calendarRow
                }
            }
            // Every field the panel owns is inert on a record that cannot be written: there is no
            // Save to carry an edit anywhere, so letting one be typed would be the same false
            // promise in a quieter form. The host's notes field is *not* in this group — a host can
            // carry something of its own there that stays writable (its own note about the event).
            .disabled(isReadOnly)
            if let notesField {
                notesField
            } else {
                notesRow
                    .disabled(isReadOnly)
            }
            if let failure = actionError ?? failureNotice {
                CadenceInlineNotice(text: failure, tone: .failure)
            }
            footer
        }
        .padding(14)
        .background(Theme.surfaceElevated)
        .onAppear {
            isTitleFocused = CadenceSchedulePanelTitleFocus.takesFocusOnAppear(
                titleFocusAppearance,
                isEditing: draft.subject.isEditing
            )
        }
        .onChange(of: draft.kind) { _, _ in
            draft.normalizeForKind()
            actionError = nil
        }
        // The notice is about what is in the fields *now*, so the next keystroke retires it — the
        // rule T-589 settled for the docked bar this panel replaces, which kept "Add a title
        // first." on screen while the title was being typed.
        .onChange(of: draft.title) { _, _ in actionError = nil }
    }

    // MARK: Kind

    /// First, because it is the one control that changes what every control under it means. On the
    /// iPad timeline it is also the owner's actual complaint: that canvas carries both species and
    /// could make only one of them.
    private var kindSwitch: some View {
        // A kind switch on an existing record would offer to turn a saved task into an event,
        // which is a move between two stores and not an edit. Editing shows which kind it is and
        // does not offer to change it.
        CadenceScheduleKindSwitch(kind: $draft.kind, isEditing: draft.subject.isEditing)
    }

    /// The title, with priority as a compact mark control at its trailing edge.
    ///
    /// **Priority rides here rather than in a row of its own**, which is what frees the slot beside
    /// the list control for Section. It cycles on activation and needs no label, in the same place
    /// relative to the field it qualifies as the iOS task inspector's title row put it.
    private var titleRow: some View {
        CadenceFieldSection(title: nil, style: .ruled) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    // Only the two statuses a checkbox cannot express say anything here. "Todo"
                    // over every open task is a label that fires on the common case.
                    if let eyebrow = titleStatus?.eyebrow {
                        SectionEyebrowLabel(text: eyebrow, tint: titleStatus?.eyebrowTint ?? Theme.dim)
                    }
                    titleField
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if draft.kind == .task {
                    priorityControl
                }
            }
        }
    }

    /// Settled — done or cancelled — reads struck through and stops being the loudest text here.
    private var isTitleSettled: Bool { titleStatus?.isSettled ?? false }

    private var titleField: some View {
        TextField(draft.kind.titlePlaceholder, text: $draft.title, axis: .vertical)
            .textFieldStyle(.plain)
            .cadenceFont(.fieldValue, base: 16, weight: .bold)
            .foregroundStyle(isTitleSettled ? Theme.dim : Theme.text)
            .strikethrough(isTitleSettled, color: Theme.dim)
            .lineLimit(1...3)
            .focused($isTitleFocused)
            .submitLabel(.done)
            // **Deliberately unguarded** (T-589, inherited from the docked bar this panel
            // replaces). Add/Save can refuse in a way you can see — it greys out — so an
            // empty title has already been answered before you reach for it. Return has no
            // such affordance, so guarding it would make the key do nothing at all and look
            // broken: the "inert control, no word on it" failure T-470/T-471 went through
            // this app removing. `commit()` reports instead, and `onChange(of: draft.title)`
            // below takes the report down on the next keystroke.
            .onSubmit(commit)
    }

    /// **Marks, not a flag** ([[T-1278]]'s ruling, carried in when the task inspector became this
    /// panel). `flag.fill` is the *due date* on macOS, and the owner chose the `!` / `!!` / `!!!`
    /// control as the one priority style across devices, so this draws the shared
    /// `TaskPriorityMarkControl` rather than a glyph of its own.
    private var priorityControl: some View {
        Button(action: cyclePriority) {
            TaskPriorityMarkControl(priority: draft.priority)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .accessibilityLabel("Priority: \(draft.priority.label)")
        // **The outcome, not the gesture** (T-521, and this panel is why that sweep
        // covers `Shared/`). This control's hint read "Tap to cycle priority", which
        // was copied from `iOSCalendarQuickCreateSheet`'s old flag — correct there,
        // because that sheet is under `#if os(iOS)` and touch is the only way to reach
        // it, and retired with it when the sheet adopted this panel ([[T-3171]]). This
        // panel is shared, so on the Mac the hint named a gesture that surface does not
        // have: VoiceOver activates a control there with Control-Option-Space.
        .accessibilityHint("Changes the priority to the next level")
    }

    private func cyclePriority() {
        switch draft.priority {
        case .none: draft.priority = .low
        case .low: draft.priority = .medium
        case .medium: draft.priority = .high
        case .high: draft.priority = .none
        }
    }

    // MARK: Task schedule — Do, then Due

    @ViewBuilder
    private var taskSchedule: some View {
        CadenceFieldSection(title: nil, style: .ruled) {
            // Colour is spent on what is wrong: a do date already past on an open task.
            disclosureRow(
                label: "Do",
                value: draft.doRowLabel,
                systemImage: "calendar",
                color: draft.isDoDateOverdue ? Theme.red : Theme.blue,
                isExpanded: $isDoExpanded
            )

            if isDoExpanded {
                CadenceFieldDivider()
                // The DUE day is marked on this grid, in amber with the word in the cell, so the
                // two dates being reconciled are visible together rather than one row apart.
                // **Clear only on a task that exists.** Unscheduling a saved task is an edit the
                // inspector always offered; a draft block on a timeline is *made* of its day, so a
                // Clear there would erase the thing being created.
                CadenceQuickDatePopover(
                    selection: doDateBinding,
                    viewMonth: $doViewMonth,
                    isOpen: .constant(true),
                    showsClear: draft.subject.isEditing && !draft.startDateKey.isEmpty,
                    onClear: { draft.clearDoDate() },
                    inlineStyle: true,
                    markedDay: draft.dueDateKey.isEmpty ? nil : DateFormatters.date(from: draft.dueDateKey)
                )

                CadenceFieldDivider()
                doTimeRow
                if offersTaskRepeat {
                    CadenceFieldDivider()
                    repeatRow
                    seriesEndRows
                }
            }
        }

        if offersTaskDue {
            CadenceFieldSection(title: nil, style: .ruled) {
                disclosureRow(
                    label: "Due",
                    value: draft.dueRowLabel,
                    systemImage: "calendar.badge.exclamationmark",
                    color: draft.isDueDateOverdue ? Theme.red : Theme.amber,
                    isExpanded: $isDueExpanded
                )

                // The grid and nothing else. There is no due *time* in the models to put beside it,
                // and a Time row here would be a control with nowhere to write.
                if isDueExpanded {
                    CadenceFieldDivider()
                    CadenceQuickDatePopover(
                        selection: dueDateBinding,
                        viewMonth: $dueViewMonth,
                        isOpen: .constant(true),
                        showsClear: true,
                        onClear: { draft.dueDateKey = "" },
                        inlineStyle: true
                    )
                }
            }
        }

        // Warn, never block. See `CadenceScheduleDraft.doAfterDueNotice`.
        if let notice = draft.doAfterDueNotice {
            CadenceInlineNotice(text: notice, tone: .warning)
        }
    }

    /// The one quiet row inside the expanded Do section.
    ///
    /// Unset it reads "Add time"; set it reads the time and the length. The roller appears beneath
    /// it only when it is tapped, so a reader who wants a date for a task never meets a clock.
    @ViewBuilder
    private var doTimeRow: some View {
        Button {
            if draft.isAllDay || draft.startDateKey.isEmpty {
                draft.addTime()
                isDoTimeExpanded = true
            } else {
                isDoTimeExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                CadenceInlineFieldLabel(label: "Time", systemImage: "clock", color: Theme.dim)
                Spacer(minLength: 6)
                Text(draft.doTimeLabel)
                    .cadenceFont(.fieldValue)
                    .foregroundStyle(draft.scheduledStartMin < 0 ? Theme.dim : Theme.text)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 36)
        }
        .buttonStyle(.cadencePlain)

        if draft.scheduledStartMin >= 0 && isDoTimeExpanded {
            CadenceTimeRoller(minutes: doStartMinuteBinding) { isDoTimeExpanded = false }

            Button {
                draft.isAllDay = true
                isDoTimeExpanded = false
            } label: {
                Text("Clear time")
                    .cadenceFont(.metadata, weight: .semibold)
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
        }
    }

    private var listAndSection: some View {
        CadenceFieldSection(title: nil, style: .ruled) {
            CadenceFieldRow(label: "List", systemImage: "tray.full.fill", color: Theme.blue) {
                CadenceChoiceValueButton(title: listTitle, color: Theme.text) {
                    showListPicker = true
                }
                .popover(isPresented: $showListPicker) {
                    CadenceChoicePopoverList(
                        rows: listChoices.map {
                            CadenceChoiceRow(value: $0.id, title: $0.name, systemImage: $0.systemImage, color: $0.color)
                        },
                        selection: $draft.listToken,
                        isPresented: $showListPicker
                    )
                }
            }

            CadenceFieldDivider()

            // Section takes the slot priority used to hold, paired beside the list it belongs to —
            // a section is a subdivision *of* a list, so the two rows reading together is the
            // arrangement that says so.
            CadenceFieldRow(label: "Section", systemImage: "rectangle.split.3x1.fill", color: Theme.purple) {
                CadenceChoiceValueButton(title: draft.sectionName, color: Theme.text) {
                    showSectionPicker = true
                }
                .popover(isPresented: $showSectionPicker) {
                    CadenceChoicePopoverList(
                        rows: sectionChoices.map { CadenceChoiceRow(value: $0, title: $0, color: Theme.purple) },
                        selection: $draft.sectionName,
                        isPresented: $showSectionPicker
                    )
                }
            }
            .disabled(sectionChoices.isEmpty)
            .opacity(sectionChoices.isEmpty ? 0.45 : 1)

            CadenceFieldDivider()

            // **A row of the task's own, not a Length under the time** ([[T-3171]]). An estimate
            // is a property of the task whether or not it has a slot — the inspector this panel
            // replaced edited it on an untimed task, and None (0) is a value it could choose. On a
            // timed task it is also the block's length, which `setEstimate` keeps in step.
            CadenceFieldRow(label: "Estimate", systemImage: "timer", color: Theme.green) {
                EstimatePickerControl(value: estimateBinding)
            }
        }
    }

    // MARK: Event schedule

    @ViewBuilder
    private var eventSchedule: some View {
        CadenceFieldSection(title: nil, style: .ruled) {
            disclosureRow(
                label: draft.scheduleLabel,
                value: nil,
                systemImage: "clock.fill",
                color: Theme.blue,
                isExpanded: $isEventScheduleExpanded
            )

            if isEventScheduleExpanded {
                CadenceFieldDivider()

                Toggle(isOn: $draft.isAllDay) {
                    CadenceInlineFieldLabel(label: "All day", systemImage: "sun.max", color: Theme.amber)
                }
                .toggleStyle(.switch)
                .tint(Theme.blue)
                .frame(minHeight: 36)

                CadenceFieldDivider()

                CadenceFieldRow(label: "Starts", systemImage: "calendar", color: Theme.blue) {
                    CadenceDatePicker(selection: eventStartDayBinding, minHeight: 36)
                }
                if !draft.isAllDay {
                    CadenceTimeRollerFieldRow(label: "Start", minutes: eventStartMinuteBinding)
                }

                CadenceFieldDivider()

                // Separate end DATE, which is the whole of "one that spans multiple days".
                CadenceFieldRow(label: "Ends", systemImage: "calendar.badge.clock", color: Theme.blue) {
                    CadenceDatePicker(selection: eventEndDayBinding, minHeight: 36)
                }
                if !draft.isAllDay {
                    CadenceTimeRollerFieldRow(
                        label: "End",
                        systemImage: "clock.badge.checkmark",
                        minutes: eventEndMinuteBinding
                    )
                }

                if offersEventRepeat {
                    CadenceFieldDivider()
                    repeatRow
                    seriesEndRows
                }
            }
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        if offersEventLocation {
            CadenceFieldSection(title: nil, style: .ruled) {
                CadenceFieldRow(label: "Location", systemImage: "mappin.and.ellipse", color: Theme.red) {
                    TextField("Add location", text: $draft.location)
                        .textFieldStyle(.plain)
                        .cadenceFont(.fieldValue)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var calendarRow: some View {
        CadenceFieldSection(title: nil, style: .ruled) {
            if let calendarUnavailableNotice {
                CadenceInlineNotice(text: calendarUnavailableNotice, tone: .informational)
            } else {
                CadenceFieldRow(
                    label: CadenceAppleCalendarNaming.integrationSectionTitle,
                    systemImage: "calendar",
                    color: Theme.green
                ) {
                    CadenceChoiceValueButton(title: calendarTitle, color: Theme.text) {
                        showCalendarPicker = true
                    }
                    .popover(isPresented: $showCalendarPicker) {
                        CadenceChoicePopoverList(
                            rows: calendarChoices.map {
                                CadenceChoiceRow(value: $0.id, title: $0.name, systemImage: "calendar", color: $0.color)
                            },
                            selection: $draft.calendarID,
                            isPresented: $showCalendarPicker
                        )
                    }
                }
            }
        }
    }

    // MARK: Shared rows

    private var repeatRow: some View {
        CadenceFieldRow(label: "Repeat", systemImage: draft.repeatRule.systemImage, color: Theme.purple) {
            CadenceChoiceValueButton(
                title: draft.repeatRule.label,
                color: draft.repeatRule == .none ? Theme.dim : Theme.text
            ) {
                showRepeatPicker = true
            }
            .popover(isPresented: $showRepeatPicker) {
                CadenceChoicePopoverList(
                    rows: TaskRecurrenceRule.allCases.map {
                        CadenceChoiceRow(value: $0, title: $0.label, systemImage: $0.systemImage, color: Theme.purple)
                    },
                    selection: $draft.repeatRule,
                    isPresented: $showRepeatPicker
                )
            }
        }
    }

    /// **The series' end, under Repeat, on both arms** ([[T-6901]]). The capture card's
    /// `Never / On Date / After` control, drawn in this presentation's row vocabulary: a mode
    /// picker, then the one value that mode needs. It was missing, so on the Mac a drag-created
    /// series was always endless and an existing series' end rode through the event editor with
    /// nothing on screen naming it. Hidden while Repeat is None — nothing repeats, so nothing ends.
    ///
    /// Every control writes through `CadenceScheduleDraft`'s `selectSeriesEnd(_:)` /
    /// `setSeriesEndCount(_:)` / `setSeriesEndDate(_:)`, which is where the seeding and the floors
    /// live and are tested; this view only binds them.
    @ViewBuilder
    private var seriesEndRows: some View {
        if draft.showsSeriesEndRows {
            CadenceFieldDivider()
            CadenceFieldRow(label: "Ends", systemImage: draft.effectiveSeriesEndMode.systemImage, color: Theme.purple) {
                CadenceChoiceValueButton(
                    title: draft.effectiveSeriesEndMode.label,
                    color: draft.effectiveSeriesEndMode == .never ? Theme.dim : Theme.text
                ) {
                    showSeriesEndPicker = true
                }
                .popover(isPresented: $showSeriesEndPicker) {
                    CadenceChoicePopoverList(
                        rows: TaskRecurrenceEndMode.allCases.map {
                            CadenceChoiceRow(value: $0, title: $0.label, systemImage: $0.systemImage, color: Theme.purple)
                        },
                        selection: seriesEndModeBinding,
                        isPresented: $showSeriesEndPicker
                    )
                }
            }

            switch CadenceTaskRecurrenceEndPresentation.detail(for: draft.effectiveSeriesEndMode) {
            case .none:
                EmptyView()
            case .date:
                CadenceFieldRow(label: "End date", systemImage: "calendar", color: Theme.purple) {
                    CadenceDatePicker(selection: seriesEndDateBinding, minHeight: 36)
                }
            case .count:
                Stepper(value: seriesEndCountBinding, in: draft.seriesEndCountRange) {
                    CadenceInlineFieldLabel(
                        label: CadenceTaskRecurrenceEndPresentation.endCountStepperLabel(draft.seriesEndCount),
                        systemImage: "number",
                        color: Theme.purple
                    )
                }
                .frame(minHeight: 36)
            }
        }
    }

    private var seriesEndModeBinding: Binding<TaskRecurrenceEndMode> {
        Binding(get: { draft.effectiveSeriesEndMode }, set: { draft.selectSeriesEnd($0) })
    }

    private var seriesEndDateBinding: Binding<Date> {
        Binding(
            get: { CadenceTaskRecurrenceEndPresentation.resolvedEndDate(draft.seriesEndDateKey) },
            set: { draft.setSeriesEndDate($0) }
        )
    }

    private var seriesEndCountBinding: Binding<Int> {
        Binding(get: { draft.seriesEndCount }, set: { draft.setSeriesEndCount($0) })
    }

    private var subtasksEditor: some View {
        CadenceFieldSection(title: "Subtasks", style: .ruled) {
            TextEditor(text: Binding(
                get: { draft.subtaskTitles.joined(separator: "\n") },
                set: { draft.subtaskTitles = $0.components(separatedBy: "\n") }
            ))
            .cadenceFont(.fieldValue)
            .foregroundStyle(Theme.text)
            .scrollContentBackground(.hidden)
            .frame(height: 80)
            .accessibilityLabel("Subtasks, one per line")
            Text("One subtask per line")
                .cadenceFont(.metadata)
                .foregroundStyle(Theme.dim)
        }
    }

    /// Plain text, not the full markdown well the two creation sheets carry.
    ///
    /// That well brings an accessory bar, an image inserter and two reference sheets of its own,
    /// and a popover that can present a sheet from inside itself is a presentation knot rather than
    /// a feature. The field writes the same `AppTask.notes` / `EKEvent.notes` either way, and both
    /// stay markdown — a note started here opens in the full editor afterwards.
    private var notesRow: some View {
        CadenceSchedulePanelNotesRow(notes: $draft.notes)
    }

    @ViewBuilder
    private func disclosureRow(
        label: String,
        value: String?,
        systemImage: String,
        color: Color,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                CadenceInlineFieldLabel(label: label, systemImage: systemImage, color: color)
                Spacer(minLength: 6)
                if let value {
                    Text(value)
                        .cadenceFont(.fieldValue)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .cadenceFont(.metadata, weight: .bold)
                    .foregroundStyle(Theme.dim)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
            }
            .contentShape(Rectangle())
            .frame(minHeight: 36)
        }
        .buttonStyle(.cadencePlain)
        .accessibilityHint(isExpanded.wrappedValue ? "Collapse" : "Expand")
    }

    /// Delete on the left, well away from Save — and present **only** when there is a record to
    /// delete. That one control is the entire difference between this panel creating and editing.
    private var footer: some View {
        HStack(spacing: 10) {
            if !isReadOnly, let delete = actions.delete {
                Button {
                    actionError = delete()
                } label: {
                    Text("Delete")
                        .cadenceFont(.controlLabel, weight: .semibold)
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Theme.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
            }

            Spacer(minLength: 0)

            // "Done" on a record that cannot be written: there is nothing to cancel, and the one
            // thing the button does is leave.
            Button(action: actions.cancel) {
                Text(isReadOnly ? "Done" : "Cancel")
                    .cadenceFont(.controlLabel, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)

            if !isReadOnly {
                Button(action: commit) {
                    Text(draft.subject.isEditing ? "Save" : "Add")
                        .cadenceFont(.controlLabel, weight: .semibold)
                        .foregroundStyle(Theme.onColor(for: Theme.blue))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(isCommitEnabled ? Theme.blue : Theme.blue.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .disabled(!isCommitEnabled)
            }
        }
    }

    private var isCommitEnabled: Bool {
        draft.hasCommittableTitle && canCommit
    }

    private func commit() {
        guard !isReadOnly else { return }
        guard draft.hasCommittableTitle else {
            actionError = "Add a title first."
            return
        }
        actionError = actions.commit()
    }

    // MARK: Derived and bindings

    private var listTitle: String {
        listChoices.first { $0.id == draft.listToken }?.name ?? "Inbox"
    }

    private var calendarTitle: String {
        calendarChoices.first { $0.id == draft.calendarID }?.name ?? "Choose Calendar"
    }

    private var doDateBinding: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: draft.startDateKey) ?? Date() },
            set: { draft.startDateKey = DateFormatters.dateKey(from: $0) }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: draft.dueDateKey) ?? Date() },
            set: { draft.dueDateKey = DateFormatters.dateKey(from: $0) }
        )
    }

    private var doStartMinuteBinding: Binding<Int> {
        Binding(
            get: { draft.startMin },
            set: { draft.moveStart(toMinute: $0) }
        )
    }

    private var estimateBinding: Binding<Int> {
        Binding(
            get: { draft.estimateMinutes },
            set: { draft.setEstimate($0) }
        )
    }

    private var eventStartDayBinding: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: draft.startDateKey) ?? Date() },
            set: { newDay in
                let key = DateFormatters.dateKey(from: newDay)
                draft.startDateKey = key
                // An end day can never precede the start it was measured from. Dragging the start
                // past the end carries the end with it rather than producing a block that finishes
                // before it begins — the same non-inversion rule the block's edge handles obey.
                draft.keepEndAfterStart()
            }
        )
    }

    private var eventEndDayBinding: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: draft.endDateKey) ?? Date() },
            set: {
                draft.endDateKey = max(DateFormatters.dateKey(from: $0), draft.startDateKey)
                draft.keepEndAfterStart()
            }
        )
    }

    private var eventStartMinuteBinding: Binding<Int> {
        Binding(
            get: { draft.startMin },
            set: { draft.moveStart(toMinute: $0) }
        )
    }

    private var eventEndMinuteBinding: Binding<Int> {
        Binding(
            get: { draft.endMin },
            set: { draft.setEndMinute($0) }
        )
    }
}

extension CadenceSchedulePanel where NotesField == EmptyView {
    /// The panel with its own plain notes field — what a popover host wants.
    init(
        draft: Binding<CadenceScheduleDraft>,
        listChoices: [CadenceSchedulePanelChoice] = [],
        sectionChoices: [String] = [],
        calendarChoices: [CadenceSchedulePanelChoice] = [],
        calendarUnavailableNotice: String? = nil,
        readOnlyNotice: String? = nil,
        failureNotice: String? = nil,
        canCommit: Bool = true,
        offersEventRepeat: Bool = true,
        offersTaskRepeat: Bool = true,
        offersTaskDue: Bool = true,
        offersEventLocation: Bool = true,
        offersSubtasks: Bool = false,
        actions: CadenceSchedulePanelActions
    ) {
        self.init(
            draft: draft,
            listChoices: listChoices,
            sectionChoices: sectionChoices,
            calendarChoices: calendarChoices,
            calendarUnavailableNotice: calendarUnavailableNotice,
            readOnlyNotice: readOnlyNotice,
            failureNotice: failureNotice,
            canCommit: canCommit,
            offersEventRepeat: offersEventRepeat,
            titleStatus: nil,
            offersTaskRepeat: offersTaskRepeat,
            offersTaskDue: offersTaskDue,
            offersEventLocation: offersEventLocation,
            offersSubtasks: offersSubtasks,
            actions: actions,
            customNotesField: nil
        )
    }
}

/// The panel's plain notes field, as a view of its own so a host that hands in a `notesField` of
/// its own can still draw it.
///
/// The macOS event editor is that host ([[T-3171]]): it puts the Cadence event note's card in the
/// slot, which the panel must not disable on a read-only event, and wants the plain Apple Calendar
/// notes field beneath it, which it must. One spelling of the field rather than a near-copy in the
/// host.
struct CadenceSchedulePanelNotesRow: View {
    @Binding var notes: String

    var body: some View {
        CadenceFieldSection(title: nil, style: .ruled) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.alignleft")
                    .cadenceFont(.metadata)
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 4)
                TextField("Add notes", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .cadenceFont(.fieldValue)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...4)
            }
            .frame(minHeight: 36)
        }
    }
}

/// The panel's figures, outside the generic type: a static stored property cannot live on one.
/// The Task/Event switch, drawn once for every surface that offers one.
///
/// **It is a shared view rather than a near-copy** because there are now two hosts — the standard
/// panel and the capture card — and a second spelling of this control is the mistake [[T-3195]]
/// was filed about: one editor, drawn one way. **It is Buttons rather than a
/// `Picker(.pickerStyle(.segmented))`** because `Cadence/iOS` and `Cadence/Shared` draw no native
/// pickers; `CadenceChoiceRow` and its siblings are this app's own vocabulary, and
/// `SettingsSharedVocabularyTests.noMobileOrSharedSurfaceDrawsANativePicker` holds the rule for
/// both directories. A selected arm carries `.isSelected`, so it reads to VoiceOver — and to a UI
/// test — as a selected segment would.
struct CadenceScheduleKindSwitch: View {
    @Binding var kind: CadenceScheduleDraftKind
    /// Editing an existing record: shown, dimmed, and not offered.
    var isEditing: Bool
    /// Each arm is identified `<prefix>-task` / `<prefix>-event`. A per-arm identifier rather than
    /// one on the row: a UI test that reaches a segment through its container depends on how
    /// SwiftUI happens to flatten the row that day, and "Event" on its own is ambiguous with the
    /// capture palette's own Event tile.
    var identifierPrefix: String = "schedule-kind"

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CadenceScheduleDraftKind.allCases) { kind in
                let isSelected = self.kind == kind
                Button { self.kind = kind } label: {
                    Text(kind.title)
                        .cadenceFont(.controlLabel, weight: isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Theme.onColor(for: Theme.blue) : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(isSelected ? Theme.blue : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("\(identifierPrefix)-\(kind.rawValue)")
            }
        }
        .opacity(isEditing ? 0.45 : 1)
        .disabled(isEditing)
    }
}

/// Whether the panel's title field takes focus when the panel appears ([[T-3252]]).
///
/// **A new draft focuses its title; an existing record does not; and neither does a draft whose
/// editor is coming BACK.** The iPad timeline's draft editor is a popover that goes down while an
/// edge handle is dragged and is put back when that handle's own drag ends having moved the edge
/// (`restoreDraftEditorAfterAdjustment()`, [[T-3246]], [[T-7551]]). Every re-presentation is a
/// fresh `onAppear`, so the focus a new draft rightly takes re-raised the keyboard on every
/// adjustment — on a gesture that was about the block's range, not its name. The returning editor leaves the keyboard down; a tap on the title still raises it.
enum CadenceSchedulePanelTitleFocus {
    enum Appearance: Equatable {
        /// The editor is opening on this draft: the first presentation, or one a tap asked for.
        case opened
        /// The editor is being put back after an adjustment of the draft it was already showing.
        case returnedAfterAdjustment
    }

    static func takesFocusOnAppear(_ appearance: Appearance, isEditing: Bool) -> Bool {
        guard !isEditing else { return false }
        return appearance == .opened
    }
}

/// A row of the panel that a host can ask to open expanded. Only Do and Due expand at all: List,
/// Section and Repeat open popovers, and Priority and Estimate are inline controls.
enum CadenceSchedulePanelRow: Equatable {
    case doDate
    case dueDate

    struct Expansion: Equatable {
        var isDoExpanded = false
        var isDueExpanded = false
    }

    static func initialExpansion(_ row: CadenceSchedulePanelRow?) -> Expansion {
        switch row {
        case .doDate: Expansion(isDoExpanded: true)
        case .dueDate: Expansion(isDueExpanded: true)
        case nil: Expansion()
        }
    }
}

enum CadenceSchedulePanelMetrics {
    /// The panel's width where its host gives it none — a popover has no container to be a fraction
    /// of. A sheet or an inspector column overrides it with its own frame.
    static let preferredWidth: CGFloat = 372
}

/// The standard panel's Ends row, as draft writes ([[T-6901]]).
///
/// **Choosing a mode stores a value that mode can honour.** `effectiveSeriesEndMode` degrades an
/// `.onDate` with no day and an `.afterCount` below one to `.never`, so writing the bare mode would
/// look like the picker refusing the tap. On Date seeds through `seedSeriesEnd(for:)` -- the
/// capture card's T-3233 seed, anchored on the later of today and the start, keeping a day already
/// chosen. After seeds `resolvedEndCount(_:occurrenceNumber:)`: the shared seed of ten rather than
/// the floor of one (a fresh series ending on its first occurrence), floored at the occurrence an
/// existing task has already reached (T-6114). Never keeps the other values, so switching back
/// finds the count or day the user had; every write reads only the value of the resolved mode.
extension CadenceScheduleDraft {
    /// The Ends rows are drawn only under a Repeat that repeats.
    var showsSeriesEndRows: Bool {
        CadenceTaskRecurrenceEndPresentation.showsEndControls(rule: repeatRule)
    }

    /// The After stepper's bounds: never below one or the occurrence already reached, and never
    /// capping a stored count that is already larger (the task inspector's field has no ceiling).
    var seriesEndCountRange: ClosedRange<Int> {
        let floor = max(1, seriesOccurrenceNumber)
        return floor...max(999, seriesEndCount, floor)
    }

    mutating func selectSeriesEnd(
        _ mode: TaskRecurrenceEndMode,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        seriesEndMode = mode
        switch mode {
        case .never:
            break
        case .onDate:
            seedSeriesEnd(for: .onDate, reference: reference, calendar: calendar)
        case .afterCount:
            seriesEndCount = CadenceTaskRecurrenceEndPresentation.resolvedEndCount(
                seriesEndCount,
                occurrenceNumber: seriesOccurrenceNumber
            )
        }
    }

    mutating func setSeriesEndCount(_ count: Int) {
        seriesEndMode = .afterCount
        seriesEndCount = CadenceTaskRecurrenceEndPresentation.normalizedEndCount(
            count,
            occurrenceNumber: seriesOccurrenceNumber
        )
    }

    mutating func setSeriesEndDate(_ date: Date) {
        seriesEndMode = .onDate
        seriesEndDateKey = DateFormatters.dateKey(from: date)
    }
}
