#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSEventNoteEditorSheet: View {
    @Bindable var note: Note
    let eventTitle: String
    let event: EKEvent?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var isEditorFocused = false
    @State private var commitNotice: String?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    private var title: String {
        note.displayTitle
    }

    private var subtitle: String {
        let trimmed = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Linked event note" : trimmed
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            editorLayout
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Event Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        // T-325: Done used to dismiss over a `try?` save. A sheet that closes on
                        // a failed commit takes the user's writing with it, so an unsaved note
                        // keeps the editor open with the notice showing instead. A note that is
                        // saved but not mirrored into Apple Calendar still closes — the text is
                        // safe, and a read-only event can never accept it however long we wait.
                        guard persistNote().isSaved else { return }
                        isEditorFocused = false
                        dismiss()
                    }
                }

                // An event note is a note, so it gets the same AI actions control the other three
                // kinds get — `iOSNoteEditorCover` puts it in the same slot. Absent without an API
                // key.
                ToolbarItem(placement: .primaryAction) {
                    iOSNoteAIActionsMenu(note: note, area: note.area, project: note.project)
                }
            }
            .onAppear {
                refreshEventMetadata()
                persistNote(syncToCalendar: false)
            }
            .onChange(of: note.content) { _, _ in
                persistNote()
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
    private var editorLayout: some View {
        if isRegularWidth {
            regularEditorLayout
        } else {
            compactEditorLayout
        }
    }

    private var compactEditorLayout: some View {
        VStack(spacing: 0) {
            header

            Divider().background(Theme.borderSubtle)

            editorSurface
        }
    }

    private var regularEditorLayout: some View {
        HStack(spacing: 0) {
            header
                .frame(width: 320, alignment: .topLeading)

            Divider().background(Theme.borderSubtle)

            editorSurface
        }
    }

    private var editorSurface: some View {
        iOSMarkdownEditingSurface(
            text: $note.content,
            isFocused: $isEditorFocused,
            placeholder: "Start writing...",
            referenceNotes: allNotes,
            referenceTasks: allTasks,
            editingNote: note,
            onOpenReference: openMarkdownReference
        )
    }

    // The same header `iOSLinkedNoteEditorSheet` draws, and now literally the same view rather than
    // a second copy of it (T-281). The eyebrow, the title ramp and the block's padding live on
    // `iOSNoteEditorSheetHeader`; the commit notice is this sheet's own and rides in as the
    // accessory.
    private var header: some View {
        iOSNoteEditorSheetHeader(eyebrow: subtitle, title: title) {
            commitNoticeBanner
        }
    }

    /// Says which of the note's two writes did not happen, in the one place on this sheet where
    /// the user is looking. Absent while both are landing, which is nearly always.
    ///
    /// Deliberately the plain-surface failure-line spelling (12pt medium, `Theme.red`) rather than
    /// the 13pt semibold one `iOSCalendarEventEditSheet` uses inside an `iOSEditorSection`, so
    /// this is one swap away from the shared notice component when it lands.
    @ViewBuilder
    private var commitNoticeBanner: some View {
        if let commitNotice {
            Text(commitNotice)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refreshEventMetadata() {
        guard let event else { return }
        let metadata = CadenceEventNoteSupport.eventDateMetadata(from: event)
        CadenceEventNoteSupport.updateMetadata(
            note,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin
        )
    }

    /// **T-325.** This was `try? modelContext.save()` followed unconditionally by a push into the
    /// native event. Apple Calendar is outside Cadence and cannot be rolled back from inside it,
    /// so a local commit that never landed must not be mirrored there: the ordering, and the fact
    /// that the sync is only reachable through it, belong to
    /// `CadenceEventNoteSupport.commitNote(syncToCalendar:save:syncToNativeEvent:)`.
    @discardableResult
    private func persistNote(syncToCalendar: Bool = true) -> CadenceEventNoteCommitOutcome {
        note.updatedAt = Date()
        let outcome = CadenceEventNoteSupport.commitNote(
            syncToCalendar: syncToCalendar,
            save: { try modelContext.save() },
            syncToNativeEvent: syncNoteToNativeEvent
        )
        commitNotice = outcome.notice
        return outcome
    }

    /// Whether Apple Calendar now holds this note's text. A note with no native event to mirror
    /// into has nothing that can fail, so it is not a sync failure.
    ///
    /// The writes answer `CalendarWriteFailure?` since T-339, and this narrows that back to the
    /// `Bool` `commitNote` wants — deliberately, and in the same place macOS's
    /// `EventNoteSupport.syncNativeCalendarNotes` does it. `CadenceEventNoteCommitOutcome` is
    /// about what happened to the *note*: whether the local save landed, and whether the mirror
    /// did. Which EventKit rejection it was does not change either of those, and this editor's
    /// banner is a debounced flush that fires while someone types.
    private func syncNoteToNativeEvent() -> Bool {
        if let event {
            return calendarManager.updateEventNotes(event, notes: note.content) == nil
        }
        if !note.calendarEventID.isEmpty {
            return calendarManager.updateEventNotes(calendarEventID: note.calendarEventID, notes: note.content) == nil
        }
        return true
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }
}
#endif
