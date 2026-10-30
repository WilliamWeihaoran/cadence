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

/// Edits an existing Apple Calendar event through **the one shared schedule panel** ([[T-3171]]).
///
/// The form itself is `CadenceSchedulePanel`, the same view the iPad timeline creates with — so
/// editing an event and creating one are the same screen, differing by `CadenceScheduleDraft`'s
/// subject and by the Delete control. This file is what cannot be shared: the `EKEvent`, the
/// manager's writes, the recurrence-scope question, the delete confirmation, and the one Notes
/// field — the rich Cadence event note, which mirrors a flattened copy into `EKEvent.notes`
/// ([[T-8161]]); there is no separate "Apple Calendar note" well any more.
///
/// **What it gained by adopting the panel**: a separate end DATE, so a timed event can be moved
/// across a midnight and an all-day one given any number of days (the old Days list stopped at
/// 30); an End time instead of a Duration; and a Location row, written back through
/// `iOSCalendarManager.updateEvent(location:)`. **Repeat** ([[T-3171]] (ii)) is offered whenever
/// the event's own rules are ones Cadence can spell (`CadenceEventRepeatSetting`), opened on what
/// the event does; a changed answer is saved for this and future events only, and the scope
/// question drops "Only This Event" for it, as Apple Calendar does.
struct iOSCalendarEventEditSheet: View {
    let event: EKEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var cardHeight: CGFloat = 520
    @State private var draft: CadenceScheduleDraft
    @State private var notesEditorFocused = false
    /// The Notes well's held-back typing, flushed before Save reads `draft` ([[T-5170]]).
    @State private var notesFlush = iOSMarkdownEditorFlush()
    /// The Apple Calendar note as this sheet last read it from EventKit — what an untouched
    /// `draft.notes` still equals ([[T-5171]]).
    @State private var loadedEventNotes: String
    @State private var presentedEventNote: Note?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    /// The scope the delete confirmation names, while it is up. A series member reaches it only
    /// through the scope dialog ([[T-7075]]); see `CadenceEventDeleteStep`.
    @State private var deleteConfirmationScope: CalendarRecurrenceEditScope?
    @State private var actionError: String?
    /// What the Notes field's last commit could not do, drawn under the field itself.
    @State private var noteCommitNotice: String?
    /// The note's content as Apple Calendar last took it — `nil` until the sheet appears. Rule (1)
    /// of [[T-8161]]: the mirror fires only when the Cadence note has moved away from this.
    @State private var mirroredNoteContent: String?
    @State private var pendingAction: PendingAction?

    /// The draft as the sheet opened it. A save whose schedule still matches it writes the event's
    /// own instants back — see `CadenceScheduleDraft.hasSameSchedule(as:)`.
    private let openedDraft: CadenceScheduleDraft

