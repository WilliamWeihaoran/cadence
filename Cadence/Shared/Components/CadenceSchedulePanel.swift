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
struct CadenceSchedulePanel: View {
    @Binding var draft: CadenceScheduleDraft
    var listChoices: [CadenceSchedulePanelChoice] = []
    var sectionChoices: [String] = []
    var calendarChoices: [CadenceSchedulePanelChoice] = []
    /// Drawn in place of the calendar picker when the host has no calendar to offer — no access, or
    /// none writable. The panel never asks for a permission: a popover hanging off a block is not
    /// the place to raise a system prompt, so it says what is missing and leaves the request to the
    /// surface that owns it.
    var calendarUnavailableNotice: String?
    let actions: CadenceSchedulePanelActions

    @State private var isDoExpanded = false
    @State private var isDueExpanded = false
    @State private var isDoTimeExpanded = false
    @State private var isEventScheduleExpanded = false
    @State private var showListPicker = false
    @State private var showSectionPicker = false
    @State private var showCalendarPicker = false
    @State private var showRepeatPicker = false
    @State private var doViewMonth = Date()
    @State private var dueViewMonth = Date()
    @State private var actionError: String?
    @FocusState private var isTitleFocused: Bool

    /// The panel's width where its host gives it none — a popover has no container to be a fraction
    /// of. A sheet or an inspector column overrides it with its own frame.
    static let preferredWidth: CGFloat = 372

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            kindSwitch
            titleRow
            if draft.kind == .task {
                taskSchedule
                listAndSection
            } else {
                eventSchedule
                locationRow
                calendarRow
            }
            notesRow
            if let actionError {
                CadenceInlineNotice(text: actionError, tone: .failure)
            }
            footer
        }
        .padding(14)
        .background(Theme.surfaceElevated)
        .onAppear { isTitleFocused = !draft.subject.isEditing }
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
        HStack(spacing: 6) {
            ForEach(CadenceScheduleDraftKind.allCases) { kind in
                let isSelected = draft.kind == kind
                Button { draft.kind = kind } label: {
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
            }
        }
        // A kind switch on an existing record would offer to turn a saved task into an event,
        // which is a move between two stores and not an edit. Editing shows which kind it is and
        // does not offer to change it.
        .opacity(draft.subject.isEditing ? 0.45 : 1)
        .disabled(draft.subject.isEditing)
    }

    /// The title, with priority as a compact flag at its trailing edge.
    ///
    /// **Priority rides here rather than in a row of its own**, which is what frees the slot beside
    /// the list control for Section. A flag cycles on activation and needs no label — it is the same
    /// control `iOSCalendarQuickCreateSheet`'s header carries, in the same place relative to the
    /// field it qualifies.
    private var titleRow: some View {
        CadenceFieldSection(title: nil, style: .ruled) {
            HStack(alignment: .top, spacing: 8) {
                TextField(draft.kind.titlePlaceholder, text: $draft.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .cadenceFont(.fieldValue, base: 16, weight: .bold)
                    .foregroundStyle(Theme.text)
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

                if draft.kind == .task {
                    Button(action: cyclePriority) {
                        Image(systemName: "flag.fill")
                            .cadenceFont(.controlLabel)
                            .foregroundStyle(Theme.priorityColor(draft.priority))
                            .frame(width: 32, height: 32)
                            .background(Theme.priorityColor(draft.priority).opacity(0.13))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.cadencePlain)
                    .accessibilityLabel("Priority: \(draft.priority.label)")
                    // **The outcome, not the gesture** (T-521, and this panel is why that sweep
                    // covers `Shared/`). This control's hint read "Tap to cycle priority", which
                    // was copied from `iOSCalendarQuickCreateSheet` — where it is correct, because
                    // that sheet is under `#if os(iOS)` and touch is the only way to reach it. This
                    // panel is shared, so on the Mac the hint named a gesture that surface does not
                    // have: VoiceOver activates a control there with Control-Option-Space.
                    .accessibilityHint("Changes the priority to the next level")
                }
            }
        }
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
            disclosureRow(
                label: "Do",
                value: draft.doRowLabel,
                systemImage: "calendar",
                color: Theme.blue,
                isExpanded: $isDoExpanded
            )

            if isDoExpanded {
                CadenceFieldDivider()
                // The DUE day is marked on this grid, in amber with the word in the cell, so the
                // two dates being reconciled are visible together rather than one row apart.
                CadenceQuickDatePopover(
                    selection: doDateBinding,
                    viewMonth: $doViewMonth,
                    isOpen: .constant(true),
                    showsClear: false,
                    inlineStyle: true,
                    markedDay: draft.dueDateKey.isEmpty ? nil : DateFormatters.date(from: draft.dueDateKey)
                )

                CadenceFieldDivider()
                doTimeRow
                CadenceFieldDivider()
                repeatRow
            }
        }

        CadenceFieldSection(title: nil, style: .ruled) {
            disclosureRow(
                label: "Due",
                value: draft.dueRowLabel,
                systemImage: "calendar.badge.exclamationmark",
                color: Theme.amber,
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
            if draft.isAllDay {
                draft.isAllDay = false
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
                    .foregroundStyle(draft.isAllDay ? Theme.dim : Theme.text)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 36)
        }
        .buttonStyle(.cadencePlain)

        if !draft.isAllDay && isDoTimeExpanded {
            CadenceTimeRoller(minutes: doStartMinuteBinding) { isDoTimeExpanded = false }

            CadenceFieldRow(label: "Length", systemImage: "timer", color: Theme.green) {
                EstimatePickerControl(value: durationBinding, pickerTitle: "LENGTH")
            }

            Button {
                draft.isAllDay = true
                isDoTimeExpanded = false
            } label: {
                Text("Remove time")
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
                if !draft.isAllDay && !draft.spansMultipleDays {
                    CadenceTimeRollerFieldRow(
                        label: "End",
                        systemImage: "clock.badge.checkmark",
                        minutes: eventEndMinuteBinding
                    )
                }

                CadenceFieldDivider()
                repeatRow
            }
        }
    }

    private var locationRow: some View {
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

    /// Plain text, not the full markdown well the two creation sheets carry.
    ///
    /// That well brings an accessory bar, an image inserter and two reference sheets of its own,
    /// and a popover that can present a sheet from inside itself is a presentation knot rather than
    /// a feature. The field writes the same `AppTask.notes` / `EKEvent.notes` either way, and both
    /// stay markdown — a note started here opens in the full editor afterwards.
    private var notesRow: some View {
        CadenceFieldSection(title: nil, style: .ruled) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.alignleft")
                    .cadenceFont(.metadata)
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 4)
                TextField("Add notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .cadenceFont(.fieldValue)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...4)
            }
            .frame(minHeight: 36)
        }
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
            if let delete = actions.delete {
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

            Button(action: actions.cancel) {
                Text("Cancel")
                    .cadenceFont(.controlLabel, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)

            Button(action: commit) {
                Text(draft.subject.isEditing ? "Save" : "Add")
                    .cadenceFont(.controlLabel, weight: .semibold)
                    .foregroundStyle(Theme.onColor(for: Theme.blue))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(draft.hasCommittableTitle ? Theme.blue : Theme.blue.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .disabled(!draft.hasCommittableTitle)
        }
    }

    private func commit() {
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

    private var durationBinding: Binding<Int> {
        Binding(
            get: { draft.durationMinutes },
            set: { draft.moveEndEdge(toMinute: draft.startMin + max(CadenceScheduleDraft.minimumDurationMinutes, $0)) }
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
                if draft.endDateKey < key { draft.endDateKey = key }
            }
        )
    }

    private var eventEndDayBinding: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: draft.endDateKey) ?? Date() },
            set: { draft.endDateKey = max(DateFormatters.dateKey(from: $0), draft.startDateKey) }
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
            set: { draft.moveEndEdge(toMinute: $0) }
        )
    }
}
