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
    @State private var selectedTaskNoteID: UUID?
    @State private var searchText = ""
    @State private var selectedTagFilterSlugs: Set<String> = []
    @State private var folderSheetRequest: NoteFolderSheetRequest?
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
        let noteSlugs = relatedNotes.flatMap { ($0.tags ?? []).map(\.slug) }
        let taskSlugs = taskNotes.flatMap { ($0.tags ?? []).map(\.slug) }
        let slugs = Set(noteSlugs + taskSlugs)
        return allTags.filter { slugs.contains($0.slug) }
    }

    private var selectedEventNote: Note? {
        meetingNotes.first { $0.id == selectedEventNoteID }
    }

    private var selectedTaskNote: AppTask? {
        tasks.first { $0.id == selectedTaskNoteID }
    }

    private var tasks: [AppTask] {
        if let area {
            return allTasks.filter { $0.area?.id == area.id }
        } else if let project {
            return allTasks.filter { $0.project?.id == project.id }
        }
        return []
    }

    private var taskNotes: [AppTask] {
        tasks.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var filteredTaskNotes: [AppTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return taskNotes.filter {
            let taskTagSlugs = Set(($0.tags ?? []).map(\.slug))
            guard selectedTagFilterSlugs.isSubset(of: taskTagSlugs) else { return false }
            guard !query.isEmpty else { return true }
            return $0.title.localizedCaseInsensitiveContains(query) ||
                $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    private var listNoteFolderNames: [String] {
        Array(Set(listNotes.map { normalizedFolderPath($0.folderPath) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredListNoteGroups: [ListNoteFolderGroup] {
        let grouped = Dictionary(grouping: filteredListNotes) { normalizedFolderPath($0.folderPath) }
        let folders = grouped.keys.sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return folders.map { folder in
            ListNoteFolderGroup(
                folderPath: folder,
                notes: (grouped[folder] ?? []).sorted {
                    if $0.order != $1.order { return $0.order < $1.order }
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
            )
        }
    }

    var body: some View {
        HSplitView {
            notesList
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
                .background(Theme.surface)

            if let task = selectedTaskNote {
                TaskNoteEditorPane(
                    task: task,
                    relatedNotes: relatedNotes,
                    relatedTasks: tasks
                )
                .id(task.id)
            } else if let eventNote = selectedEventNote {
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
        .sheet(item: $folderSheetRequest) { request in
            NoteFolderSheet(request: request) { folderPath in
                applyFolderRequest(request, folderPath: folderPath)
            }
        }
    }

    private var notesList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Menu {
                    Button("New Note") {
                        addNote()
                    }
                    Button("New Note in Folder...") {
                        folderSheetRequest = NoteFolderSheetRequest(mode: .newNote)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
                    if !filteredTaskNotes.isEmpty {
                        noteSection("Task Notes") {
                            ForEach(filteredTaskNotes) { task in
                                TaskNoteListRow(task: task, isSelected: selectedTaskNoteID == task.id)
                                    .onTapGesture {
                                        selectedTaskNoteID = task.id
                                        selectedEventNoteID = nil
                                        selectedNoteID = nil
                                        requestedEventNoteID = nil
                                    }
                            }
                        }
                    }

                    if !filteredMeetingNotes.isEmpty {
                        noteSection("Meeting Notes") {
                            ForEach(filteredMeetingNotes) { note in
                                MeetingNoteListRow(note: note, isSelected: selectedEventNoteID == note.id)
                                    .onTapGesture {
                                        selectedEventNoteID = note.id
                                        selectedNoteID = nil
                                        selectedTaskNoteID = nil
                                        requestedEventNoteID = nil
                                    }
                            }
                        }
                    }

                    ForEach(filteredListNoteGroups) { group in
                        noteSection(group.displayName) {
                            ForEach(group.notes) { note in
                                ListNoteRow(note: note, isSelected: selectedNoteID == note.id)
                                    .onTapGesture {
                                        openListNote(note)
                                    }
                                    .contextMenu {
                                        Button("Copy Note Link") {
                                            NoteActionSupport.copyMarkdownLink(to: note)
                                        }
                                        Menu("Move to Folder") {
                                            Button("No Folder") {
                                                note.folderPath = ""
                                            }
                                            ForEach(listNoteFolderNames, id: \.self) { folder in
                                                Button(folder) {
                                                    note.folderPath = folder
                                                }
                                            }
                                            Button("New Folder...") {
                                                folderSheetRequest = NoteFolderSheetRequest(mode: .moveNote(note.id))
                                            }
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
                }
                .padding(8)
            }

            if listNotes.isEmpty && meetingNotes.isEmpty && taskNotes.isEmpty {
                Spacer()
                EmptyStateView(
                    message: "No notes",
                    subtitle: "Tap + to create one",
                    icon: "doc.text"
                )
                Spacer()
            } else if filteredListNotes.isEmpty && filteredMeetingNotes.isEmpty && filteredTaskNotes.isEmpty {
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

    private func addNote(folderPath: String = "") {
        let note = Note(kind: .list)
        note.area = area
        note.project = project
        note.order = listNotes.count
        note.folderPath = normalizedFolderPath(folderPath)
        note.content = defaultNoteContent(for: note.title)
        modelContext.insert(note)
        selectedNoteID = note.id
        selectedEventNoteID = nil
        selectedTaskNoteID = nil
    }

    private func openListNote(_ note: Note) {
        selectedNoteID = note.id
        selectedEventNoteID = nil
        selectedTaskNoteID = nil
    }

    private func openNote(_ note: Note) {
        if note.kind == .meeting {
            selectedEventNoteID = note.id
            selectedNoteID = nil
            selectedTaskNoteID = nil
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

    private func applyFolderRequest(_ request: NoteFolderSheetRequest, folderPath: String) {
        let normalized = normalizedFolderPath(folderPath)
        switch request.mode {
        case .newNote:
            addNote(folderPath: normalized)
        case .moveNote(let noteID):
            guard let note = listNotes.first(where: { $0.id == noteID }) else { return }
            note.folderPath = normalized
        }
    }

    private func normalizedFolderPath(_ folderPath: String) -> String {
        folderPath
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
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
        selectedTaskNoteID = nil
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
        guard selectedNoteID == nil, selectedEventNoteID == nil, selectedTaskNoteID == nil else { return }
        selectedEventNoteID = meetingNotes.first?.id
        if selectedEventNoteID == nil {
            selectedNoteID = listNotes.first?.id
        }
    }
}

private struct ListNoteFolderGroup: Identifiable {
    let folderPath: String
    let notes: [Note]

    var id: String { folderPath.isEmpty ? "__root__" : folderPath }
    var displayName: String { folderPath.isEmpty ? "Notes" : folderPath }
}

private struct NoteFolderSheetRequest: Identifiable {
    enum Mode {
        case newNote
        case moveNote(UUID)
    }

    let id = UUID()
    let mode: Mode

    var title: String {
        switch mode {
        case .newNote: return "New Folder Note"
        case .moveNote: return "Move to Folder"
        }
    }

    var actionTitle: String {
        switch mode {
        case .newNote: return "Create Note"
        case .moveNote: return "Move"
        }
    }
}

private struct NoteFolderSheet: View {
    let request: NoteFolderSheetRequest
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folderPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                TextField("Planning/Research", text: $folderPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surfaceElevated.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.cadencePlain)

                Button(request.actionTitle) {
                    onSave(folderPath)
                    dismiss()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.blue.opacity(folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.cadencePlain)
                .disabled(folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Theme.surface)
    }
}

private struct TaskNoteEditorPane: View {
    @Bindable var task: AppTask
    let relatedNotes: [Note]
    let relatedTasks: [AppTask]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("Task notes")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Button {
                    TaskNotesPanelController.shared.show(
                        task: task,
                        referenceNotes: relatedNotes,
                        referenceTasks: relatedTasks
                    )
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 30, height: 30)
                        .background(Theme.surfaceElevated.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
                .help("Open task notes")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Theme.borderSubtle)

            MarkdownEditor(
                text: Binding(
                    get: { task.notes },
                    set: { task.notes = $0 }
                ),
                referenceNotes: relatedNotes,
                referenceTasks: relatedTasks
            )
        }
        .background(Theme.bg)
    }
}

private struct TaskNoteListRow: View {
    @Bindable var task: AppTask
    let isSelected: Bool

    private var title: String {
        task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : task.title
    }

    private var excerpt: String {
        task.notes
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                if !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
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
