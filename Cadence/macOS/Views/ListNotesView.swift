#if os(macOS)
import SwiftUI
import SwiftData

struct ListNotesView: View {
    var area: Area?
    var project: Project?
    @Binding var requestedEventNoteID: UUID?

    init(area: Area? = nil, project: Project? = nil, requestedEventNoteID: Binding<UUID?> = .constant(nil)) {
        self.area = area
        self.project = project
        _requestedEventNoteID = requestedEventNoteID
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(CalendarManager.self) private var calendarManager
    @State private var selectedNoteID: UUID?
    @State private var selectedEventNoteID: UUID?
    @Query(sort: \Note.order) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    private var listNotes: [Note] {
        if let area {
            return allNotes.filter { $0.kind == .list && $0.area?.id == area.id }
        } else if let project {
            return allNotes.filter { $0.kind == .list && $0.project?.id == project.id }
        }
        return []
    }

    private var selectedListNote: Note? {
        listNotes.first { $0.id == selectedNoteID }
    }

    private var linkedCalendarID: String {
        area?.linkedCalendarID ?? project?.linkedCalendarID ?? ""
    }

    private var meetingNotes: [Note] {
        EventNoteSupport.meetingNotes(forLinkedCalendarID: linkedCalendarID, in: allNotes)
    }

    private var selectedEventNote: Note? {
        meetingNotes.first { $0.id == selectedEventNoteID }
    }

    private var tasks: [AppTask] {
        if let area {
            return allTasks.filter { $0.area?.id == area.id }
        } else if let project {
            return allTasks.filter { $0.project?.id == project.id }
        }
        return []
    }

    var body: some View {
        HSplitView {
            notesList
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
                .background(Theme.surface)

            if let eventNote = selectedEventNote {
                NoteEditorPane(note: eventNote)
                    .id(eventNote.id)
            } else if let note = selectedListNote {
                NoteEditorPane(
                    note: note,
                    area: area,
                    project: project,
                    relatedNotes: listNotes,
                    relatedTasks: tasks,
                    onOpenNote: openListNote,
                    onDelete: { deleteNote(note) }
                )
                .id(note.id)
            } else {
                noteEditorPlaceholder
            }
        }
        .background(Theme.bg)
        .onAppear {
            backfillMeetingNoteMetadata()
            applyRequestedEventNoteSelection()
            selectFirstNoteIfNeeded()
        }
        .onChange(of: requestedEventNoteID) { _, _ in
            applyRequestedEventNoteSelection()
        }
        .onChange(of: allNotes.map(\.id)) { _, _ in
            backfillMeetingNoteMetadata()
            applyRequestedEventNoteSelection()
            selectFirstNoteIfNeeded()
        }
    }

    private var notesList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    addNote()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.cadencePlain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !meetingNotes.isEmpty {
                        noteSection("Meeting Notes") {
                            ForEach(meetingNotes) { note in
                                MeetingNoteListRow(note: note, isSelected: selectedEventNoteID == note.id)
                                    .onTapGesture {
                                        selectedEventNoteID = note.id
                                        selectedNoteID = nil
                                        requestedEventNoteID = nil
                                    }
                            }
                        }
                    }

                    noteSection(meetingNotes.isEmpty ? nil : "Notes") {
                        ForEach(listNotes) { note in
                            ListNoteRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture {
                                    openListNote(note)
                                }
                                .contextMenu {
                                    Button("Copy Note Link") {
                                        NoteActionSupport.copyMarkdownLink(to: note)
                                    }
                                    Button(role: .destructive) {
                                        deleteNote(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .padding(8)
            }

            if listNotes.isEmpty && meetingNotes.isEmpty {
                Spacer()
                EmptyStateView(
                    message: "No notes",
                    subtitle: "Tap + to create one",
                    icon: "doc.text"
                )
                Spacer()
            }
        }
    }

    private func noteSection<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.top, title == "Meeting Notes" ? 4 : 0)
            }
            content()
        }
    }

    private var noteEditorPlaceholder: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.dim)
                Text("Select a note")
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func addNote() {
        let note = Note(kind: .list)
        note.area = area
        note.project = project
        note.order = listNotes.count
        note.content = defaultNoteContent(for: note.title)
        modelContext.insert(note)
        selectedNoteID = note.id
        selectedEventNoteID = nil
    }

    private func openListNote(_ note: Note) {
        selectedNoteID = note.id
        selectedEventNoteID = nil
    }

    private func deleteNote(_ note: Note) {
        deleteConfirmationManager.present(
            title: "Delete Note?",
            message: "This will permanently delete \"\(note.displayTitle)\"."
        ) {
            if selectedNoteID == note.id {
                selectedNoteID = listNotes.first { $0.id != note.id }?.id
            }
            modelContext.delete(note)
            modelContext.deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: [note.id])
        }
    }

    private func defaultNoteContent(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let headingTitle = trimmed.isEmpty ? "Untitled" : trimmed
        return "# \(headingTitle)\n\n"
    }

    private func applyRequestedEventNoteSelection() {
        guard let requestedEventNoteID else { return }
        guard meetingNotes.contains(where: { $0.id == requestedEventNoteID }) else { return }
        selectedEventNoteID = requestedEventNoteID
        selectedNoteID = nil
        self.requestedEventNoteID = nil
    }

    private func backfillMeetingNoteMetadata() {
        for note in allNotes where note.kind == .meeting && note.calendarID.isEmpty {
            EventNoteSupport.backfillMetadataIfPossible(note, calendarManager: calendarManager)
        }
        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }

    private func selectFirstNoteIfNeeded() {
        guard selectedNoteID == nil, selectedEventNoteID == nil else { return }
        selectedEventNoteID = meetingNotes.first?.id
        if selectedEventNoteID == nil {
            selectedNoteID = listNotes.first?.id
        }
    }
}

private struct ListNoteRow: View {
    @Bindable var note: Note
    let isSelected: Bool
    @State private var isEditingTitle = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            if isEditingTitle {
                TextField("", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { isEditingTitle = false }
                    .onExitCommand { isEditingTitle = false }
            } else {
                Text(note.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Theme.blue.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: 6,
            fillColor: Theme.blue.opacity(isSelected ? 0.16 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.24 : 0.12)
        )
        .onTapGesture(count: 2) {
            isEditingTitle = true
            focused = true
        }
    }
}
#endif
