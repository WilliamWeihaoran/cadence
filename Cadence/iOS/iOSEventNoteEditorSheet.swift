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
    /// The well's held-back typing, flushed before Done saves the note ([[T-5170]]).
    @State private var editorFlush = iOSMarkdownEditorFlush()
    @State private var commitNotice: String?
    /// The content Apple Calendar last took, or the note as this sheet opened it. [[T-8161]] rule
    /// (1): Done and a swipe-dismiss both commit, and without this they mirror an untouched note
    /// over an edit made in Apple Calendar since it was written.
    @State private var mirroredContent: String?
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
                        // [[T-5170]]: first, so the save and the Apple Calendar mirror carry
                        // the words typed just before the tap.
                        editorFlush.flush()
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

                // [[T-5805]]: and the same export control. A note can always be written out, and
                // the Mac's event sheet offers Export for this same note. The flush rides in so
                // the file carries the words typed just before the tap, as Done's save does.
                ToolbarItem(placement: .primaryAction) {
                    iOSNoteExportMenu(note: note, flush: editorFlush)
                }
            }
            .onAppear {
                refreshEventMetadata()
                if mirroredContent == nil { mirroredContent = note.content }
                persistNote(syncToCalendar: false)
            }
            .onChange(of: note.content) { _, _ in
                persistNote()
            }
            // [[T-5190]]: a swipe skips Done, so the well's held tail is written here.
            .onDisappear(perform: persistTypedTailOnDismissal)
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
            placeholder: "Start writing…",
            referenceNotes: allNotes,
            referenceTasks: allTasks,
            editingNote: note,
            onOpenReference: openMarkdownReference,
            flush: editorFlush
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
        guard let event, CadenceEventNoteSupport.matches(event, identifier: note.calendarEventID) else { return }
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
    ///
    /// [[T-5804]]: the commit itself is `iOSEventNoteCommit`'s now, shared with the iPad's Events
    /// pane in `iOSNotesView`, which used to save the same note without ever mirroring it.
    @discardableResult
    private func persistNote(syncToCalendar: Bool = true) -> CadenceEventNoteCommitOutcome {
        // [[T-8161]] rule (1). Done, and the swipe's tail write, commit whether or not anything was
        // typed; mirroring on those pushed the note as it was *loaded* over whatever Apple Calendar
        // holds now. The gate closes only while the note still matches what was last mirrored.
        let mirrors = syncToCalendar
            && CadenceEventNotesMerge.shouldMirror(content: note.content, lastMirrored: mirroredContent ?? "")
        let outcome = iOSEventNoteCommit.commitEventNote(
            note,
            event: event,
            syncToCalendar: mirrors,
            in: modelContext,
            calendarManager: calendarManager
        )
        if outcome == .saved {
            mirroredContent = note.content
        }
        commitNotice = outcome.notice
        return outcome
    }

    /// **[[T-5190]] — the swipe's half of [[T-5170]].** A swipe-dismiss never reaches Done, so the
    /// well's last 2.5 s of typing arrives — if at all — from the surface's own `onDisappear`, after
    /// this sheet has stopped answering `.onChange(of: note.content)`: the tail rode autosave and
    /// never reached Apple Calendar. Flush the held write first, then commit and mirror whatever the
    /// context still holds. Nothing pending (Done already saved, or nothing was typed), nothing
    /// written — a dismissal is not an EventKit write.
    private func persistTypedTailOnDismissal() {
        editorFlush.flush()
        guard modelContext.hasChanges else { return }
        persistNote()
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

/// **[[T-5804]] — one commit for an event note, whichever iOS editor it was typed in.**
///
/// It was `iOSEventNoteEditorSheet`'s private `persistNote` / `syncNoteToNativeEvent`, so only the
/// sheet mirrored a note into Apple Calendar: on iPad the Events tab edits the same note in
/// `iOSNotesView.editorPane`, whose setter was the bare `CadenceCoreNoteSupport.update` save. Both
/// now commit here, through `CadenceEventNoteSupport.commitNote`'s ordering — the local save first,
/// the mirror only if it landed — the same shape macOS's three event-note editors use.
@MainActor
enum iOSEventNoteCommit {
    /// `event` is the one the host already resolved, if any; `nil` resolves it from the note's
    /// stored identifier.
    static func commitEventNote(
        _ note: Note,
        event: EKEvent?,
        syncToCalendar: Bool = true,
        in modelContext: ModelContext,
        calendarManager: iOSCalendarManager
    ) -> CadenceEventNoteCommitOutcome {
        note.updatedAt = Date()
        return CadenceEventNoteSupport.commitNote(
            syncToCalendar: syncToCalendar,
            save: { try modelContext.save() },
            syncToNativeEvent: {
                syncNoteToNativeEvent(note, event: event, calendarManager: calendarManager)
            }
        )
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
    static func syncNoteToNativeEvent(_ note: Note, event: EKEvent?, calendarManager: iOSCalendarManager) -> Bool {
        // [[T-8161]] rule (2): Apple Calendar is given the markdown source minus its image
        // references. The pictures are `MarkdownImageAsset` rows that only Cadence can resolve;
        // `[[note]]` and `[[task:…]]` spans go across as written.
        let mirrored = CadenceEventNotesMerge.mirrorText(noteContent: note.content)
        if let event, CadenceEventNoteSupport.matches(event, identifier: note.calendarEventID) {
            guard CadenceEventNoteSupport.canMirrorNotes(to: event) else { return true }
            return calendarManager.updateEventNotes(event, notes: mirrored) == nil
        }
        if !note.calendarEventID.isEmpty {
            guard let resolved = calendarManager.event(for: note) else { return false }
            guard CadenceEventNoteSupport.canMirrorNotes(to: resolved) else { return true }
            return calendarManager.updateEventNotes(resolved, notes: mirrored) == nil
        }
        return true
    }
}
#endif
