#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

// MARK: - Calendar Event Edit Popover

/// What one Save asks the host to write, worked out from the panel's draft ([[T-3171]]).
///
/// A value rather than five closure arguments because the popover is no longer the frame that knows
/// the instants: the **draft** is, through `CadenceScheduleDraft.savedEventRange(openedAs:…)`. The
/// two hosts still perform the write, see the typed `CalendarWriteFailure`, and decide whether to
/// close (T-658), which is why this is handed to them rather than written here.
///
/// Every field the user did not touch is `nil`, so an untouched Save writes nothing it did not
/// read: the event's own instants (not a wall-clock re-derivation that could move it by the
/// seconds, or the repeated fall-back hour, a minute cannot spell), and no notes, location or
/// all-day flag at all. The notes half matters more than it looks: on this platform a Cadence
/// event note mirrors itself into `EKEvent.notes`, and a Save that re-wrote the notes it opened
/// with would undo that mirror's later flush.
struct CalendarEventEditRequest {
    let title: String
    /// `nil` when no range can be formed. EventKit was never asked, so the host names no cause.
    let range: (start: Date, end: Date)?
    let calendarID: String
    let notes: String?
    let location: String?
    let isAllDay: Bool?
    /// The series' new Repeat answer, or `nil` to leave the event's rules alone ([[T-3171]] (ii)).
    /// Non-`nil` only when the Repeat or Ends row moved; the host's write then saves
    /// `.futureEvents` whatever scope was answered — see `CadenceEventCreationSupport.editSpan`.
    let recurrence: CadenceEventRepeatSetting?

    init(
        draft: CadenceScheduleDraft,
        opened: CadenceScheduleDraft,
        originalStart: Date?,
        originalEnd: Date?,
        calendar: Calendar = .current
    ) {
        title = draft.title
        range = draft.savedEventRange(
            openedAs: opened,
            originalStart: originalStart,
            originalEnd: originalEnd,
            calendar: calendar
        )
        calendarID = draft.calendarID
        notes = draft.notes == opened.notes ? nil : draft.notes
        location = draft.location == opened.location ? nil : draft.location
        isAllDay = draft.isAllDay == opened.isAllDay ? nil : draft.isAllDay
        recurrence = CadenceEventRepeatSetting.edit(draft: draft, opened: opened)
    }
}

/// Edits an existing Apple Calendar event on the Mac through **the one shared schedule panel**
/// ([[T-3171]], the fourth adoption slice) — the same view the iOS event editor, task editor and
/// quick-create sheet draw.
///
/// This file is what cannot be shared: the `EKEvent`, the recurrence-scope question, the Cadence
/// event note and its sheet, and the hand-off of each write to the host that owns the popover.
/// Since [[T-8161]] the note is the popover's **one Notes field** rather than a card offering to
/// open it beside a second field bound to `EKEvent.notes`.
///
/// **What it gained:** an All-day switch, a separate end DATE (so a timed event can be moved across
/// a midnight), a Location row, the Apple Calendar notes field, and **the whole event** rather than
/// the clicked day's segment of it — the old Start/End fields edited one day of a multi-day event,
/// and only that day's own end. Both ends are now set on the wall clock (T-3119's gap rule), where
/// the old fields added elapsed minutes to the segment's midnight. **Repeat** ([[T-3171]] (ii)) is
/// offered whenever the event's own rules are ones Cadence can spell (`CadenceEventRepeatSetting`),
/// opened on what the event does, and a changed answer is saved for this and future events only —
/// the scope question drops "Only This Event" for it, as Apple Calendar does. **Changed on purpose:** the clock is the shared roller, not two typed fields; Save greys
/// out on an empty title; and an event on a read-only calendar is read-only here — the panel draws
/// no Save and no Delete for one, where this popover used to offer both and let EventKit refuse.
struct CalendarEventEditPopover: View {
    let item: CalendarEventItem
    let onSave: (CalendarEventEditRequest, CalendarRecurrenceEditScope) -> Void
    let onDelete: (CalendarRecurrenceEditScope) -> Void
    /// What to say when the host's save was refused (T-658).
    ///
    /// A binding rather than local `@State`, for the reason `TaskBundleDetailPopover` records for
    /// its own: the host is the frame that performs the write, the frame that sees the typed
    /// `CalendarWriteFailure`, and the frame that decides *not* to close this popover — a notice
    /// this view set itself would be drawn for one frame and dismissed with it. The panel draws it
    /// (`failureNotice:`), because a recurring event's Save reaches the host only after the scope
    /// question, so its answer cannot come back through the panel's own commit.
    ///
    /// Save only. Delete leaves through `DeleteConfirmationManager`'s full-window overlay, which
    /// closes this popover on the way, so its refusal is reported by that overlay instead.
    @Binding var actionFailureNotice: String?
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    @State private var draft: CadenceScheduleDraft
    @State private var presentedEventNote: Note?
    @State private var pendingAction: PendingAction?
    @State private var noteFailureNotice: String?
    /// The note's content as Apple Calendar last took it — `nil` until the popover appears.
    /// [[T-8161]] rule (1): the mirror fires only when the Cadence note has moved away from this.
    @State private var mirroredNoteContent: String?
    /// The Notes field's buffer and its debounce, the shape `TaskDetailNotesSection` already uses
    /// ([[T-7810]]/[[T-7811]]). A `MarkdownEditor` writes its binding on **every keystroke**, and
    /// this field's write reaches two stores: a `ModelContext.save()` and an EventKit write. So
    /// typing fills a buffer and the commit is a flush — on the idle delay, on focus leaving the
    /// editor, when the popover closes, and on termination.
    @State private var notesDraft = ""
    @State private var hasLoadedNotes = false
    @State private var pendingNotesCommit: Task<Void, Never>?
    @State private var notesWindowStart: Date?
    @State private var notesFlushID = UUID()

