#if os(macOS)
import SwiftUI
import SwiftData

struct NotesView: View {
    enum NotesPage: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case meeting = "Meeting"
    }

    @Environment(NotesNavigationManager.self) private var notesNavigationManager
    @State private var page: NotesPage = .daily
    @State private var requestedMeetingNoteID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(NotesPage.allCases, id: \.self) { page in
                    Button {
                        self.page = page
                    } label: {
                        Text(page.rawValue)
                            .font(.system(size: 13, weight: self.page == page ? .semibold : .regular))
                            .foregroundStyle(self.page == page ? Theme.text : Theme.dim)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if self.page == page {
                                    Rectangle().fill(Theme.blue).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.cadencePlain)
                }
                Spacer()
            }
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            Group {
                switch page {
                case .daily:
                    DailyNotesPage()
                case .weekly:
                    WeeklyNotesPage()
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

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(notes) { note in
                            DailyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture { selectedNoteID = note.id }
                        }
                    }
                    .padding(8)
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

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(notes) { note in
                            WeeklyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture { selectedNoteID = note.id }
                        }
                    }
                    .padding(8)
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

private struct MeetingNotesPage: View {
    @Binding var requestedNoteID: UUID?

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @State private var selectedNoteID: UUID?

    private var notes: [Note] {
        allNotes.filter { $0.kind == .meeting }
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                NotesListHeader(title: "Meeting Notes")

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(notes) { note in
                            MeetingNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture {
                                    selectedNoteID = note.id
                                    requestedNoteID = nil
                                }
                        }
                    }
                    .padding(8)
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
