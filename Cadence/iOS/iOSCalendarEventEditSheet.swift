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
/// manager's writes, the recurrence-scope question, the delete confirmation, the Cadence event note
/// and the platform's markdown well for the Apple Calendar note.
///
/// **What it gained by adopting the panel**: a separate end DATE, so a timed event can be moved
/// across a midnight and an all-day one given any number of days (the old Days list stopped at
/// 30); an End time instead of a Duration; and a Location row, written back through
/// `iOSCalendarManager.updateEvent(location:)`. **What it deliberately does not offer** is Repeat:
/// an existing series is not re-ruled from here, so the panel is told `offersEventRepeat: false`
/// rather than shown a row whose choice would be dropped.
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
    @State private var presentedEventNote: Note?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @State private var confirmDelete = false
    @State private var actionError: String?
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
        let opened = CadenceScheduleDraft(
            editingEventID: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: iOSCalendarEventSupport.title(for: event),
            notes: event.notes ?? "",
            location: event.location ?? "",
            calendarID: event.calendar?.calendarIdentifier ?? "",
            start: start,
            end: end,
            isAllDay: event.isAllDay
        )
        self.openedDraft = opened
        _draft = State(initialValue: opened)
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
                offersEventRepeat: false,
                actions: panelActions
            ) {
                eventNoteSection
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
        .confirmationDialog("Delete Event?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Event", role: .destructive) {
                requestDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the event from Apple Calendar.")
        }
        .confirmationDialog(
            CadenceRecurrenceScopeCopy.eventScopeTitle,
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
            Text(CadenceRecurrenceScopeCopy.eventScopeMessage)
        }
        .onAppear(perform: ensureWritableCalendar)
        .onChange(of: calendarManager.storeVersion) { _, _ in
            draft.notes = event.notes ?? ""
        }
        .sheet(item: $presentedEventNote) { note in
            iOSEventNoteEditorSheet(note: note, eventTitle: draft.title, event: event)
                .cadenceFixedTypography()
        }
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.height(cardHeight)])
        .interactiveDismissDisabled(draft != openedDraft)
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
                confirmDelete = true
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
                    name: CadenceTitleNormalization.display(eventCalendarName, fallback: "Unknown calendar"),
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

    private var eventNoteSection: some View {
        iOSEditorSection(title: "Event Note", style: .ruled) {
            HStack(alignment: .center, spacing: 12) {
                // 34/15, the tile size the app's other editor rows draw.
                iOSIconTile(systemImage: "doc.text", color: Theme.purple, size: 34, iconSize: 15)

                VStack(alignment: .leading, spacing: 3) {
                    Text(linkedEventNote?.displayTitle ?? "No linked note yet")
                        .cadenceFont(.rowTitle, base: 14, weight: .semibold)
                        .foregroundStyle(linkedEventNote == nil ? Theme.dim : Theme.text)
                        .lineLimit(1)
                    Text(linkedEventNote == nil ? "Create a markdown note for this event." : "Open the note linked to this event.")
                        .cadenceFont(.metadata, base: 12, weight: .regular)
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

    private var notesSection: some View {
        iOSEditorSection(title: "Notes", style: .ruled) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apple Calendar note")
                    .cadenceFont(.metadata, base: 12, weight: .semibold)
                    .foregroundStyle(Theme.subdued)

                iOSMarkdownEditingSurface(
                    text: $draft.notes,
                    isFocused: $notesEditorFocused,
                    placeholder: "Add markdown notes...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference,
                    allowsEmbeddedTaskCreation: false,
                    // **T-422.** This binding is `EKEvent.notes` in EventKit, not a row in the
                    // store, so an image pasted here would be referenced by nothing
                    // `CadenceMarkdownSourceInventory` can read and the next sweep would collect
                    // its `.externalStorage` bytes. Widening the inventory was never an option:
                    // EventKit has no unbounded "every event" query, so there is no way to ask the
                    // calendar store the question the sweep asks the model store.
                    allowsImageInsertion: false
                )
                .iOSMarkdownWell()
            }
        }
        // The Apple Calendar note is written back through EventKit on save, which a read-only
        // calendar refuses. The *Cadence* event note above stays editable — it is our own data,
        // which is why the panel leaves its notes slot to the host rather than disabling it.
        .disabled(!isEditable)
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
        var inserted: [any PersistentModel] = []
        guard let note = CadenceEventNoteSupport.noteForEditing(
            calendarEventID: eventNoteID,
            eventTitle: draft.title,
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
        ) else { return }

        do {
            try CadencePendingChangePersistence.commitInsert(of: inserted, in: modelContext)
        } catch {
            actionError = CadencePendingChangePersistence.editFailureNotice
            return
        }
        actionError = nil
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

    /// The panel's commit. `nil` always: a recurring event stops at the scope question, and every
    /// outcome — this one's included — is reported through `actionError`, which the panel draws.
    private func save() -> String? {
        if isRecurringEvent {
            pendingAction = .save
            return nil
        }
        applySave(scope: .thisOccurrence)
        return nil
    }

    private func requestDelete() {
        if isRecurringEvent {
            pendingAction = .delete
            return
        }
        applyDelete(scope: .thisOccurrence)
    }

    private func applyPendingAction(scope: CalendarRecurrenceEditScope) {
        guard let pendingAction else { return }
        self.pendingAction = nil
        switch pendingAction {
        case .save:
            applySave(scope: scope)
        case .delete:
            applyDelete(scope: scope)
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
        if let failure = calendarManager.updateEvent(
            event,
            title: draft.title,
            startDate: range.start,
            endDate: range.end,
            calendarID: draft.calendarID,
            notes: draft.notes,
            span: scope.eventSpan,
            isAllDay: draft.isAllDay,
            location: draft.location
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

#endif
