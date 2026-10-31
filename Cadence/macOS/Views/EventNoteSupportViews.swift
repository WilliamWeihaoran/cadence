#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

@Observable
final class NotesNavigationManager {
    struct Request: Equatable {
        var page: NotesView.NotesPage
        var eventNoteID: UUID?
        var noteID: UUID? = nil
        var token: UUID = UUID()
    }

    static let shared = NotesNavigationManager()

    var request: Request?

    private init() {}

    func openMeetingNote(id: UUID) {
        request = Request(page: .meeting, eventNoteID: id)
    }

    static func page(for kind: NoteKind) -> NotesView.NotesPage? {
        switch kind {
        case .daily: return .daily
        case .weekly: return .weekly
        case .permanent: return .notepad
        case .meeting: return .meeting
        case .list: return nil
        }
    }

    func openNote(id: UUID, kind: NoteKind) {
        guard let page = Self.page(for: kind) else { return }
        request = Request(page: page, eventNoteID: nil, noteID: id)
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
    /// [[T-5151]] (a): the store's notes and tasks, sorted as the Notes page sorts them. Without
    /// them `NoteEditorPane` defaulted both to `[]`, so in this sheet `[[` offered nothing, every
    /// `[[task:…]]` drew unresolved, and neither a task link nor a task chip found a task to open.
    ///
    /// [[T-5151]] (b), owner decision 2026-10-24: a `[[note]]` link or note chip clicked here
    /// dismisses the sheet and opens that note where every other note link goes — the Notes page,
    /// or a list note's own Notes tab — through `TaskNoteLinkRouting.openDismissing`. Swapping the
    /// sheet's note in place was declined: it would be a second navigation model with no way back.
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var commitNotice: String?
    /// The content Apple Calendar last took, or the note as this sheet opened it — [[T-8161]]
    /// rule (1)'s baseline. See `MacEventNoteCommit`.
    @State private var mirroredContent: String?

    var body: some View {
        VStack(spacing: 0) {
            NoteEditorPane(
                note: note,
                relatedNotes: allNotes,
                relatedTasks: allTasks,
                onOpenNote: { TaskNoteLinkRouting.openDismissing($0, dismiss: { dismiss() }) },
                onPersistContent: commitEventNote,
                headerDetail: CadenceTitleNormalization.display(eventTitle, fallback: "Linked event note"),
                // **T-5162.** The pane's append, not the menu's default store write: it flushes
                // the buffer, appends, and commits through `commitEventNote`, so a summary reaches
                // Apple Calendar and a failed mirror shows the notice like any other edit.
                summaryHeaderAccessory: { appendSummary in AnyView(
                    HStack(spacing: 10) {
                        NoteActionMenu(note: note, onAppendSummary: appendSummary)
                        // [[T-9453]]: the shared action button. A bare label under
                        // `.cadencePlain` made the hit area and the hover wash the word itself, a
                        // glyph-tight wash beside the padded Actions pill.
                        CadenceActionButton(title: "Done", role: .secondary, size: .compact) {
                            dismiss()
                        }
                    }
                ) },
                // **[[T-7336]].** Escape closes the sheet the way Done does, and through the same
                // `dismiss()`, so the pane's `onDisappear` flush commits the text either way. Not a
                // `.cancelAction` on Done: that is a key equivalent, offered every Escape before
                // the editor's own uses (a picker, a table cell, an inline task title, the inline
                // task panel), and it would close the sheet out from under each of them.
                onUnhandledEscape: { dismiss() }
            )

            EventNoteCommitNoticeBanner(notice: commitNotice)
        }
        .onAppear {
            if mirroredContent == nil { mirroredContent = note.content }
        }
        // Escape with focus outside the body (the title field, the header's controls).
        .onExitCommand { dismiss() }
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.bg)
    }

