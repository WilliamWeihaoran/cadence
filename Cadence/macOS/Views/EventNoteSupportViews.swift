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
    var nativeEvent: EKEvent?
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarManager.self) private var calendarManager

    var body: some View {
        NoteEditorPane(
            note: note,
            onPersistContent: syncNativeEventNotes,
            headerDetail: eventTitle.isEmpty ? "Linked event note" : eventTitle,
            headerAccessory: AnyView(
                HStack(spacing: 10) {
                    NoteActionMenu(note: note)
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                }
            )
        )
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.bg)
    }

    private func syncNativeEventNotes(_ note: Note, content: String) {
        if let nativeEvent {
            calendarManager.updateEventNotes(nativeEvent, notes: content)
            return
        }
        EventNoteSupport.syncNativeCalendarNotes(for: note, content: content, calendarManager: calendarManager)
    }
}

enum EventNoteSupport {
    static func note(for calendarEventID: String, in notes: [Note]) -> Note? {
        CadenceEventNoteSupport.note(for: calendarEventID, in: notes)
    }

    static func note(
        for calendarEventID: String,
        eventTitle: String,
        calendarID: String,
        eventDateKey: String,
        eventStartMin: Int,
        eventEndMin: Int,
        in notes: [Note]
    ) -> Note? {
        CadenceEventNoteSupport.note(
            for: calendarEventID,
            eventTitle: eventTitle,
            calendarID: calendarID,
            eventDateKey: eventDateKey,
            eventStartMin: eventStartMin,
            eventEndMin: eventEndMin,
            in: notes
        )
    }

    // Defaults deliberately absent, mirroring `CadenceEventNoteSupport.noteForEditing` — this
    // wrapper re-declared them, so the unsafe short spelling was available here too.
    @discardableResult
    static func noteForEditing(
        calendarEventID: String,
        eventTitle: String,
        calendarID: String,
        eventDateKey: String,
        eventStartMin: Int,
        eventEndMin: Int,
        nativeNotes: String? = nil,
        notes: [Note],
        insert: (Note) -> Void
    ) -> Note? {
        CadenceEventNoteSupport.noteForEditing(
            calendarEventID: calendarEventID,
            eventTitle: eventTitle,
            calendarID: calendarID,
            eventDateKey: eventDateKey,
            eventStartMin: eventStartMin,
            eventEndMin: eventEndMin,
            nativeNotes: nativeNotes,
            notes: notes,
            insert: insert
        )
    }

    static func initialContent(eventTitle: String, nativeNotes: String?) -> String {
        CadenceEventNoteSupport.initialContent(eventTitle: eventTitle, nativeNotes: nativeNotes)
    }

    static func syncNativeCalendarNotes(for note: Note, content: String, calendarManager: CalendarManager) {
        guard note.kind == .meeting, !note.calendarEventID.isEmpty else { return }
        calendarManager.updateEventNotes(calendarEventID: note.calendarEventID, notes: content)
    }

    static func eventDateMetadata(from event: EKEvent) -> (dateKey: String, startMin: Int, endMin: Int) {
        CadenceEventNoteSupport.eventDateMetadata(from: event)
    }

    static func backfillMetadataIfPossible(_ note: Note, calendarManager: CalendarManager) {
        guard note.kind == .meeting else { return }
        let lookupID = CalendarEventIdentity.lookupIdentifier(from: note.calendarEventID)
        guard let event = calendarManager.event(withIdentifier: lookupID) else { return }
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
        CadenceEventNoteSupport.updateMetadata(
            note,
            calendarID: calendarID,
            eventDateKey: eventDateKey,
            eventStartMin: eventStartMin,
            eventEndMin: eventEndMin
        )
    }

    static func meetingNotes(forLinkedCalendarID calendarID: String, in notes: [Note]) -> [Note] {
        CadenceEventNoteSupport.meetingNotes(forLinkedCalendarID: calendarID, in: notes)
    }
}
#endif
