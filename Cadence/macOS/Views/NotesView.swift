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
                        message: "Nothing written yet",
                        subtitle: "Days you write on appear here. Pick a date above to open one.",
                        icon: "doc.text"
                    )
                    Spacer()
                } else {
                    NotesGroupedListColumn(
                        groups: NotesListGrouping.monthGroups(for: listedNotes, dateKey: { $0.dateKey })
                    ) { note in
                        DailyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                            .onTapGesture { selectedNoteID = note.id }
                    }
                }
            }
            .frame(minWidth: NotesListMetrics.columnMinWidth,
                   idealWidth: NotesListMetrics.columnIdealWidth,
                   maxWidth: NotesListMetrics.columnMaxWidth)
            .background(Theme.surface)

            if let note = selectedNote {
                NoteEditorPane(
                    note: note,
                    relatedNotes: notes,
                    relatedTasks: allTasks,
                    onOpenNote: { selectedNoteID = $0.id }
                )
            } else {
                NotesEditorPlaceholder(title: "Select a note")
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
                        message: "Nothing written yet",
                        subtitle: "Weeks you write in appear here. Pick a date above to open one.",
                        icon: "doc.text"
                    )
                    Spacer()
                } else {
                    NotesGroupedListColumn(
                        groups: NotesListGrouping.monthGroups(
                            for: listedNotes,
                            dateKey: { NotesListGrouping.weekStartDateKey(forWeekKey: $0.weekKey) }
                        )
                    ) { note in
                        WeeklyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                            .onTapGesture { selectedNoteID = note.id }
                    }
                }
            }
            .frame(minWidth: NotesListMetrics.columnMinWidth,
                   idealWidth: NotesListMetrics.columnIdealWidth,
                   maxWidth: NotesListMetrics.columnMaxWidth)
            .background(Theme.surface)

            if let note = selectedNote {
                NoteEditorPane(
                    note: note,
                    relatedNotes: notes,
                    relatedTasks: allTasks,
                    onOpenNote: { selectedNoteID = $0.id }
                )
            } else {
                NotesEditorPlaceholder(title: "Select a week")
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

/// The Notepad tab.
///
/// `NoteKind.permanent` is a singleton — `NoteMigrationService.permanentNote(in:)` returns the one
/// permanent note or creates it — so there is nothing to list. This tab is the editor at full
/// width rather than a one-row list column beside it. Backed by the existing kind; no new
/// `NoteKind` was introduced.
private struct NotepadPage: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @State private var noteID: UUID?

    private var notes: [Note] {
        allNotes.filter { $0.kind == .permanent }
    }

    private var note: Note? {
        notes.first { $0.id == noteID } ?? notes.first
    }

    var body: some View {
        Group {
            if let note {
                NoteEditorPane(
                    note: note,
                    relatedNotes: allNotes,
                    relatedTasks: allTasks
                )
            } else {
                NotesEditorPlaceholder(title: "No notepad yet")
            }
        }
        .onAppear { loadOrCreateNotepad() }
    }

    private func loadOrCreateNotepad() {
        if let existing = notes.first {
            noteID = existing.id
            return
        }
        noteID = (try? CadenceCoreNoteSupport.note(for: .notepad, in: modelContext))?.id
    }
}

private struct MeetingNotesPage: View {
    @Binding var requestedNoteID: UUID?

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @State private var selectedNoteID: UUID?

    private var notes: [Note] {
        allNotes
            .filter { $0.kind == .meeting }
            // Sorted by the meeting's own day, not by last edit: the list is grouped under month
            // headers now, and an edit-ordered list would jump between months row to row.
            .sorted {
                let left = Self.dayKey(for: $0)
                let right = Self.dayKey(for: $1)
                return left == right ? $0.updatedAt > $1.updatedAt : left > right
            }
    }

    private static func dayKey(for note: Note) -> String {
        note.eventDateKey.isEmpty ? DateFormatters.dateKey(from: note.updatedAt) : note.eventDateKey
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
                        message: "No meeting notes yet",
                        subtitle: "Create one from a calendar event",
                        icon: "doc.text"
                    )
                    Spacer()
                } else {
                    NotesGroupedListColumn(
                        groups: NotesListGrouping.monthGroups(for: notes, dateKey: { Self.dayKey(for: $0) })
                    ) { note in
                        MeetingNoteListRow(note: note, isSelected: selectedNoteID == note.id, showsDate: false)
                            .onTapGesture {
                                selectedNoteID = note.id
                                requestedNoteID = nil
                            }
                    }
                }
            }
            .frame(minWidth: NotesListMetrics.columnMinWidth,
                   idealWidth: NotesListMetrics.columnIdealWidth,
                   maxWidth: NotesListMetrics.columnMaxWidth)
            .background(Theme.surface)

            if let note = selectedNote {
                NoteEditorPane(
                    note: note,
                    relatedNotes: notes,
                    relatedTasks: allTasks,
                    onOpenNote: { selectedNoteID = $0.id }
                )
            } else {
                NotesEditorPlaceholder(title: "Select a meeting note")
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
}

private struct NotesListHeader: View {
    let title: String
    /// Present on the tabs whose list is filtered. Empty days no longer have a row, so the header
    /// carries the one control that can still reach them.
    var onPickDate: ((Date) -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
            if let onPickDate {
                NotesDateJumpButton(onPick: onPickDate)
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
