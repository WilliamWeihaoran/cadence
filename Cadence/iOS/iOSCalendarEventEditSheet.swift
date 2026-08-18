#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarEventSelection: Identifiable {
    let event: EKEvent

    var id: String {
        let rawID = event.eventIdentifier ?? event.calendarItemIdentifier
        let start = event.startDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(rawID)-\(start)"
    }
}

private enum iOSCalendarRecurrenceEditScope: String, CaseIterable, Hashable {
    case thisOccurrence
    case futureOccurrences

    var label: String {
        switch self {
        case .thisOccurrence: return "Only This Event"
        case .futureOccurrences: return "This And Future Events"
        }
    }

    var eventSpan: EKSpan {
        switch self {
        case .thisOccurrence: return .thisEvent
        case .futureOccurrences: return .futureEvents
        }
    }
}

struct iOSCalendarEventEditSheet: View {
    let event: EKEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var title: String
    @State private var startDate: Date
    @State private var durationMinutes: Int
    @State private var allDayDurationDays: Int
    @State private var isAllDay: Bool
    @State private var selectedCalendarID: String
    @State private var notes: String
    @State private var notesEditorFocused = false
    @State private var presentedEventNote: Note?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @State private var confirmDelete = false
    @State private var actionError: String?
    @State private var pendingAction: PendingAction?
    @State private var showCalendarPicker = false
    @State private var showStartTimePicker = false
    @State private var showDaysPicker = false

    /// `CadenceDatePicker` returns midnight-anchored day dates — merge just the Y/M/D into the
    /// existing `startDate` so picking a new day doesn't silently zero out the time-of-day.
    private var startDateOnlyBinding: Binding<Date> {
        Binding(
            get: { startDate },
            set: { newDay in
                let dayComps = Calendar.current.dateComponents([.year, .month, .day], from: newDay)
                var comps = Calendar.current.dateComponents([.hour, .minute], from: startDate)
                comps.year = dayComps.year
                comps.month = dayComps.month
                comps.day = dayComps.day
                startDate = Calendar.current.date(from: comps) ?? startDate
            }
        )
    }

