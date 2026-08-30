#if os(macOS)
import SwiftUI
import SwiftData

struct NotesView: View {
    enum NotesPage: String, CaseIterable {
        case daily
        case weekly
        case notepad
        case meeting

        /// User-facing label, deliberately separate from the case name.
        ///
        /// `meeting` keeps its case name because `NoteKind.meeting`'s raw value is persisted in
        /// `Note.kindRaw` — renaming the model case would orphan every existing meeting note.
        /// Only the label reads "Event Notes".
        var title: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .notepad: return "Notepad"
            case .meeting: return "Event Notes"
            }
        }

        /// The kind this tab lists. The fold state is keyed by `NoteKind` so the four columns
        /// remember their own folds — see `CadenceNotesFoldState`.
        var noteKind: NoteKind {
            switch self {
            case .daily: return .daily
            case .weekly: return .weekly
            case .notepad: return .permanent
            case .meeting: return .meeting
            }
        }
    }

    @Environment(NotesNavigationManager.self) private var notesNavigationManager
    @State private var page: NotesPage = .daily
    @State private var requestedMeetingNoteID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // The app's one tab-bar control. This used to be a bespoke blue-underline bar; blue is
            // reserved for things that are actually selected or actionable, and a tab bar is
            // neither special nor worth a second idiom.
            HStack(spacing: CadenceQuietPillMetrics.clusterSpacing) {
                ForEach(NotesPage.allCases, id: \.self) { page in
                    CadenceQuietTabButton(title: page.title, isSelected: self.page == page) {
                        self.page = page
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            Group {
                switch page {
                case .daily:
                    DailyNotesPage()
                case .weekly:
                    WeeklyNotesPage()
                case .notepad:
                    NotepadPage()
                case .meeting:
                    MeetingNotesPage(requestedNoteID: $requestedMeetingNoteID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .onAppear { applyPendingNavigationIfNeeded() }
        .onChange(of: notesNavigationManager.request?.token) { _, _ in
            applyPendingNavigationIfNeeded()
        }
    }

    private func applyPendingNavigationIfNeeded() {
        guard let request = notesNavigationManager.request else { return }
        page = request.page
        requestedMeetingNoteID = request.eventNoteID
        notesNavigationManager.clear()
    }
}

private struct DailyNotesPage: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedNoteID: UUID?

    /// Every daily note, in date order. Selection and the editor's reference set resolve against
    /// this, not against `listedNotes` — a day you jumped to from the header picker but have not
    /// written in yet has no row, and must still stay open in the editor.
    private var notes: [Note] {
        allNotes
            .filter { $0.kind == .daily }
            .sorted { $0.dateKey > $1.dateKey }
    }

    private var listedNotes: [Note] {
        NotesListVisibility.dailyNotes(notes, todayKey: DateFormatters.todayKey())
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                NotesListHeader(title: "Daily Notes", onPickDate: openNote(forDate:))

                if listedNotes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: CadenceEmptyStateCopy.dailyNotesTitle,
                        subtitle: CadenceEmptyStateCopy.dailyNotesSubtitle,
                        icon: "doc.text"
                    )
                    Spacer()
                } else {
                    NotesFoldableListColumn(
                        notes: listedNotes,
                        kind: NotesView.NotesPage.daily.noteKind,
                        dateKey: { $0.dateKey }
                    ) { note in
                        DailyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                            .onTapGesture { selectedNoteID = note.id }
                    }
                }
            }
            .frame(minWidth: CadenceNotesListMetrics.columnMinWidth,
                   idealWidth: CadenceNotesListMetrics.columnIdealWidth,
                   maxWidth: CadenceNotesListMetrics.columnMaxWidth)
            .background(Theme.surface)

            if let note = selectedNote {
                NoteEditorPane(
                    note: note,
                    relatedNotes: notes,
                    relatedTasks: allTasks,
                    onOpenNote: { selectedNoteID = $0.id }
                )
                // Per-note editor, matching the Notepad tab. Without it the pane is reused
                // across a note switch: `.onChange(of: note.id)` then cancels the pending
                // 15-second content sync and overwrites the buffer, so up to fifteen seconds of
                // typing is discarded silently. Tearing the pane down instead fires
                // `.onDisappear` while `note` still points at the note being left, which flushes
                // it. It also stops the NSTextView's undo stack and its hit-test caches from
                // leaking into the next note.
                .id(note.id)
            } else {
                NotesEditorPlaceholder(title: CadenceEmptyStateCopy.selectNoteTitle)
            }
        }
        .onAppear { openNote(forDateKey: DateFormatters.todayKey()) }
        .onChange(of: notes.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    private func openNote(forDate date: Date) {
        openNote(forDateKey: DateFormatters.dateKey(from: date))
    }

    private func openNote(forDateKey key: String) {
        if let existing = notes.first(where: { $0.dateKey == key }) {
            selectedNoteID = existing.id
        } else if let note = try? NoteMigrationService.dailyNote(for: key, in: modelContext) {
            selectedNoteID = note.id
        }
    }

    private func normalizeSelection() {
        guard let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) else { return }
        self.selectedNoteID = listedNotes.first?.id ?? notes.first?.id
    }
}