    /// **T-389.** This used to push the body straight into the native `EKEvent` and drop whatever
    /// `CalendarManager` said about it, so a stale `calendarEventID` meant the edit stayed in
    /// Cadence, never reached Apple Calendar, and showed none of iOS's "saved but not synced"
    /// notice. It goes through the same ordered commit iOS uses now — local first, mirror only if
    /// the local commit landed — and shows the outcome it returns.
    private func commitEventNote(_ note: Note, content: String) {
        // [[T-8161]] rule (1): the pane persists on a debounce and on dismissal, and a commit that
        // carries no change must not push this note over an edit made in Apple Calendar since.
        let outcome = MacEventNoteCommit.commitEventNote(
            note,
            content: content,
            nativeEvent: nativeEvent,
            syncToCalendar: CadenceEventNotesMerge.shouldMirror(content: content, lastMirrored: mirroredContent ?? ""),
            in: modelContext,
            calendarManager: calendarManager
        )
        if outcome == .saved {
            mirroredContent = content
        }
        commitNotice = outcome.notice
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
    /// the same rule as `iOSEventNoteCommit.syncNoteToNativeEvent`. Otherwise every ordinary
    /// note would wear the "not synced" notice.
    static func syncNativeCalendarNotes(for note: Note, content: String, calendarManager: CalendarManager) -> Bool {
        guard note.kind == .meeting, !note.calendarEventID.isEmpty else { return true }
        guard let event = calendarManager.event(for: note) else { return false }
        // [[T-8161]] rule (5): a read-only calendar refuses the write, and that is not a failure
        // the user can act on — the note is theirs and is already saved.
        guard CadenceEventNoteSupport.canMirrorNotes(to: event) else { return true }
        // [[T-8161]] rule (2): the flattened copy, minus image references.
        return calendarManager.updateEventNotes(
            event,
            notes: CadenceEventNotesMerge.mirrorText(noteContent: content)
        ) == nil
    }

    static func eventDateMetadata(from event: EKEvent) -> (dateKey: String, startMin: Int, endMin: Int) {
        CadenceEventNoteSupport.eventDateMetadata(from: event)
    }

    static func backfillMetadataIfPossible(_ note: Note, calendarManager: CalendarManager) {
        guard note.kind == .meeting else { return }
        guard let event = calendarManager.event(for: note) else { return }
        let metadata = eventDateMetadata(from: event)
        updateMetadata(
            note,
            calendarID: CalendarEventIdentity.calendarIdentifier(of: event),
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
/// **[[T-8161]] — one commit for an event note on the Mac, whichever editor it was typed in**, and
/// the twin of `iOSEventNoteCommit`.
///
/// `EventNoteEditorSheet` and the timeline's event popover both edit the same `Note` and both have
/// to obey the same three rules: save locally first and mirror only if that landed (T-325), give
/// Apple Calendar the **flattened** copy (rule 2), and skip the mirror entirely on a read-only
/// calendar (rule 5). Rule (1) — mirror only when the note actually changed — is the host's,
/// because only the host knows what it opened with.
@MainActor
enum MacEventNoteCommit {
    static func commitEventNote(
        _ note: Note,
        content: String,
        nativeEvent: EKEvent?,
        syncToCalendar: Bool,
        in modelContext: ModelContext,
        calendarManager: CalendarManager
    ) -> CadenceEventNoteCommitOutcome {
        CadenceEventNoteSupport.commitNote(
            syncToCalendar: syncToCalendar,
            save: { try modelContext.save() },
            syncToNativeEvent: {
                syncNoteToNativeEvent(note, content: content, event: nativeEvent, calendarManager: calendarManager)
            }
        )
    }

    /// Whether Apple Calendar now holds this text. The timeline hands its hosts the live `EKEvent`
    /// it is already rendering, which skips a lookup that a churned identifier could fail.
    static func syncNoteToNativeEvent(
        _ note: Note,
        content: String,
        event: EKEvent?,
        calendarManager: CalendarManager
    ) -> Bool {
        if let event, CadenceEventNoteSupport.matches(event, identifier: note.calendarEventID) {
            guard CadenceEventNoteSupport.canMirrorNotes(to: event) else { return true }
            return calendarManager.updateEventNotes(
                event,
                notes: CadenceEventNotesMerge.mirrorText(noteContent: content)
            ) == nil
        }
        return EventNoteSupport.syncNativeCalendarNotes(for: note, content: content, calendarManager: calendarManager)
    }
}
#endif
