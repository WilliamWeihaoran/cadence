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
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var notesEditorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @State private var notesEditorFocused = false
    @State private var presentedEventNote: Note?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @State private var confirmDelete = false
    @State private var pendingAction: PendingAction?

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

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        calendarManager.writableCalendars.contains { $0.calendarIdentifier == selectedCalendarID }
    }

    private var isRecurringEvent: Bool {
        event.hasRecurrenceRules || event.isDetached || event.occurrenceDate != nil
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

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var notesEditorModeBinding: Binding<iOSMarkdownEditorMode> {
        iOSMarkdownEditorPreferences.binding(for: $notesEditorModeRaw)
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
                    .padding(isRegularWidth ? 20 : 18)
            }
            .background(Theme.bg)
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
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
                titleCard
                scheduleCard
                calendarCard
            }
            .frame(minWidth: 340, maxWidth: 440, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 16) {
                eventNoteCard
                notesCard
                deleteCard
            }
            .frame(minWidth: 360, maxWidth: 520, alignment: .topLeading)
        }
        .frame(maxWidth: 980, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var titleCard: some View {
        iOSCalendarEventEditorSection(title: "Event") {
            TextField("Event title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1...3)
        }
    }

    private var scheduleCard: some View {
        iOSCalendarEventEditorSection(title: "Schedule") {
            Toggle(isOn: $isAllDay) {
                iOSCalendarEventEditorInlineLabel(label: "All day", systemImage: "sun.max", color: Theme.amber)
            }
            .toggleStyle(.switch)
            .tint(Theme.blue)

            iOSCalendarEventEditorDivider()

            DatePicker("Starts", selection: $startDate, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .tint(Theme.blue)

            iOSCalendarEventEditorDivider()

            if isAllDay {
                iOSCalendarEventEditorRow(label: "Days", systemImage: "calendar", color: Theme.green) {
                    Stepper(value: $allDayDurationDays, in: 1...365, step: 1) {
                        Text(allDayDurationDays == 1 ? "1 day" : "\(allDayDurationDays) days")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
            } else {
                iOSCalendarEventEditorRow(label: "Duration", systemImage: "timer", color: Theme.green) {
                    Stepper(value: $durationMinutes, in: 5...480, step: 5) {
                        Text(durationLabel(durationMinutes))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
            }
        }
    }

    private var calendarCard: some View {
        iOSCalendarEventEditorSection(title: "Apple Calendar") {
            if calendarManager.writableCalendars.isEmpty {
                Text("No writable calendars are available.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
            } else {
                iOSCalendarEventEditorRow(label: "Calendar", systemImage: "calendar", color: Theme.blue) {
                    Picker("Calendar", selection: $selectedCalendarID) {
                        ForEach(calendarManager.writableCalendars, id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(calendar.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var eventNoteCard: some View {
        iOSCalendarEventEditorSection(title: "Meeting Note") {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.purple)
                    .frame(width: 34, height: 34)
                    .background(Theme.purple.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(linkedEventNote?.displayTitle ?? "No linked note yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(linkedEventNote == nil ? Theme.dim : Theme.text)
                        .lineLimit(1)
                    Text(linkedEventNote == nil ? "Create a markdown note for this event." : "Open the note linked to this event.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button(linkedEventNote == nil ? "Create" : "Open") {
                    openEventNote()
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(Theme.blue)
            }
        }
    }

    private var notesCard: some View {
        iOSCalendarEventEditorSection(title: "Notes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Apple Calendar note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)

                    Spacer(minLength: 0)

                    iOSMarkdownModePicker(mode: notesEditorModeBinding, compact: true)
                }

                iOSMarkdownEditingSurface(
                    text: $notes,
                    isFocused: $notesEditorFocused,
                    mode: notesEditorModeBinding,
                    placeholder: "Add markdown notes...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference,
                    allowsEmbeddedTaskCreation: false
                )
                .frame(minHeight: isRegularWidth ? 300 : 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.68), lineWidth: 1)
                }
            }
        }
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

    private var deleteCard: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete Event", systemImage: "trash")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.red)
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
        ) else { return }
        dismiss()
    }

    private func applyDelete(scope: iOSCalendarRecurrenceEditScope) {
        if calendarManager.deleteEvent(event, span: scope.eventSpan) {
            dismiss()
        }
    }

    private func ensureWritableCalendar() {
        guard calendarManager.writableCalendars.contains(where: { $0.calendarIdentifier == selectedCalendarID }) else {
            selectedCalendarID = calendarManager.writableCalendars.first?.calendarIdentifier ?? ""
            return
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct iOSCalendarEventEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

private struct iOSCalendarEventEditorRow<Content: View>: View {
    let label: String
    let systemImage: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            iOSCalendarEventEditorInlineLabel(label: label, systemImage: systemImage, color: color)
            Spacer(minLength: 12)
            content()
        }
        .frame(minHeight: 34)
    }
}

private struct iOSCalendarEventEditorInlineLabel: View {
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
    }
}

private struct iOSCalendarEventEditorDivider: View {
    var body: some View {
        Divider().background(Theme.borderSubtle.opacity(0.6))
    }
}

#endif