    /// The draft as the popover opened it. A Save compares against it — see
    /// `CalendarEventEditRequest`.
    private let openedDraft: CadenceScheduleDraft

    private enum PendingAction {
        case save
        case delete
    }

    init(
        item: CalendarEventItem,
        onSave: @escaping (CalendarEventEditRequest, CalendarRecurrenceEditScope) -> Void,
        onDelete: @escaping (CalendarRecurrenceEditScope) -> Void,
        actionFailureNotice: Binding<String?>
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        _actionFailureNotice = actionFailureNotice
        let opened = Self.openingDraft(for: item)
        self.openedDraft = opened
        _draft = State(initialValue: opened)
    }

    /// The draft over the **whole** event, whichever day's segment was clicked.
    ///
    /// Read off the `EKEvent`'s own instants, not the segment's: the panel names a start day and an
    /// end day, so a multi-day event is one record with two dates here rather than the one day the
    /// timeline happened to draw. The title is the item's, the display title the block and card
    /// already print, as it was before.
    static func openingDraft(for item: CalendarEventItem, calendar: Calendar = .current) -> CadenceScheduleDraft {
        let event = item.ekEvent
        let start = event.startDate ?? item.eventStartDate
        let end = event.endDate ?? item.eventEndDate
        var draft = CadenceScheduleDraft(
            editingEventID: item.id,
            title: item.title,
            notes: event.notes ?? "",
            location: event.location ?? "",
            calendarID: calendarIdentifier(of: event),
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            calendar: calendar
        )
        CadenceEventRepeatSetting(event: event, calendar: calendar)?.seed(&draft)
        return draft
    }

    /// The event's calendar identifier, or `""` when it has none (T-2047).
    ///
    /// `EKEvent.calendar` is an implicitly-unwrapped `EKCalendar!`, and an unsaved event built
    /// without one returns `nil`. Every other reader on this path (`CalendarEventItem`,
    /// `CalendarBoardEventDisplayItem`) already goes through `?.`; reading it bare here trapped in
    /// `init` the moment such an event's card was clicked. All the readers in this popover go
    /// through this one function so none of them can drift back to the bare read.
    static func calendarIdentifier(of event: EKEvent) -> String {
        CalendarEventIdentity.calendarIdentifier(of: event)
    }

    /// Whether EventKit will take a write to this event — `iOSCalendarManager.canModify`'s rule.
    /// Birthdays, Holidays and subscribed feeds are visible on the timeline and read-only, and an
    /// event with no calendar at all (T-2047's fixture) has nowhere to be written.
    static func isEditable(_ event: EKEvent) -> Bool {
        event.calendar?.allowsContentModifications ?? false
    }