    private var startTimeMinutesBinding: Binding<Int> {
        Binding(
            get: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: startDate)
                return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            },
            set: { minutes in
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: startDate)
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                startDate = Calendar.current.date(from: comps) ?? startDate
            }
        )
    }

    private enum PendingAction {
        case save
        case delete
    }

    private var endDate: Date {
        if isAllDay {
            let startOfDay = Calendar.current.startOfDay(for: startDate)
            return Calendar.current.date(byAdding: .day, value: max(1, allDayDurationDays), to: startOfDay) ?? startOfDay
        }
        return Calendar.current.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate) ?? startDate
    }

    private var normalizedStartDate: Date {
        isAllDay ? Calendar.current.startOfDay(for: startDate) : startDate
    }

    /// EventKit refuses writes to Birthdays, Holidays and subscribed calendars, and the sheet is
    /// reachable from the calendar inspector and from search for exactly those events.
    private var isEditable: Bool {
        calendarManager.canModify(event)
    }

    private var writableCalendarIDs: [String] {
        calendarManager.writableCalendars.map(\.calendarIdentifier)
    }

    private var eventCalendarName: String {
        event.calendar?.title ?? ""
    }

    private var canSave: Bool {
        CadenceCalendarEventEditingSupport.canSave(
            title: title,
            isEventEditable: isEditable,
            selectedCalendarID: selectedCalendarID,
            writableCalendarIDs: writableCalendarIDs
        )
    }

    private var isRecurringEvent: Bool {
        CadenceEventNoteSupport.isRecurringSeriesMember(event)
    }

    private var eventNoteID: String {
        CadenceEventNoteSupport.identifier(for: event)
    }

    private var eventMetadata: (dateKey: String, startMin: Int, endMin: Int) {
        CadenceEventNoteSupport.eventDateMetadata(from: event)
    }

    private var linkedEventNote: Note? {
        CadenceEventNoteSupport.note(
            for: eventNoteID,
            eventTitle: iOSCalendarEventSupport.title(for: event),
            calendarID: event.calendar?.calendarIdentifier ?? selectedCalendarID,
            eventDateKey: eventMetadata.dateKey,
            eventStartMin: eventMetadata.startMin,
            eventEndMin: eventMetadata.endMin,
            in: allNotes
        )
    }

    /// Read for two things only: the sheet's gutter, and whether the form splits into two columns.
    /// Both are facts about the host. Nothing the sheet *draws* consults it — those figures are
    /// `iOSEditorSheetMetrics`, which takes no width.
    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    init(event: EKEvent) {
        self.event = event
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start.addingTimeInterval(30 * 60)
        _title = State(initialValue: iOSCalendarEventSupport.title(for: event))
        _startDate = State(initialValue: start)
        _durationMinutes = State(initialValue: max(5, Int(end.timeIntervalSince(start) / 60)))
        _allDayDurationDays = State(initialValue: max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: end)).day ?? 1))
        _isAllDay = State(initialValue: event.isAllDay)
        _selectedCalendarID = State(initialValue: event.calendar?.calendarIdentifier ?? "")
        _notes = State(initialValue: event.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                formLayout
                    .padding(iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth))
            }
            .background(Theme.bg)
            .navigationTitle(isEditable ? "Edit Event" : "Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditable ? "Cancel" : "Done") { dismiss() }
                }
                // No Save at all on a read-only event. It used to be enabled, and tapping it
                // threw inside EventKit, returned false, and left the sheet open with nothing
                // said — an enabled control that did nothing.
                if isEditable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(!canSave)
                    }
                }
            }
            .confirmationDialog("Delete Event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Event", role: .destructive) {
                    requestDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the event from Apple Calendar.")
            }
            .confirmationDialog(
                "Change recurring event?",
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(iOSCalendarRecurrenceEditScope.thisOccurrence.label) {
                    applyPendingAction(scope: .thisOccurrence)
                }
                Button(iOSCalendarRecurrenceEditScope.futureOccurrences.label) {
                    applyPendingAction(scope: .futureOccurrences)
                }
                Button("Cancel", role: .cancel) {
                    pendingAction = nil
                }
            } message: {
                Text("Choose whether this calendar change applies only to this occurrence or to this and future events.")
            }
            .onAppear(perform: ensureWritableCalendar)
            .onChange(of: calendarManager.storeVersion) { _, _ in
                notes = event.notes ?? ""
            }
            .sheet(item: $presentedEventNote) { note in
                iOSEventNoteEditorSheet(note: note, eventTitle: title, event: event)
            }
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var formLayout: some View {
        if isRegularWidth {
            regularFormLayout
        } else {
            compactFormLayout
        }
    }

    private var compactFormLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            readOnlyNotice
            actionErrorNotice
            titleCard
            scheduleCard
            calendarCard
            eventNoteCard
            notesCard
            deleteCard
        }
    }

    private var regularFormLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                readOnlyNotice
                titleCard
                scheduleCard
                calendarCard
            }
            .frame(
                minWidth: iOSEditorSheetMetrics.primaryColumnMinWidth,
                maxWidth: iOSEditorSheetMetrics.primaryColumnMaxWidth,
                alignment: .topLeading
            )

            VStack(alignment: .leading, spacing: 16) {
                eventNoteCard
                notesCard
                deleteCard
            }
            .frame(
                minWidth: iOSEditorSheetMetrics.secondaryColumnMinWidth,
                maxWidth: iOSEditorSheetMetrics.secondaryColumnMaxWidth,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: iOSEditorSheetMetrics.twoColumnMaxWidth, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var actionErrorNotice: some View {
        if let actionError {
            Text(actionError)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)
        }
    }

    /// Says once, at the top, why the fields below are inert — instead of leaving the reader to
    /// discover it by tapping a Save button that silently failed.
    @ViewBuilder
    private var readOnlyNotice: some View {
        if !isEditable {
            HStack(alignment: .top, spacing: 12) {
                iOSIconTile(systemImage: "lock.fill", color: Theme.amber, size: 34, iconSize: 15)

                Text(CadenceCalendarEventEditingSupport.readOnlyNotice(calendarName: eventCalendarName))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)
        }
    }

    private var titleCard: some View {
        iOSEditorSection(title: "Event") {
            TextField("Event title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: iOSEditorSheetMetrics.titleSize, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1...iOSEditorSheetMetrics.titleLineLimit)
        }
        // Every field below is inert on a read-only event: there is no Save to carry an edit
        // anywhere, so letting one be typed would be the same false promise in a quieter form.
        .disabled(!isEditable)
    }

    // `contentSpacing` stays at its 0 default: every gap in here is an `iOSEditorDivider`, which
    // already pads itself 9pt each side. Adding 10 on top double-counted it and gave a 44pt row an
    // 83pt pitch — the same measurement that was taken out of the task inspector.
    private var scheduleCard: some View {
        iOSEditorSection(title: "Schedule") {
            Toggle(isOn: $isAllDay) {
                iOSEditorInlineLabel(label: "All day", systemImage: "sun.max", color: Theme.amber)
            }
            .toggleStyle(.switch)
            .tint(Theme.blue)

            iOSEditorDivider()

            iOSEditorFieldRow(label: "Date", systemImage: "calendar", color: Theme.blue) {
                CadenceDatePicker(selection: startDateOnlyBinding)
            }

            if !isAllDay {
                iOSEditorDivider()
                iOSEditorFieldRow(label: "Time", systemImage: "clock.fill", color: Theme.blue) {
                    iOSChoiceValueButton(title: TimeFormatters.timeString(from: startTimeMinutesBinding.wrappedValue), color: Theme.text) {
                        showStartTimePicker = true
                    }
                    .popover(isPresented: $showStartTimePicker) {
                        iOSChoicePopoverList(
                            rows: stride(from: 0, to: 1440, by: 15).map { minute in
                                iOSChoiceRow(value: minute, title: TimeFormatters.timeString(from: minute), color: Theme.blue)
                            },
                            selection: startTimeMinutesBinding,
                            isPresented: $showStartTimePicker
                        )
                    }
                }
            }

            iOSEditorDivider()

            if isAllDay {
                iOSEditorFieldRow(label: "Days", systemImage: "calendar", color: Theme.green) {
                    iOSChoiceValueButton(title: allDayDurationDays == 1 ? "1 day" : "\(allDayDurationDays) days", color: Theme.text) {
                        showDaysPicker = true
                    }
                    .popover(isPresented: $showDaysPicker) {
                        iOSChoicePopoverList(
                            rows: [1, 2, 3, 4, 5, 6, 7, 10, 14, 21, 30].map { days in
                                iOSChoiceRow(value: days, title: days == 1 ? "1 day" : "\(days) days", color: Theme.green)
                            },
                            selection: $allDayDurationDays,
                            isPresented: $showDaysPicker
                        )
                    }
                }
            } else {
                iOSEditorFieldRow(label: "Duration", systemImage: "timer", color: Theme.green) {
                    EstimatePickerControl(value: $durationMinutes)
                }
            }
        }
        .disabled(!isEditable)
    }

    private var calendarCard: some View {
        iOSEditorSection(title: "Apple Calendar") {
            if !isEditable {
                // The event's real calendar, stated plainly. A picker here could only offer
                // calendars this event cannot move to.
                iOSEditorFieldRow(label: "Calendar", systemImage: "calendar", color: Theme.dim) {
                    Text(eventCalendarName.isEmpty ? "Unknown calendar" : eventCalendarName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            } else if calendarManager.writableCalendars.isEmpty {
                Text("No writable calendars are available.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
            } else {
                iOSEditorFieldRow(label: "Calendar", systemImage: "calendar", color: Theme.blue) {
                    iOSChoiceValueButton(
                        title: calendarManager.writableCalendars.first { $0.calendarIdentifier == selectedCalendarID }?.title ?? "Choose Calendar",
                        color: Theme.text
                    ) {
                        showCalendarPicker = true
                    }
                    .popover(isPresented: $showCalendarPicker) {
                        iOSChoicePopoverList(
                            rows: calendarManager.writableCalendars.map { calendar in
                                iOSChoiceRow(value: calendar.calendarIdentifier, title: calendar.title, systemImage: "calendar", color: Theme.blue)
                            },
                            selection: $selectedCalendarID,
                            isPresented: $showCalendarPicker
                        )
                    }
                }
            }
        }
    }

    private var eventNoteCard: some View {
        iOSEditorSection(title: "Event Note") {
            HStack(alignment: .center, spacing: 12) {
                // 34/15, the same tile the read-only notice above draws. It was 34/16: one sheet,
                // two rows, one tile size, two glyph sizes — a tile resized without its glyph, in
                // the one place a reader can see both at once.
                iOSIconTile(systemImage: "doc.text", color: Theme.purple, size: 34, iconSize: 15)

                VStack(alignment: .leading, spacing: 3) {
                    Text(linkedEventNote?.displayTitle ?? "No linked note yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(linkedEventNote == nil ? Theme.dim : Theme.text)
                        .lineLimit(1)
                    Text(linkedEventNote == nil ? "Create a markdown note for this event." : "Open the note linked to this event.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                iOSActionButton(
                    title: linkedEventNote == nil ? "Create" : "Open",
                    role: .secondary,
                    size: .compact,
                    action: openEventNote
                )
            }
        }
    }

    private var notesCard: some View {
        iOSEditorSection(title: "Notes") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apple Calendar note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.subdued)

                iOSMarkdownEditingSurface(
                    text: $notes,
                    isFocused: $notesEditorFocused,
                    placeholder: "Add markdown notes...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference,
                    allowsEmbeddedTaskCreation: false
                )
                .iOSMarkdownWell()
            }
        }
        // The Apple Calendar note is written back through EventKit on save, which a read-only
        // calendar refuses. The *Cadence* event note above stays editable — it is our own data.
        .disabled(!isEditable)
    }

    private func openEventNote() {
        guard let note = CadenceEventNoteSupport.noteForEditing(
            calendarEventID: eventNoteID,
            eventTitle: title,
            calendarID: event.calendar?.calendarIdentifier ?? selectedCalendarID,
            eventDateKey: eventMetadata.dateKey,
            eventStartMin: eventMetadata.startMin,
            eventEndMin: eventMetadata.endMin,
            nativeNotes: event.notes,
            notes: allNotes,
            insert: { modelContext.insert($0) }
        ) else { return }

        try? modelContext.save()
        presentedEventNote = note
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }

    /// Absent, not disabled, on a read-only event: EventKit refuses the removal, so the button
    /// raised a confirmation dialog for a delete that could never happen.
    @ViewBuilder
    private var deleteCard: some View {
        if isEditable {
            iOSActionButton(
                title: "Delete Event",
                systemImage: "trash",
                role: .destructive,
                fullWidth: true
            ) {
                confirmDelete = true
            }
        }
    }

    private func save() {
        if isRecurringEvent {
            pendingAction = .save
            return
        }
        applySave(scope: .thisOccurrence)
    }

    private func requestDelete() {
        if isRecurringEvent {
            pendingAction = .delete
            return
        }
        applyDelete(scope: .thisOccurrence)
    }

    private func applyPendingAction(scope: iOSCalendarRecurrenceEditScope) {
        guard let pendingAction else { return }
        self.pendingAction = nil
        switch pendingAction {
        case .save:
            applySave(scope: scope)
        case .delete:
            applyDelete(scope: scope)
        }
    }

    private func applySave(scope: iOSCalendarRecurrenceEditScope) {
        guard calendarManager.updateEvent(
            event,
            title: title,
            startDate: normalizedStartDate,
            endDate: endDate,
            calendarID: selectedCalendarID,
            notes: notes,
            span: scope.eventSpan,
            isAllDay: isAllDay
        ) else {
            // A rejected write used to return here and do nothing at all: the sheet stayed open,
            // unchanged, with no indication that the save had failed.
            actionError = "Couldn't save this event to Apple Calendar."
            return
        }
        actionError = nil
        dismiss()
    }

    private func applyDelete(scope: iOSCalendarRecurrenceEditScope) {
        if calendarManager.deleteEvent(event, span: scope.eventSpan) {
            dismiss()
        } else {
            actionError = "Couldn't delete this event from Apple Calendar."
        }
    }

    /// Keeps a writable event pointed at a calendar the picker actually lists — and leaves a
    /// read-only event on its own calendar, which is the one thing this used to get wrong: it
    /// substituted the first writable calendar, so a Birthdays event's Calendar row read
    /// "Personal" and the sheet then offered to save it there.
    private func ensureWritableCalendar() {
        selectedCalendarID = CadenceCalendarEventEditingSupport.resolvedCalendarID(
            eventCalendarID: selectedCalendarID,
            isEventEditable: isEditable,
            writableCalendarIDs: writableCalendarIDs
        )
    }

}

#endif