private struct WeeklyNotesPage: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedNoteID: UUID?

    private var notes: [Note] {
        allNotes
            .filter { $0.kind == .weekly }
            .sorted { $0.weekKey > $1.weekKey }
    }

    private var listedNotes: [Note] {
        NotesListVisibility.weeklyNotes(notes, currentWeekKey: DateFormatters.currentWeekKey())
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                // The picker takes a day, not a week: weeks have no handle you can point at, and
                // "the week containing this date" is how anyone actually locates one.
                NotesListHeader(title: "Weekly Notes", onPickDate: openNote(forDate:))

                if listedNotes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: CadenceEmptyStateCopy.weeklyNotesTitle,
                        subtitle: CadenceEmptyStateCopy.weeklyNotesSubtitle,
                        icon: "doc.text"
                    )
                    Spacer()
                } else {
                    NotesFoldableListColumn(
                        notes: listedNotes,
                        kind: NotesView.NotesPage.weekly.noteKind,
                        dateKey: { NotesListGrouping.weekStartDateKey(forWeekKey: $0.weekKey) }
                    ) { note in
                        WeeklyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                            .onTapGesture { selectedNoteID = note.id }
                    }
                }
            }
            .frame(minWidth: CadenceNotesListMetrics.columnMinWidth,
                   idealWidth: CadenceNotesListMetrics.columnIdealWidth,
                   maxWidth: CadenceNotesListMetrics.columnMaxWidth)
            .background(Theme.surface)

            if let note = selectedNote {
                NoteEditorPane(
                    note: note,
                    relatedNotes: notes,
                    relatedTasks: allTasks,
                    onOpenNote: { selectedNoteID = $0.id }
                )
                // Per-note editor, matching the Notepad tab. Without it the pane is reused
                // across a note switch: `.onChange(of: note.id)` then cancels the pending
                // 15-second content sync and overwrites the buffer, so up to fifteen seconds of
                // typing is discarded silently. Tearing the pane down instead fires
                // `.onDisappear` while `note` still points at the note being left, which flushes
                // it. It also stops the NSTextView's undo stack and its hit-test caches from
                // leaking into the next note.
                .id(note.id)
            } else {
                NotesEditorPlaceholder(title: CadenceEmptyStateCopy.selectWeekTitle)
            }
        }
        .onAppear { openNote(forWeekKey: DateFormatters.currentWeekKey()) }
        .onChange(of: notes.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    private func openNote(forDate date: Date) {
        openNote(forWeekKey: DateFormatters.weekKey(from: date))
    }

    private func openNote(forWeekKey key: String) {
        if let existing = notes.first(where: { $0.weekKey == key }) {
            selectedNoteID = existing.id
        } else if let note = try? NoteMigrationService.weeklyNote(for: key, in: modelContext) {
            selectedNoteID = note.id
        }
    }

    private func normalizeSelection() {
        guard let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) else { return }
        self.selectedNoteID = listedNotes.first?.id ?? notes.first?.id
    }
}