    private var isEditable: Bool { Self.isEditable(item.ekEvent) }

    /// Whether the panel draws Repeat: only over rules it can read back — see
    /// `CadenceEventRepeatSetting(rules:…)`.
    private var offersRepeat: Bool { CadenceEventRepeatSetting(event: item.ekEvent) != nil }

    /// A Save that re-rules the series asks only "this and future" — see `editSpan`.
    private var savesRecurrenceChange: Bool {
        pendingAction == .save && draft.changesRecurrence(from: openedDraft)
    }

    private var writableCalendarIDs: [String] {
        calendarManager.writableCalendars.map(\.calendarIdentifier)
    }

    private var canSave: Bool {
        CadenceCalendarEventEditingSupport.canSave(
            title: draft.title,
            isEventEditable: isEditable,
            selectedCalendarID: draft.calendarID,
            writableCalendarIDs: writableCalendarIDs
        )
    }

    private var eventNotes: [Note] {
        allNotes.filter { $0.kind == .meeting }
    }

    private var linkedEventNote: Note? {
        let metadata = EventNoteSupport.eventDateMetadata(from: item.ekEvent)
        return EventNoteSupport.note(
            for: item.id,
            eventTitle: item.title,
            calendarID: Self.calendarIdentifier(of: item.ekEvent),
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin,
            in: eventNotes
        )
    }

    /// The length the header's capsule prints, read off the instants the draft would write so a
    /// multi-day block reads its real length. `nil` for an all-day event — the panel's schedule row
    /// already says "All day" — and for a schedule that names no instant.
    ///
    /// The format is the shared estimate label, with its non-breaking space, as before.
    private var durationLabel: String? {
        guard !draft.isAllDay, let range = draft.eventDateRange() else { return nil }
        let minutes = Int(range.end.timeIntervalSince(range.start) / 60)
        return CadenceTaskPresentationSupport.estimateLabel(minutes: minutes, emptyPlaceholder: "–")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            CadenceSchedulePanel(
                draft: $draft,
                calendarChoices: calendarChoices,
                calendarUnavailableNotice: calendarUnavailableNotice,
                readOnlyNotice: isEditable
                    ? nil
                    : CadenceCalendarEventEditingSupport.readOnlyNotice(calendarName: item.calendarTitle),
                failureNotice: actionFailureNotice,
                canCommit: canSave,
                offersEventRepeat: offersRepeat,
                actions: panelActions
            ) {
                notesField
            }
        }
        .frame(width: CadenceSchedulePanelMetrics.preferredWidth)
        .cadenceCard(cornerRadius: Theme.radiusPanel)
        .onAppear(perform: ensureWritableCalendar)
        .onAppear(perform: loadMirrorBaseline)
        .onAppear(perform: loadNotesIfNeeded)
        .onDisappear {
            flushPendingNotes()
            MarkdownEditorTerminationFlush.shared.unregister(notesFlushID)
        }
        .sheet(isPresented: Binding(
            get: { presentedEventNote != nil },
            set: { if !$0 { presentedEventNote = nil } }
        )) {
            if let presentedEventNote {
                EventNoteEditorSheet(note: presentedEventNote, eventTitle: item.title, nativeEvent: item.ekEvent)
            }
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
    }

    /// The event's calendar and whether it repeats, with its length — the facts this popover's old
    /// header carried and the panel has no row for. The title moved into the panel.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            calendarLabel
            Spacer(minLength: 0)
            if let durationLabel {
                Text(durationLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surface)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated)
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
                        .lineLimit(1)
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

    /// Save, Cancel and — on an event that can be written — Delete. The panel draws them; a
    /// recurring event's Save and Delete both stop at the scope question here before anything is
    /// written, so their outcome reaches the user through the host rather than as a return value.
    private var panelActions: CadenceSchedulePanelActions {
        var actions = CadenceSchedulePanelActions(commit: save, cancel: { dismiss() })
        // Absent, not disabled, on a read-only event: EventKit refuses the removal.
        if isEditable {
            actions.delete = {
                requestAction(.delete)
                return nil
            }
        }
        return actions
    }

