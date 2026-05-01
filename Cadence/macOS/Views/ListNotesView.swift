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
    @State private var searchText = ""
    @State private var selectedTagFilterSlugs: Set<String> = []
    @Query(sort: \Note.order) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Tag.order) private var allTags: [Tag]

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

    private var filteredListNotes: [Note] {
        filteredNotes(listNotes)
    }

    private var filteredMeetingNotes: [Note] {
        filteredNotes(meetingNotes)
    }

    private var relatedNotes: [Note] {
        listNotes + meetingNotes
    }

    private var filterableTags: [Tag] {
        let slugs = Set(relatedNotes.flatMap { ($0.tags ?? []).map(\.slug) })
        return allTags.filter { slugs.contains($0.slug) }
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
                NoteEditorPane(
                    note: eventNote,
                    relatedNotes: relatedNotes,
                    relatedTasks: tasks,
                    onOpenNote: openNote
                )
                    .id(eventNote.id)
            } else if let note = selectedListNote {
                NoteEditorPane(
                    note: note,
                    area: area,
                    project: project,
                    relatedNotes: relatedNotes,
                    relatedTasks: tasks,
                    onOpenNote: openNote,
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
        .onChange(of: filterableTags.map(\.slug)) { _, slugs in
            selectedTagFilterSlugs.formIntersection(Set(slugs))
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

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                TextField("Search notes", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.bg.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, filterableTags.isEmpty ? 10 : 6)

            TagFilterBar(tags: filterableTags, selectedSlugs: $selectedTagFilterSlugs)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !filteredMeetingNotes.isEmpty {
                        noteSection("Meeting Notes") {
                            ForEach(filteredMeetingNotes) { note in
                                MeetingNoteListRow(note: note, isSelected: selectedEventNoteID == note.id)
                                    .onTapGesture {
                                        selectedEventNoteID = note.id
                                        selectedNoteID = nil
                                        requestedEventNoteID = nil
                                    }
                            }
                        }
                    }

                    noteSection(filteredMeetingNotes.isEmpty ? nil : "Notes") {
                        ForEach(filteredListNotes) { note in
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
            } else if filteredListNotes.isEmpty && filteredMeetingNotes.isEmpty {
                Spacer()
                EmptyStateView(
                    message: "No matches",
                    subtitle: "Try a different search",
                    icon: "magnifyingglass"
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

    private func openNote(_ note: Note) {
        if note.kind == .meeting {
            selectedEventNoteID = note.id
            selectedNoteID = nil
        } else {
            openListNote(note)
        }
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

    private func filteredNotes(_ notes: [Note]) -> [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiredTagSlugs = selectedTagFilterSlugs
        guard !query.isEmpty || !requiredTagSlugs.isEmpty else { return notes }
        return notes.filter { note in
            let noteTagSlugs = Set((note.tags ?? []).map(\.slug))
            guard requiredTagSlugs.isSubset(of: noteTagSlugs) else { return false }
            guard !query.isEmpty else { return true }
            return note.displayTitle.localizedCaseInsensitiveContains(query) ||
                    note.content.localizedCaseInsensitiveContains(query) ||
                    note.sortedTags.contains { tag in
                        tag.name.localizedCaseInsensitiveContains(query) ||
                            tag.slug.localizedCaseInsensitiveContains(TagSupport.slug(for: query))
                    }
        }
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
            VStack(alignment: .leading, spacing: 4) {
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
                CompactTagStrip(tags: note.sortedTags, limit: 2)
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