/// The Notepad tab: undated notes, as many as you like.
///
/// It used to be a single editor at full width, because `NoteKind.permanent` was reached only
/// through `NoteMigrationService.permanentNote(in:)`, which returns *the* permanent note or makes
/// it. That accessor still exists and still returns one note — the Today panel's Notepad tab and
/// iOS both want exactly one — but it is no longer the only way in: this page lists
/// `permanentNotes` and adds to them. An upgrading user's one notepad note is the oldest, so it is
/// the last row and the note every other surface still opens.
///
/// No new `NoteKind` was introduced.
private struct NotepadPage: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @State private var selectedNoteID: UUID?

    /// Unfiltered — see `NotesListVisibility.notepadNotes`. A notepad note only exists because it
    /// was asked for, so a blank one is a note you are about to write in, not noise.
    private var notes: [Note] {
        NotesListVisibility.notepadNotes(allNotes)
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                NotesListHeader(title: "Notepad", onCreate: createNote)

                if notes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: CadenceEmptyStateCopy.notepadTitle,
                        subtitle: CadenceEmptyStateCopy.notepadSubtitle,
                        icon: "doc.text"
                    )
                    Spacer()
                } else {
                    NotesFoldableListColumn(
                        notes: notes,
                        kind: NotesView.NotesPage.notepad.noteKind,
                        dateKey: { DateFormatters.dateKey(from: $0.createdAt) }
                    ) { note in
                        NotepadNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                            .onTapGesture { selectedNoteID = note.id }
                    }
                }
            }
            .frame(minWidth: CadenceNotesListMetrics.columnMinWidth,
                   idealWidth: CadenceNotesListMetrics.columnIdealWidth,
                   maxWidth: CadenceNotesListMetrics.columnMaxWidth)
            .background(Theme.surface)

            if let note = selectedNote {
                NoteEditorPane(
                    note: note,
                    relatedNotes: allNotes,
                    relatedTasks: allTasks,
                    onOpenNote: { selectedNoteID = $0.id },
                    onDelete: { deleteNote(note) }
                )
                // Per-note text view, so undo history does not leak between notes.
                .id(note.id)
            } else {
                NotesEditorPlaceholder(title: CadenceEmptyStateCopy.selectNoteTitle)
            }
        }
        .onAppear { loadOrCreateNotepad() }
        .onChange(of: notes.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    /// Opens the newest note, creating the first one if the store has none. Uses the shared
    /// singleton accessor for that first note rather than inserting directly, so a user upgrading
    /// into this page lands on the note they already had instead of a second, empty one.
    private func loadOrCreateNotepad() {
        if let existing = notes.first {
            selectedNoteID = existing.id
            return
        }
        selectedNoteID = (try? CadenceCoreNoteSupport.note(for: .notepad, in: modelContext))?.id
    }

    private func createNote() {
        guard let note = try? NoteMigrationService.createPermanentNote(in: modelContext) else { return }
        selectedNoteID = note.id
    }

    private func deleteNote(_ note: Note) {
        let noteID = note.id
        let title = note.displayTitle
        deleteConfirmationManager.present(
            title: "Delete Note?",
            message: "This will permanently delete \"\(title)\"."
        ) {
            guard let current = notes.first(where: { $0.id == noteID }) else { return }
            if selectedNoteID == noteID {
                selectedNoteID = notes.first { $0.id != noteID }?.id
            }
            // The shared delete — see `ListNotesView.deleteNote` and `CadenceNoteActionSupport`.
            modelContext.deleteNote(current)
        }
    }

    private func normalizeSelection() {
        guard selectedNoteID == nil || !notes.contains(where: { $0.id == selectedNoteID }) else { return }
        selectedNoteID = notes.first?.id
    }
}

private struct MeetingNotesPage: View {
    @Binding var requestedNoteID: UUID?

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @State private var selectedNoteID: UUID?
    @State private var commitNotice: String?