    /// **T-467.** The event's calendar link, as the panel's Calendar row reads it.
    ///
    /// This card used to hand the picker `writableCalendars` alone and let it title whatever it
    /// could find. The timeline's events come from `availableCalendars`, which filters by
    /// visibility and not by writability, so an event on an **active read-only** subscribed
    /// calendar reached this editor, printed its calendar's name in `calendarLabel`, and had "No
    /// calendar" underneath — the [[T-441]] collapse, on a second surface.
    ///
    /// The universe here is `availableCalendars`, not `allCalendars`: it is exactly what the
    /// timeline can show, so `availableCalendars` minus `writableCalendars` is exactly the active
    /// read-only calendars and `.readOnly` is always the true word for anything this offer adds
    /// back. Hidden calendars never reach this editor at all — the fetch dropped them first — so
    /// `.hidden` is not a state this editor can be in.
    private var calendarLink: CadenceCalendarLink {
        CadenceCalendarLink(
            linkedCalendarID: draft.calendarID,
            allCalendars: calendarManager.availableCalendars,
            visibleCalendars: calendarManager.writableCalendars,
            exclusion: .readOnly
        )
    }

    private var calendarChoices: [CadenceSchedulePanelChoice] {
        Self.calendarChoices(
            calendars: calendarLink.pickableCalendars(from: calendarManager.availableCalendars),
            link: calendarLink,
            selectedID: draft.calendarID
        )
    }

    /// The panel's calendar rows: the writable offer plus the calendar the event is already on,
    /// each worded by the link — so a read-only one reads "Holidays (Read-only)" in the row and the
    /// menu alike. When the event's calendar is in neither (an event with no calendar, or one the
    /// fetch no longer lists) the row still names what the link calls it rather than falling back
    /// to the panel's "Choose Calendar", which would read as a choice still to make.
    static func calendarChoices(
        calendars: [EKCalendar],
        link: CadenceCalendarLink,
        selectedID: String
    ) -> [CadenceSchedulePanelChoice] {
        var choices = calendars.map {
            CadenceSchedulePanelChoice(
                id: $0.calendarIdentifier,
                name: link.pickerLabel(title: $0.title, calendarID: $0.calendarIdentifier),
                // `cgColor` is implicitly unwrapped and nil on a calendar EventKit has not
                // coloured yet; read as the orphan row's dim rather than trapping.
                color: $0.cgColor.map { Color(cgColor: $0) } ?? Theme.dim,
                systemImage: "calendar"
            )
        }
        if !choices.contains(where: { $0.id == selectedID }) {
            choices.append(
                CadenceSchedulePanelChoice(id: selectedID, name: link.rowState.valueText, color: Theme.dim)
            )
        }
        return choices
    }

    private var calendarUnavailableNotice: String? {
        guard isEditable, calendarManager.writableCalendars.isEmpty else { return nil }
        return "No writable calendars are available."
    }

