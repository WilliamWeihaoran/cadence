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

    private var notes: [Note] {
        allNotes
            .filter { $0.kind == .daily }
            .sorted { $0.dateKey > $1.dateKey }
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                NotesListHeader(title: "Daily Notes")

                NotesGroupedListColumn(
                    groups: NotesListGrouping.monthGroups(for: notes, dateKey: { $0.dateKey })
                ) { note in
                    DailyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                        .onTapGesture { selectedNoteID = note.id }
                }

                if notes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: "No notes yet",
                        subtitle: "Notes are created automatically each day",
                        icon: "doc.text"
                    )
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 240)
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
        .onAppear { loadOrCreateToday() }
        .onChange(of: notes.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    private func loadOrCreateToday() {
        let key = DateFormatters.todayKey()
        if let existing = notes.first(where: { $0.dateKey == key }) {
            selectedNoteID = existing.id
        } else if let note = try? CadenceCoreNoteSupport.note(for: .today, in: modelContext) {
            selectedNoteID = note.id
        }
    }

    private func normalizeSelection() {
        guard let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) else { return }
        self.selectedNoteID = notes.first?.id
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

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                NotesListHeader(title: "Weekly Notes")

                NotesGroupedListColumn(
                    groups: NotesListGrouping.monthGroups(
                        for: notes,
                        dateKey: { NotesListGrouping.weekStartDateKey(forWeekKey: $0.weekKey) }
                    )
                ) { note in
                    WeeklyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                        .onTapGesture { selectedNoteID = note.id }
                }

                if notes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: "No weekly notes yet",
                        subtitle: "Weekly notes are created automatically",
                        icon: "doc.text"
                    )
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 240)
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
        .onAppear { loadOrCreateThisWeek() }
        .onChange(of: notes.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    private func loadOrCreateThisWeek() {
        let key = DateFormatters.currentWeekKey()
        if let existing = notes.first(where: { $0.weekKey == key }) {
            selectedNoteID = existing.id
        } else if let note = try? CadenceCoreNoteSupport.note(for: .week, in: modelContext) {
            selectedNoteID = note.id
        }
    }

    private func normalizeSelection() {
        guard let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) else { return }
        self.selectedNoteID = notes.first?.id
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

                NotesGroupedListColumn(
                    groups: NotesListGrouping.monthGroups(for: notes, dateKey: { Self.dayKey(for: $0) })
                ) { note in
                    MeetingNoteListRow(note: note, isSelected: selectedNoteID == note.id, showsDate: false)
                        .onTapGesture {
                            selectedNoteID = note.id
                            requestedNoteID = nil
                        }
                }

                if notes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: "No meeting notes yet",
                        subtitle: "Create one from a calendar event",
                        icon: "doc.text"
                    )
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 260)
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

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)

        Divider().background(Theme.borderSubtle)
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