    private enum PendingAction {
        case save
        case delete
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
            title: draft.title,
            isEventEditable: isEditable,
            selectedCalendarID: draft.calendarID,
            writableCalendarIDs: writableCalendarIDs
        )
    }

    /// Whether the panel draws Repeat: only over rules it can read back — see
    /// `CadenceEventRepeatSetting(rules:…)`.
    private var offersRepeat: Bool {
        CadenceEventRepeatSetting(event: event) != nil
    }

    /// A Save that re-rules the series asks only "this and future" — see
    /// `CadenceEventCreationSupport.editSpan`.
    private var savesRecurrenceChange: Bool {
        pendingAction == .save && draft.changesRecurrence(from: openedDraft)
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

    /// The event's title as the store holds it -- never `draft.title`, which is what the user may be
    /// halfway through retyping ([[T-8571]]). The note's lookup, the note a first keystroke mints
    /// and the full editor's eyebrow all read this, as macOS's popover reads `item.title`: the draft
    /// title minted a note under an unsaved (or then cancelled) name, and its title fallback could
    /// miss the note the lookup had found and create a second one beside it.
    private var savedEventTitle: String {
        iOSCalendarEventSupport.title(for: event)
    }

    private var linkedEventNote: Note? {
        CadenceEventNoteSupport.note(
            for: eventNoteID,
            eventTitle: savedEventTitle,
            calendarID: event.calendar?.calendarIdentifier ?? draft.calendarID,
            eventDateKey: eventMetadata.dateKey,
            eventStartMin: eventMetadata.startMin,
            eventEndMin: eventMetadata.endMin,
            in: allNotes
        )
    }

    init(event: EKEvent) {
        self.event = event
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start.addingTimeInterval(30 * 60)
        var opened = CadenceScheduleDraft(
            editingEventID: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: iOSCalendarEventSupport.title(for: event),
            notes: event.notes ?? "",
            location: event.location ?? "",
            calendarID: event.calendar?.calendarIdentifier ?? "",
            start: start,
            end: end,
            isAllDay: event.isAllDay
        )
        CadenceEventRepeatSetting(event: event)?.seed(&opened)
        self.openedDraft = opened
        _draft = State(initialValue: opened)
        _loadedEventNotes = State(initialValue: opened.notes)
    }

    var body: some View {
        ScrollView {
            CadenceSchedulePanel(
                draft: $draft,
                calendarChoices: calendarChoices,
                calendarUnavailableNotice: calendarUnavailableNotice,
                readOnlyNotice: isEditable
                    ? nil
                    : CadenceCalendarEventEditingSupport.readOnlyNotice(calendarName: eventCalendarName),
                // T-497: every failure this sheet reports — a refused EventKit save, a refused
                // delete, a refused event-note commit — is drawn by the panel, in one place,
                // whatever the width. Most of them arrive after a confirmation dialog rather
                // than as the panel's own call returning, which is why this is a parameter.
                failureNotice: actionError,
                canCommit: canSave,
                offersEventRepeat: offersRepeat,
                actions: panelActions
            ) {
                notesSection
            }
            .capturePresentation(CadenceScheduleCaptureOptions())
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 + 24 }
            .frame(maxWidth: 540)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .cadenceScaledTypography()
        .scrollDismissesKeyboard(.never)
        .scrollIndicators(.hidden)
        // [[T-7070]]: the Mac's words, from the one owner its three delete sites read.
        // [[T-7075]]: a series member's scope was asked before this, so the sentence names the
        // scope chosen — "and future events" when the delete reaches past this occurrence.
        .confirmationDialog(
            CadenceCalendarEventEditingSupport.deleteConfirmationTitle,
            isPresented: Binding(
                get: { deleteConfirmationScope != nil },
                set: { if !$0 { deleteConfirmationScope = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteConfirmationScope
        ) { scope in
            Button(CadenceCalendarEventEditingSupport.deleteConfirmationLabel, role: .destructive) {
                applyDelete(scope: scope)
            }
            Button("Cancel", role: .cancel) {}
        } message: { scope in
            Text(
                CadenceCalendarEventEditingSupport.deleteConfirmationMessage(
                    eventTitle: iOSCalendarEventSupport.title(for: event),
                    scope: scope
                )
            )
        }
        .confirmationDialog(
            CadenceRecurrenceScopeCopy.eventScopeTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if !savesRecurrenceChange {
                Button(CalendarRecurrenceEditScope.thisOccurrence.label) {
                    applyPendingAction(scope: .thisOccurrence)
                }
            }
            Button(CalendarRecurrenceEditScope.futureOccurrences.label) {
                applyPendingAction(scope: .futureOccurrences)
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(
                savesRecurrenceChange
                    ? CadenceRecurrenceScopeCopy.eventRepeatScopeMessage
                    : CadenceRecurrenceScopeCopy.eventScopeMessage
            )
        }
        .onAppear(perform: ensureWritableCalendar)
        .onAppear(perform: loadMirrorBaseline)
        .onChange(of: calendarManager.storeVersion) { _, _ in
            reloadEventNotesIfUntouched()
        }
        .sheet(item: $presentedEventNote) { note in
            iOSHeldNoteSheet(note: note) { presentedEventNote = nil } content: { note in
                iOSEventNoteEditorSheet(note: note, eventTitle: savedEventTitle, event: event)
            }
            .cadenceFixedTypography()
        }
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.height(cardHeight)])
        // `hasPendingEdit`: notes typed in the well's last 2.5 s are not committed yet ([[T-5170]]).
        // [[T-8572]]: committed notes are not an unsaved edit, so the guard ignores `draft.notes`.
        .interactiveDismissDisabled(
            CadenceEventEditDismissGuard.blocksSwipe(
                opened: openedDraft,
                current: draft,
                notesHavePendingEdit: notesFlush.hasPendingEdit
            )
        )
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
        .preferredColorScheme(.dark)
    }

    /// Save, Cancel and — on an event that can be written — Delete. The panel draws them; a
    /// recurring event's save and every delete stop at a confirmation here before anything is
    /// written, so their outcome is reported through `actionError` rather than returned.
    private var panelActions: CadenceSchedulePanelActions {
        var actions = CadenceSchedulePanelActions(commit: save, cancel: { dismiss() })
        // Absent, not disabled, on a read-only event: EventKit refuses the removal, so a Delete
        // there raised a confirmation dialog for a delete that could never happen.
        if isEditable {
            actions.delete = {
                beginDelete()
                return nil
            }
        }
        return actions
    }

    /// The writable calendars, or — on a read-only event — the event's real calendar alone, stated
    /// plainly. A picker there could only offer calendars this event cannot move to, and the panel
    /// draws it inert.
    private var calendarChoices: [CadenceSchedulePanelChoice] {
        guard isEditable else {
            return [
                CadenceSchedulePanelChoice(
                    id: draft.calendarID,
                    name: CadenceTitleNormalization.display(eventCalendarName, fallback: CadenceAppleCalendarNaming.unnamedCalendarTitle),
                    color: Theme.dim
                )
            ]
        }
        return calendarManager.writableCalendars.map {
            CadenceSchedulePanelChoice(
                id: $0.calendarIdentifier,
                name: $0.title,
                color: iOSCalendarEventSupport.color(for: $0),
                systemImage: "calendar"
            )
        }
    }

    private var calendarUnavailableNotice: String? {
        guard isEditable, calendarManager.writableCalendars.isEmpty else { return nil }
        return "No writable calendars are available."
    }

    /// **[[T-8161]] — the one Notes field.** It replaced two: the "Event Note" Create/Open card
    /// and the "Apple Calendar note" markdown well that bound straight to `EKEvent.notes`. The
    /// field is the rich Cadence `Note`; Apple Calendar gets a flattened copy of it
    /// (`CadenceEventNotesMerge`), and images stay Cadence-only because only the *mirror* drops
    /// them — the text they sit in is a `Note` row, which is what `CadenceMarkdownSourceInventory`
    /// reads, so [[T-422]]'s `allowsImageInsertion: false` is retired here rather than extended.
    ///
    /// Not `.disabled(!isEditable)` any more, which is rule (5): a read-only calendar refuses the
    /// *mirror*, not the note, and the field says which of the two in one quiet line.
    private var notesSection: some View {
        CadenceEventNotesField(
            mirrorsToCalendar: isEditable,
            failureNotice: noteCommitNotice,
            onOpenFullEditor: openEventNote
        ) {
            iOSMarkdownEditingSurface(
                text: notesBinding,
                isFocused: $notesEditorFocused,
                placeholder: "Add notes\u{2026}",
                // Not the event's own note ([[T-8751]], the T-8582 rule): the field IS that note.
                // Filtered here rather than passed as `editingNote:`, which would also draw the
                // full editor's reference panel and navigation in this field; `openMarkdownReference`
                // still resolves against every note.
                referenceNotes: MarkdownReferenceCompletionSupport.linkableNotes(allNotes, excludingNoteID: linkedEventNote?.id),
                referenceTasks: allTasks,
                onOpenReference: openMarkdownReference,
                allowsEmbeddedTaskCreation: false,
                flush: notesFlush
            )
            .iOSMarkdownWell()
        }
    }

    /// What the field shows, and what typing in it does.
    ///
    /// `get` is `CadenceEventNotesMerge.displayText`: the event's own `EKEvent.notes` when no
    /// Cadence note exists yet (rule 4), and otherwise the note with any Apple Calendar text it
    /// does not already carry appended under a divider (rule 6). `set` seeds the note on the first
    /// edit — `initialContent(eventTitle:nativeNotes:)` gives it the native text — and then writes
    /// what the user is looking at, which is why the merged text persists the moment it is touched
    /// and is never silently dropped.
    private var notesBinding: Binding<String> {
        Binding(
            get: {
                CadenceEventNotesMerge.displayText(
                    noteContent: linkedEventNote?.content,
                    nativeNotes: event.notes
                )
            },
            set: { applyNotesEdit($0) }
        )
    }

    /// The text Save writes into `EKEvent.notes`.
    ///
    /// **Rule (1), on the path that is easiest to miss.** Save has always written `draft.notes`
    /// back, and that draft is `EKEvent.notes` as the sheet *opened* it — so a Save with the notes
    /// untouched re-wrote an edit made in Apple Calendar since. The mirror is now the note's
    /// flattened copy and only when that note changed; otherwise the event keeps the notes it
    /// already has.
    private var savedEventNotes: String {
        guard isEditable,
              let note = linkedEventNote,
              CadenceEventNotesMerge.shouldMirror(content: note.content, lastMirrored: mirroredNoteContent ?? "")
        else { return event.notes ?? "" }
        return CadenceEventNotesMerge.mirrorText(noteContent: note.content)
    }

    /// Writes an edit made in the Notes field, creating the note on the first one.
    ///
    /// The guard is what keeps an untouched sheet from minting a `Note`: the editing surface
    /// writes its binding back as it loads and as it normalises, and only text that differs from
    /// what the field was showing is an edit.
    private func applyNotesEdit(_ newValue: String) {
        guard CadenceEventNotesMerge.isEdit(
            newValue,
            noteContent: linkedEventNote?.content,
            nativeNotes: event.notes
        ) else { return }
        guard let note = ensureEventNote() else { return }
        // Through `applyContent`, never a bare `note.content =`: the body of a note is also where
        // its title and its inline `#tags` come from, and iOS has no surface that writes one
        // without the other (`CadenceNoteTitleSyncSurfaceTests`). The save is deliberately left
        // out of it — [[T-5804]]'s split — because an event note's save belongs to `commitNote`,
        // which orders it before the Apple Calendar mirror.
        CadenceCoreNoteSupport.applyContent(note, content: newValue, in: modelContext)
        commitNotes(note)
    }

    /// Commits the note, and mirrors a flattened copy only when rule (1) allows it.
    ///
    /// `mirroredNoteContent` is the note as this sheet opened it, advanced **only** on a mirror
    /// Apple Calendar accepted — so a refused mirror is retried on the next keystroke rather than
    /// being recorded as done.
    private func commitNotes(_ note: Note) {
        let mirrors = isEditable
            && CadenceEventNotesMerge.shouldMirror(content: note.content, lastMirrored: mirroredNoteContent ?? "")
        let outcome = iOSEventNoteCommit.commitEventNote(
            note,
            event: event,
            syncToCalendar: mirrors,
            in: modelContext,
            calendarManager: calendarManager
        )
        if outcome == .saved {
            mirroredNoteContent = note.content
        }
        noteCommitNotice = outcome.notice
    }

    /// The baseline rule (1) compares against: the note as the sheet opened it. Read once, on
    /// appear, because every later read would be the content the user has just typed — which would
    /// make the gate unconditionally closed.
    private func loadMirrorBaseline() {
        guard mirroredNoteContent == nil else { return }
        mirroredNoteContent = linkedEventNote?.content ?? ""
    }

    /// T-497, the existence half of the `try? save()` rule — and the sharpest instance of it,
    /// because **opening the editor is itself the report of success**. This inserted a note,
    /// swallowed the save and presented the note anyway, so on a refused commit the user landed in
    /// an editor over a row the store never took.
    ///
    /// `noteForEditing` either returns an existing note or creates one, and only the second case
    /// has anything to un-insert — which is why the insert closure records what it inserted rather
    /// than assuming. When it inserted nothing the commit is a plain flush of the metadata
    /// reconciliation `noteForEditing` performs on the existing note; that is an in-place field
    /// edit the next open recomputes, so it needs no undo, but its failure still stops the sheet
    /// from opening on it.
    private func openEventNote() {
        guard let note = ensureEventNote() else { return }
        presentedEventNote = note
    }

    /// The note this event's Notes field edits, created and committed if it does not exist yet.
    private func ensureEventNote() -> Note? {
        var inserted: [any PersistentModel] = []
        guard let note = CadenceEventNoteSupport.noteForEditing(
            calendarEventID: eventNoteID,
            eventTitle: savedEventTitle,
            calendarID: event.calendar?.calendarIdentifier ?? draft.calendarID,
            eventDateKey: eventMetadata.dateKey,
            eventStartMin: eventMetadata.startMin,
            eventEndMin: eventMetadata.endMin,
            nativeNotes: event.notes,
            notes: allNotes,
            insert: {
                modelContext.insert($0)
                inserted.append($0)
            }
        ) else { return nil }

        // **[[T-8161]] rule (6), and the only place this change could lose the owner's data.** A
        // note that predates the merge can hold one thing while `EKEvent.notes` holds another; the
        // field *shows* both, but the stored note does not carry the Apple half until something
        // writes it. So it is written here — the moment the note is handed to an editor or to a
        // keystroke, and before any mirror can run — because the full note editor does not merge
        // and its next commit would otherwise push the Cadence half over the Apple one.
        if let merged = CadenceEventNotesMerge.mergedContent(noteContent: note.content, nativeNotes: event.notes) {
            CadenceCoreNoteSupport.applyContent(note, content: merged, in: modelContext)
        }

        do {
            try CadencePendingChangePersistence.commitInsert(of: inserted, in: modelContext)
        } catch {
            noteCommitNotice = CadencePendingChangePersistence.editFailureNotice
            return nil
        }
        noteCommitNotice = nil
        return note
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }

    /// The panel's commit. `nil` always: a recurring event stops at the scope question, and every
    /// outcome — this one's included — is reported through `actionError`, which the panel draws.
    private func save() -> String? {
        // [[T-5170]]: first, so `draft.notes` holds the words typed just before the tap.
        notesFlush.flush()
        if isRecurringEvent {
            pendingAction = .save
            return nil
        }
        applySave(scope: .thisOccurrence)
        return nil
    }

    /// **[[T-5171]].** Every `EKEventStoreChanged` bumps `storeVersion` — a sync, an edit in Apple
    /// Calendar, any other event — and this used to copy `event.notes` over `draft.notes` on each,
    /// throwing away the note being typed. It still picks up a note written elsewhere (the event
    /// note mirror), but only into a draft the user has not edited since the last read.
    private func reloadEventNotesIfUntouched() {
        notesFlush.flush()
        guard let reloaded = iOSCalendarEventNoteReload.reloadedNotes(
            draft: draft.notes,
            lastLoaded: loadedEventNotes,
            fresh: event.notes ?? ""
        ) else { return }
        loadedEventNotes = reloaded
        draft.notes = reloaded
    }

    /// **[[T-7075]].** Scope first for a series member, then the confirmation for that scope; a
    /// single event goes straight to the one confirmation. Nothing is written until it is confirmed.
    private func beginDelete() {
        switch CadenceEventDeleteStep.first(isRecurringSeriesMember: isRecurringEvent) {
        case .askScope:
            pendingAction = .delete
        case .confirm(let scope):
            deleteConfirmationScope = scope
        }
    }

    /// The scope dialog is still dismissing when its button runs, and a second dialog raised in
    /// that same pass can fail to appear. The confirmation is raised on the next main-queue turn,
    /// after the scope dialog's dismissal has been committed.
    private func confirmDelete(after scope: CalendarRecurrenceEditScope) {
        guard let confirmed = CadenceEventDeleteStep.afterScope(scope).confirmationScope else { return }
        DispatchQueue.main.async {
            deleteConfirmationScope = confirmed
        }
    }

    private func applyPendingAction(scope: CalendarRecurrenceEditScope) {
        guard let pendingAction else { return }
        self.pendingAction = nil
        switch pendingAction {
        case .save:
            applySave(scope: scope)
        case .delete:
            confirmDelete(after: scope)
        }
    }

    /// The instants to write. An untouched schedule writes the event's own back, exactly; a moved
    /// one is resolved through the draft's wall-clock rule (T-3119's gap policy included).
    private var savedRange: (start: Date, end: Date)? {
        if draft.hasSameSchedule(as: openedDraft),
           let start = event.startDate,
           let end = event.endDate,
           end > start {
            return (start, end)
        }
        return draft.eventDateRange()
    }

    private func applySave(scope: CalendarRecurrenceEditScope) {
        // A schedule that names no instant was never offered to EventKit, so there is no cause to
        // name — the same `nil` the create path passes for an unparseable day.
        guard let range = savedRange else {
            actionError = CadenceCalendarEventEditingSupport.saveFailureNotice(for: nil)
            return
        }
        let recurrence = CadenceEventRepeatSetting.edit(draft: draft, opened: openedDraft)
        if let failure = calendarManager.updateEvent(
            event,
            title: draft.title,
            startDate: range.start,
            endDate: range.end,
            calendarID: draft.calendarID,
            notes: savedEventNotes,
            span: CadenceEventCreationSupport.editSpan(for: scope, changesRecurrence: recurrence != nil),
            isAllDay: draft.isAllDay,
            location: draft.location,
            recurrence: recurrence
        ) {
            // A rejected write used to return here and do nothing at all: the sheet stayed open,
            // unchanged, with no indication that the save had failed. It then said *that* it had
            // failed but not why; since T-339 the manager hands back the cause macOS has always
            // shown in its alert.
            actionError = CadenceCalendarEventEditingSupport.saveFailureNotice(for: failure)
            return
        }
        actionError = nil
        dismiss()
    }

    private func applyDelete(scope: CalendarRecurrenceEditScope) {
        if let failure = calendarManager.deleteEvent(event, span: scope.eventSpan) {
            actionError = CadenceCalendarEventEditingSupport.deleteFailureNotice(for: failure)
        } else {
            dismiss()
        }
    }

    /// Keeps a writable event pointed at a calendar the picker actually lists — and leaves a
    /// read-only event on its own calendar, which is the one thing this used to get wrong: it
    /// substituted the first writable calendar, so a Birthdays event's Calendar row read
    /// "Personal" and the sheet then offered to save it there.
    private func ensureWritableCalendar() {
        draft.calendarID = CadenceCalendarEventEditingSupport.resolvedCalendarID(
            eventCalendarID: draft.calendarID,
            isEventEditable: isEditable,
            writableCalendarIDs: writableCalendarIDs
        )
    }
}

/// **[[T-5171]]** — whether a store change may replace the event sheet's draft Apple Calendar note.
/// `nil` keeps the draft: it differs from what the sheet last read, so it holds the user's edit.
enum iOSCalendarEventNoteReload {
    static func reloadedNotes(draft: String, lastLoaded: String, fresh: String) -> String? {
        guard draft == lastLoaded else { return nil }
        return fresh
    }
}

#endif
