#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

// MARK: - Calendar Event Edit Popover

struct CalendarEventEditPopover: View {
    let item: CalendarEventItem
    let onSave: (String, Int, Int, String, CalendarRecurrenceEditScope) -> Void
    let onDelete: (CalendarRecurrenceEditScope) -> Void
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    @State private var title: String
    @State private var startMin: Int
    @State private var endMin: Int
    @State private var startText: String
    @State private var endText: String
    @State private var selectedCalendarID: String
    @State private var presentedEventNote: Note?
    @State private var pendingAction: PendingAction?

    private enum PendingAction {
        case save
        case delete
    }

    init(
        item: CalendarEventItem,
        onSave: @escaping (String, Int, Int, String, CalendarRecurrenceEditScope) -> Void,
        onDelete: @escaping (CalendarRecurrenceEditScope) -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        let s = item.startMin
        let e = item.startMin + item.durationMinutes
        _title = State(initialValue: item.title)
        _startMin = State(initialValue: s)
        _endMin   = State(initialValue: e)
        _startText = State(initialValue: TimeFormatters.timeString(from: s))
        _endText   = State(initialValue: TimeFormatters.timeString(from: e))
        _selectedCalendarID = State(initialValue: item.ekEvent.calendar.calendarIdentifier)
    }

    private var durationMinutes: Int { max(0, endMin - startMin) }
    private var eventNotes: [Note] {
        allNotes.filter { $0.kind == .meeting }
    }

    private var linkedEventNote: Note? {
        let metadata = EventNoteSupport.eventDateMetadata(from: item.ekEvent)
        return EventNoteSupport.note(
            for: item.id,
            eventTitle: item.title,
            calendarID: item.ekEvent.calendar.calendarIdentifier,
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin,
            in: eventNotes
        )
    }

    private var durationLabel: String {
        let mins = durationMinutes
        if mins <= 0 { return "–" }
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60; let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var body: some View {
        editorContent
        .frame(width: 320)
        .cadenceCard(cornerRadius: Theme.radiusPanel)
        .sheet(isPresented: Binding(
            get: { presentedEventNote != nil },
            set: { if !$0 { presentedEventNote = nil } }
        )) {
            if let presentedEventNote {
                EventNoteEditorSheet(note: presentedEventNote, eventTitle: item.title, nativeEvent: item.ekEvent)
            }
        }
        .confirmationDialog(
            "Change recurring event?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(CalendarRecurrenceEditScope.thisOccurrence.label) {
                applyPendingAction(scope: .thisOccurrence)
            }
            Button(CalendarRecurrenceEditScope.futureOccurrences.label) {
                applyPendingAction(scope: .futureOccurrences)
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("Choose whether this calendar change applies only to this occurrence or to this and future events.")
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                timeCard
                calendarCard
                linkedNoteCard
                actionButtons
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(item.calendarColor.opacity(0.2))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.calendarColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Event title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                calendarLabel
            }

            Spacer()

            Text(durationLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var calendarLabel: some View {
        if !item.calendarTitle.isEmpty || item.isRecurringSeriesMember {
            HStack(spacing: 5) {
                if !item.calendarTitle.isEmpty {
                    Circle()
                        .fill(item.calendarColor)
                        .frame(width: 7, height: 7)
                    Text(item.calendarTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                if item.isRecurringSeriesMember {
                    Image(systemName: "repeat")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                    Text("Repeats")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var timeCard: some View {
        infoCard {
            timeFieldRow(label: "Start", icon: "clock", text: $startText) {
                if let parsed = parseTime(startText) { startMin = parsed }
                startText = TimeFormatters.timeString(from: startMin)
            }
            timeFieldRow(label: "End", icon: "clock.badge.checkmark", text: $endText) {
                if let parsed = parseTime(endText) { endMin = parsed }
                endText = TimeFormatters.timeString(from: endMin)
            }
        }
    }

    private var calendarCard: some View {
        infoCard {
            HStack(spacing: 10) {
                Label("Calendar", systemImage: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 88, alignment: .leading)
                CadenceCalendarPickerButton(
                    calendars: calendarManager.writableCalendars,
                    selectedID: $selectedCalendarID
                )
                Spacer(minLength: 0)
            }
        }
    }

    private var linkedNoteCard: some View {
        infoCard {
            HStack(alignment: .center, spacing: 10) {
                Label("Note", systemImage: "doc.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 88, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(linkedEventNote?.displayTitle ?? "No linked note yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(linkedEventNote == nil ? Theme.dim : Theme.text)
                        .lineLimit(1)
                    Text(linkedEventNote == nil ? "Create a markdown note for this event." : "Open the note linked to this event.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button(linkedEventNote == nil ? "Create" : "Open") {
                    openEventNote()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button { requestAction(.save) } label: {
                Label("Save", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.cadencePlain)

            Button { requestAction(.delete) } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.cadencePlain)
        }
    }

    private func requestAction(_ action: PendingAction) {
        if item.isRecurringSeriesMember {
            pendingAction = action
        } else {
            applyAction(action, scope: .thisOccurrence)
        }
    }

    private func applyPendingAction(scope: CalendarRecurrenceEditScope) {
        guard let pendingAction else { return }
        self.pendingAction = nil
        applyAction(pendingAction, scope: scope)
    }

    private func applyAction(_ action: PendingAction, scope: CalendarRecurrenceEditScope) {
        switch action {
        case .save:
            onSave(title, startMin, durationMinutes, selectedCalendarID, scope)
        case .delete:
            onDelete(scope)
        }
    }

    @ViewBuilder
    private func timeFieldRow(label: String, icon: String, text: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 88, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .onSubmit(onCommit)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .cadenceCard(background: Theme.surface.opacity(0.85), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }

    /// Parses a time string like "4:55 PM", "16:55", "4 PM" → minutes from midnight.
    private func parseTime(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let isPM = s.contains("pm")
        let isAM = s.contains("am")
        let digits = s.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "").trimmingCharacters(in: .whitespaces)
        let parts = digits.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let h = parts.first ?? nil else { return nil }
        let m = parts.count > 1 ? (parts[1] ?? 0) : 0
        var hour = h
        if isPM && hour != 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        guard hour >= 0, hour < 24, m >= 0, m < 60 else { return nil }
        return hour * 60 + m
    }

    private func openEventNote() {
        let metadata = EventNoteSupport.eventDateMetadata(from: item.ekEvent)
        presentedEventNote = EventNoteSupport.noteForEditing(
            calendarEventID: item.id,
            eventTitle: item.title,
            calendarID: item.ekEvent.calendar.calendarIdentifier,
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin,
            nativeNotes: item.ekEvent.notes,
            notes: eventNotes
        ) { modelContext.insert($0) }
    }
}
#endif