    /// Filter *and* order both live in `NotesListVisibility` now, beside the other three tabs'
    /// rules, so iOS's Event Notes list is the same list in the same order rather than a second
    /// comparator that happens to agree.
    private var notes: [Note] {
        NotesListVisibility.meetingNotes(allNotes)
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                NotesListHeader(title: "Event Notes")

                // Deliberately unfiltered, and deliberately without a date picker. The hide-empty
                // rule exists because daily/weekly notes are created *for* you, one per period,
                // so most rows say nothing. An event note only exists because you made one from a
                // calendar event, there is one per event rather than one per day, and its row
                // carries the event's own title — so it never renders as "Empty" and filtering
                // would only hide notes you deliberately created. There is also no date that
                // would create one: the way in is the calendar event, not a day.
                if notes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: CadenceEmptyStateCopy.meetingNotesTitle,
                        subtitle: CadenceEmptyStateCopy.meetingNotesSubtitle,
                        icon: "doc.text"
                    )
                    Spacer()
                } else {
                    NotesFoldableListColumn(
                        notes: notes,
                        kind: NotesView.NotesPage.meeting.noteKind,
                        dateKey: { NotesListVisibility.meetingDayKey(for: $0) }
                    ) { note in
                        MeetingNoteListRow(note: note, isSelected: selectedNoteID == note.id, showsDate: false)
                            .onTapGesture {
                                selectedNoteID = note.id
                                requestedNoteID = nil
                            }
                    }
                }
            }
            .frame(minWidth: CadenceNotesListMetrics.columnMinWidth,
                   idealWidth: CadenceNotesListMetrics.columnIdealWidth,
                   maxWidth: CadenceNotesListMetrics.columnMaxWidth)
            .background(Theme.surface)

            if let note = selectedNote {
                VStack(spacing: 0) {
                    NoteEditorPane(
                        note: note,
                        relatedNotes: notes,
                        relatedTasks: allTasks,
                        onOpenNote: { selectedNoteID = $0.id },
                        onPersistContent: commitEventNote
                    )
                    // Per-note editor, matching the Notepad tab. Without it the pane is reused
                    // across a note switch: `.onChange(of: note.id)` then cancels the pending
                    // 15-second content sync and overwrites the buffer, so up to fifteen seconds of
                    // typing is discarded silently. Tearing the pane down instead fires
                    // `.onDisappear` while `note` still points at the note being left, which flushes
                    // it. It also stops the NSTextView's undo stack and its hit-test caches from
                    // leaking into the next note.
                    .id(note.id)

                    EventNoteCommitNoticeBanner(notice: commitNotice)
                }
            } else {
                NotesEditorPlaceholder(title: CadenceEmptyStateCopy.selectMeetingNoteTitle)
            }
        }
        .onAppear {
            backfillMetadata()
            applyRequestedSelection()
            normalizeSelection()
        }
        .onChange(of: requestedNoteID) { _, _ in
            applyRequestedSelection()
        }
        .onChange(of: selectedNoteID) { _, _ in
            // The notice describes one note's last commit; carrying it onto the next note would
            // report a miss that never happened there.
            commitNotice = nil
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            backfillMetadata()
            applyRequestedSelection()
            normalizeSelection()
        }
    }

    private func applyRequestedSelection() {
        guard let requestedNoteID else { return }
        guard notes.contains(where: { $0.id == requestedNoteID }) else { return }
        selectedNoteID = requestedNoteID
        self.requestedNoteID = nil
    }

    private func normalizeSelection() {
        if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
            return
        }
        selectedNoteID = notes.first?.id
    }

    private func backfillMetadata() {
        for note in notes where note.calendarID.isEmpty {
            EventNoteSupport.backfillMetadataIfPossible(note, calendarManager: calendarManager)
        }
        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }

    /// **T-389.** This tab is the second macOS editor of an event note, and it had no
    /// `onPersistContent` at all — so unlike the timeline's sheet it never reached Apple Calendar
    /// under any circumstances, and said nothing about that either. Both editors go through the
    /// shared ordered commit now, and both show its notice.
    private func commitEventNote(_ note: Note, content: String) {
        let outcome = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: { try modelContext.save() },
            syncToNativeEvent: {
                EventNoteSupport.syncNativeCalendarNotes(for: note, content: content, calendarManager: calendarManager)
            }
        )
        commitNotice = outcome.notice
    }
}

private struct NotesListHeader: View {
    let title: String
    /// Present on the tabs whose list is filtered. Empty days no longer have a row, so the header
    /// carries the one control that can still reach them.
    var onPickDate: ((Date) -> Void)? = nil
    /// Present on Notepad only. Daily and weekly notes are created by reaching a date, so their
    /// header carries a date picker instead; a notepad note has no date to reach, so the only way
    /// to make one is to say so.
    var onCreate: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
            if let onPickDate {
                NotesDateJumpButton(onPick: onPickDate)
            }
            if let onCreate {
                CadenceQuietPillButton(state: .quiet, action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .help("New note")
                .accessibilityLabel("New note")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)

        Divider().background(Theme.borderSubtle)
    }
}

/// "Go to date" for a filtered note list.
///
/// Wraps the shared `MonthCalendarPanel` rather than growing a second month grid — this is the same
/// calendar the task inspector and create sheet use, so the picker behaves identically wherever it
/// appears. Picking a day hands the date back and closes; the page creates or opens that day's note
/// and selects it. The note stays out of the list until it has something in it, which is the point:
/// the list is an index of days you wrote on, and this is how you write on a new one.
private struct NotesDateJumpButton: View {
    let onPick: (Date) -> Void

    @State private var isOpen = false
    @State private var selection = Date()
    @State private var viewMonth = Date()

    var body: some View {
        CadenceQuietPillButton(state: .quiet, action: { isOpen = true }) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .help("Go to date")
        .accessibilityLabel("Go to date")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            MonthCalendarPanel(
                selection: Binding(
                    get: { selection },
                    set: { newValue in
                        selection = newValue
                        isOpen = false
                        onPick(newValue)
                    }
                ),
                viewMonth: $viewMonth,
                isOpen: $isOpen
            )
        }
    }
}

private struct NotesEditorPlaceholder: View {
    let title: String

    var body: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.dim)
                Text(title)
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}
#endif
