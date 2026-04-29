#if os(macOS)
import SwiftUI
import EventKit

@Observable
final class NotesNavigationManager {
    struct Request: Equatable {
        var page: NotesView.NotesPage
        var eventNoteID: UUID?
        var token: UUID = UUID()
    }

    static let shared = NotesNavigationManager()

    var request: Request?

    private init() {}

    func openMeetingNote(id: UUID) {
        request = Request(page: .meeting, eventNoteID: id)
    }

    func clear() {
        request = nil
    }
}

struct EventNoteEditorSheet: View {
    @Bindable var note: Note
    let eventTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Event note title", text: $note.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(eventTitle.isEmpty ? "Linked event note" : eventTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().background(Theme.borderSubtle)

            MarkdownEditor(text: Binding(
                get: { note.content },
                set: {
                    note.content = $0
                    note.updatedAt = Date()
                }
            ))
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.bg)
    }
}

enum EventNoteSupport {
    static func note(for calendarEventID: String, in notes: [Note]) -> Note? {
        notes.first { $0.kind == .meeting && $0.calendarEventID == calendarEventID }
    }

    @discardableResult
    static func noteForEditing(
        calendarEventID: String,
        eventTitle: String,
        calendarID: String = "",
        eventDateKey: String = "",
        eventStartMin: Int = -1,
        eventEndMin: Int = -1,
        notes: [Note],
        insert: (Note) -> Void
    ) -> Note? {
        guard !calendarEventID.isEmpty else { return nil }
        if let existing = note(for: calendarEventID, in: notes) {
            if existing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Event Note" : eventTitle
            }
            updateMetadata(
                existing,
                calendarID: calendarID,
                eventDateKey: eventDateKey,
                eventStartMin: eventStartMin,
                eventEndMin: eventEndMin
            )
            return existing
        }

        let resolvedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Event Note" : eventTitle
        let created = Note(
            kind: .meeting,
            title: resolvedTitle,
            content: "# \(resolvedTitle)\n\n",
            calendarEventID: calendarEventID,
            calendarID: calendarID,
            eventDateKey: eventDateKey,
            eventStartMin: eventStartMin,
            eventEndMin: eventEndMin
        )
        insert(created)
        return created
    }

    static func eventDateMetadata(from event: EKEvent) -> (dateKey: String, startMin: Int, endMin: Int) {
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start
        let startComps = Calendar.current.dateComponents([.hour, .minute], from: start)
        let endComps = Calendar.current.dateComponents([.hour, .minute], from: end)
        return (
            DateFormatters.dateKey(from: start),
            ((startComps.hour ?? 0) * 60) + (startComps.minute ?? 0),
            ((endComps.hour ?? 0) * 60) + (endComps.minute ?? 0)
        )
    }

    static func backfillMetadataIfPossible(_ note: Note, calendarManager: CalendarManager) {
        guard note.kind == .meeting else { return }
        guard let event = calendarManager.event(withIdentifier: note.calendarEventID) else { return }
        let metadata = eventDateMetadata(from: event)
        updateMetadata(
            note,
            calendarID: event.calendar.calendarIdentifier,
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin
        )
    }

    static func updateMetadata(
        _ note: Note,
        calendarID: String,
        eventDateKey: String,
        eventStartMin: Int,
        eventEndMin: Int
    ) {
        var changed = false
        if !calendarID.isEmpty, note.calendarID != calendarID {
            note.calendarID = calendarID
            changed = true
        }
        if !eventDateKey.isEmpty, note.eventDateKey != eventDateKey {
            note.eventDateKey = eventDateKey
            changed = true
        }
        if eventStartMin >= 0, note.eventStartMin != eventStartMin {
            note.eventStartMin = eventStartMin
            changed = true
        }
        if eventEndMin >= 0, note.eventEndMin != eventEndMin {
            note.eventEndMin = eventEndMin
            changed = true
        }
        if changed {
            note.updatedAt = Date()
        }
    }
}
#endif