    /// **[[T-8161]] — the one Notes field.** It replaced two: this card, which only offered to
    /// Create or Open the Cadence note, and the panel's plain notes row underneath it, which wrote
    /// `EKEvent.notes` directly. The field *is* the rich note; Apple Calendar gets a flattened
    /// copy of it (`CadenceEventNotesMerge`).
    ///
    /// **The editor is `MarkdownEditor`, not the panel's `TextField`**, and that is the ticket's
    /// rule (3): the field has to accept an image, because it is the note. The toolbar is off —
    /// this is a popover, and the accessory bar belongs to the full editor the Open control
    /// reaches. A `[[note]]` clicked here leaves through `TaskNoteLinkRouting.openDismissing`,
    /// the route [[T-5151]] (b) chose for the event-note sheet, so nothing is ever presented from
    /// inside the popover.
    ///
    /// Not disabled on a read-only calendar: rule (5) refuses the *mirror*, not the note.
    private var notesField: some View {
        CadenceEventNotesField(
            mirrorsToCalendar: isEditable,
            failureNotice: noteFailureNotice,
            onOpenFullEditor: openEventNote
        ) {
            MarkdownEditor(
                text: notesBinding,
                showsToolbar: false,
                // Not the event's own note ([[T-8751]], the T-8583 rule): the field IS that note.
                // `openNoteReference` still resolves against every note.
                referenceNotes: MarkdownReferenceCompletionSupport.linkableNotes(allNotes, excludingNoteID: linkedEventNote?.id),
                onOpenNoteReference: openNoteReference,
                onEditingChanged: { isEditing in
                    if !isEditing { flushPendingNotes() }
                }
            )
            .frame(minHeight: CadenceEventNotesFieldMetrics.deskEditorHeight)
            .background(Theme.surfaceRecessed)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous))
        }
    }

    /// What the field shows: the buffer once typing has started, and otherwise
    /// `CadenceEventNotesMerge.displayText` — the event's own `EKEvent.notes` when no Cadence note
    /// exists yet (rule 4), and otherwise the note with any Apple Calendar text it does not
    /// already carry appended under a divider (rule 6).
    private var displayedNotes: String {
        hasLoadedNotes
            ? notesDraft
            : CadenceEventNotesMerge.displayText(
                noteContent: linkedEventNote?.content,
                nativeNotes: item.ekEvent.notes
            )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { displayedNotes },
            set: { updateNotesDraft($0) }
        )
    }

    private func loadNotesIfNeeded() {
        guard !hasLoadedNotes else { return }
        notesDraft = CadenceEventNotesMerge.displayText(
            noteContent: linkedEventNote?.content,
            nativeNotes: item.ekEvent.notes
        )
        hasLoadedNotes = true
    }

    private func updateNotesDraft(_ content: String) {
        guard hasLoadedNotes, notesDraft != content else { return }
        notesDraft = content
        scheduleNotesCommit(content)
    }

    /// Re-armed on every keystroke, but never later than the ceiling after the first uncommitted
    /// one, so continuous typing still reaches the store — [[T-7810]]'s schedule, read rather than
    /// re-derived.
    private func scheduleNotesCommit(_ content: String) {
        let schedule = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
            pendingWindowStart: pendingNotesCommit == nil ? nil : notesWindowStart,
            now: Date()
        )
        notesWindowStart = schedule.windowStart
        pendingNotesCommit?.cancel()
        // [[T-7811]]: something is pending now; a quit drains it through this field's flush.
        MarkdownEditorTerminationFlush.shared.register(notesFlushID) {
            guard pendingNotesCommit != nil else { return }
            flushPendingNotes()
        }
        pendingNotesCommit = Task { @MainActor in
            try? await Task.sleep(nanoseconds: schedule.delay)
            guard !Task.isCancelled else { return }
            persistNotesIfNeeded(content)
            pendingNotesCommit = nil
        }
    }

    private func flushPendingNotes() {
        pendingNotesCommit?.cancel()
        pendingNotesCommit = nil
        guard hasLoadedNotes else { return }
        persistNotesIfNeeded(notesDraft)
    }

    /// Writes what the buffer holds, creating the note on the first edit. The guard is what keeps
    /// an untouched popover from minting a `Note`: only text that differs from what the field was
    /// showing is an edit.
    private func persistNotesIfNeeded(_ content: String) {
        guard CadenceEventNotesMerge.isEdit(
            content,
            noteContent: linkedEventNote?.content,
            nativeNotes: item.ekEvent.notes
        ) else { return }
        guard let note = ensureEventNote() else { return }
        // Through `applyContent`, never a bare `note.content =`: the body is also where the note's
        // title and its inline `#tags` come from. The save is left out of it — [[T-5804]]'s split
        // — because an event note's save belongs to `commitNote` and its mirror ordering.
        CadenceCoreNoteSupport.applyContent(note, content: content, in: modelContext)
        commitNotes(note)
    }

    /// Commits the note, and mirrors a flattened copy only when rule (1) allows it.
    ///
    /// `mirroredNoteContent` is the note as this popover opened it, advanced **only** on a mirror
    /// Apple Calendar accepted — so a refused mirror is retried on the next keystroke rather than
    /// being recorded as done.
    private func commitNotes(_ note: Note) {
        let mirrors = isEditable
            && CadenceEventNotesMerge.shouldMirror(content: note.content, lastMirrored: mirroredNoteContent ?? "")
        let outcome = MacEventNoteCommit.commitEventNote(
            note,
            content: note.content,
            nativeEvent: item.ekEvent,
            syncToCalendar: mirrors,
            in: modelContext,
            calendarManager: calendarManager
        )
        if outcome == .saved {
            mirroredNoteContent = note.content
        }
        noteFailureNotice = outcome.notice
    }

    /// The baseline rule (1) compares against: the note as the popover opened it.
    private func loadMirrorBaseline() {
        guard mirroredNoteContent == nil else { return }
        mirroredNoteContent = linkedEventNote?.content ?? ""
    }

    /// A `[[note]]` link leaves the popover rather than presenting inside it ([[T-5151]] (b)).
    private func openNoteReference(id: UUID?, title: String) {
        guard let note = TaskNoteLinkRouting.note(id: id, title: title, in: allNotes) else { return }
        TaskNoteLinkRouting.openDismissing(note, dismiss: { dismiss() })
    }

    /// The panel's commit. `nil` always: a recurring event stops at the scope question, and every
    /// outcome — this one's included — is reported by the host through `actionFailureNotice`.
    private func save() -> String? {
        requestAction(.save)
        return nil
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
            onSave(
                CalendarEventEditRequest(
                    draft: draft,
                    opened: openedDraft,
                    originalStart: item.ekEvent.startDate,
                    originalEnd: item.ekEvent.endDate
                ),
                scope
            )
        case .delete:
            onDelete(scope)
        }
    }

    /// Keeps a writable event pointed at a calendar the picker lists, and leaves a read-only event
    /// on its own calendar — `CadenceCalendarEventEditingSupport.resolvedCalendarID`'s rule, which
    /// the iOS editor reads too.
    private func ensureWritableCalendar() {
        draft.calendarID = CadenceCalendarEventEditingSupport.resolvedCalendarID(
            eventCalendarID: draft.calendarID,
            isEventEditable: isEditable,
            writableCalendarIDs: writableCalendarIDs
        )
    }

    /// **T-503, and the macOS twin of the site [[T-497]] fixed on iOS** — one platform behind, and
    /// worse: `iOSCalendarEventEditSheet.openEventNote` at least attempted a save, while this one
    /// inserted the note and presented the editor over it with no `save()` of any kind. Opening the
    /// editor *is* the report of success here, so the user landed in an editor on a row the store
    /// had never been asked to take, and the row sat pending in the app's single `ModelContext`
    /// until an unrelated save committed it or an unrelated `rollback()` discarded it.
    ///
    /// The trap T-497 found applies unchanged, because both platforms call the same
    /// `CadenceEventNoteSupport.noteForEditing`: it returns an **existing** note as often as it
    /// creates one, and only the second case has anything to un-insert. So the closure records what
    /// it actually inserted rather than assuming — a blind `commitInsert(of: note)` would delete a
    /// note the user already had. When nothing was inserted the commit is a plain flush of the
    /// metadata reconciliation `noteForEditing` performs on the existing note; that is an in-place
    /// field edit the next open recomputes, so it needs no undo, but its refusal still has to stop
    /// the sheet from opening on it.
    private func openEventNote() {
        guard let note = ensureEventNote() else { return }
        presentedEventNote = note
    }

    /// The note this event's Notes field edits, created and committed if it does not exist yet.
    private func ensureEventNote() -> Note? {
        let metadata = EventNoteSupport.eventDateMetadata(from: item.ekEvent)
        var inserted: [any PersistentModel] = []
        guard let note = EventNoteSupport.noteForEditing(
            calendarEventID: item.id,
            eventTitle: item.title,
            calendarID: Self.calendarIdentifier(of: item.ekEvent),
            eventDateKey: metadata.dateKey,
            eventStartMin: metadata.startMin,
            eventEndMin: metadata.endMin,
            nativeNotes: item.ekEvent.notes,
            notes: eventNotes,
            insert: {
                modelContext.insert($0)
                inserted.append($0)
            }
        ) else { return nil }

        // **[[T-8161]] rule (6)**, and the iOS sheet's twin: a note that predates the merge can
        // hold one thing while `EKEvent.notes` holds another, and the field showing both is not
        // the same as the note carrying both. It is written the moment the note is handed to an
        // editor or to a keystroke, before any mirror can run.
        if let merged = CadenceEventNotesMerge.mergedContent(noteContent: note.content, nativeNotes: item.ekEvent.notes) {
            CadenceCoreNoteSupport.applyContent(note, content: merged, in: modelContext)
        }

        do {
            try CadencePendingChangePersistence.commitInsert(of: inserted, in: modelContext)
        } catch {
            noteFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return nil
        }
        noteFailureNotice = nil
        return note
    }
}
#endif
