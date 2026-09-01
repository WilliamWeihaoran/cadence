#if os(macOS)
import SwiftUI
import SwiftData
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

/// The one place a macOS event-note editor says which of the note's two writes did not happen.
///
/// Same failure-line spelling as `iOSEventNoteEditorSheet`'s notice (12pt medium, `Theme.red`), and
/// a shared view rather than a second copy because T-389 was two macOS editors of the same note
/// disagreeing about whether there was anything to report at all.
struct EventNoteCommitNoticeBanner: View {
    let notice: String?

    var body: some View {
        if let notice {
            VStack(spacing: 0) {
                Divider().background(Theme.borderSubtle)
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }
}

struct EventNoteEditorSheet: View {
    @Bindable var note: Note
    let eventTitle: String
    var nativeEvent: EKEvent?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @State private var commitNotice: String?

    var body: some View {
        VStack(spacing: 0) {
            NoteEditorPane(
                note: note,
                onPersistContent: commitEventNote,
                headerDetail: CadenceTitleNormalization.display(eventTitle, fallback: "Linked event note"),
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

            EventNoteCommitNoticeBanner(notice: commitNotice)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.bg)
    }

    /// **T-389.** This used to push the body straight into the native `EKEvent` and drop whatever
    /// `CalendarManager` said about it, so a stale `calendarEventID` meant the edit stayed in
    /// Cadence, never reached Apple Calendar, and showed none of iOS's "saved but not synced"
    /// notice. It goes through the same ordered commit iOS uses now — local first, mirror only if
    /// the local commit landed — and shows the outcome it returns.
    private func commitEventNote(_ note: Note, content: String) {
        let outcome = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: { try modelContext.save() },
            syncToNativeEvent: { syncNativeEventNotes(note, content: content) }
        )
        commitNotice = outcome.notice
    }

    /// Whether Apple Calendar now holds this text. The timeline hands the sheet the live `EKEvent`
    /// it is already rendering, which skips a lookup that a churned identifier could fail.
    private func syncNativeEventNotes(_ note: Note, content: String) -> Bool {
        if let nativeEvent {
            return calendarManager.updateEventNotes(nativeEvent, notes: content) == nil
        }
        return EventNoteSupport.syncNativeCalendarNotes(for: note, content: content, calendarManager: calendarManager)
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

    /// Whether Apple Calendar now holds this note's text.
    ///
    /// **T-389.** This returned `Void`, and its one caller discarded what `CalendarManager` told
    /// it. The return type is the fix, and it is deliberately **not** `@discardableResult`:
    /// dropping the answer again is a compile error rather than a silent regression.
    ///
    /// A note with no native event to mirror into has nothing that can fail, so it is not a miss —
    /// the same rule as `iOSEventNoteEditorSheet.syncNoteToNativeEvent`. Otherwise every ordinary
    /// note would wear the "not synced" notice.
    static func syncNativeCalendarNotes(for note: Note, content: String, calendarManager: CalendarManager) -> Bool {
        guard note.kind == .meeting, !note.calendarEventID.isEmpty else { return true }
        return calendarManager.updateEventNotes(calendarEventID: note.calendarEventID, notes: content) == nil
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
