#if os(macOS)
import SwiftUI
import SwiftData

private enum ListNotesSelection: Equatable {
    case list(UUID)
    case event(UUID)
    case task(UUID)
}

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
    @State private var selection: ListNotesSelection?
    @State private var searchText = ""
    @State private var selectedTagFilterSlugs: Set<String> = []
    @State private var folderSheetRequest: NoteFolderSheetRequest?
    @State private var isListNotesCollapsed = false
    @State private var isEventNotesCollapsed = false
    @State private var isTaskNotesCollapsed = false
    @Query(sort: \Note.order) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Tag.order) private var allTags: [Tag]

    private var listNotes: [Note] {
        CadenceListNoteSupport.notes(for: area, project: project, in: allNotes)
    }

    private var selectedListNote: Note? {
        guard case .list(let noteID) = selection else { return nil }
        return listNotes.first { $0.id == noteID }
    }

    private var selectedEventNote: Note? {
        guard case .event(let noteID) = selection else { return nil }
        return eventNotes.first { $0.id == noteID }
    }

    private var selectedTaskNote: AppTask? {
        guard case .task(let taskID) = selection else { return nil }
        return taskNotes.first { $0.id == taskID }
    }

    private var selectedListNoteID: UUID? {
        guard case .list(let noteID) = selection else { return nil }
        return noteID
    }

    private var selectedEventNoteID: UUID? {
        guard case .event(let noteID) = selection else { return nil }
        return noteID
    }

    private var selectedTaskNoteID: UUID? {
        guard case .task(let taskID) = selection else { return nil }
        return taskID
    }

    private var linkedCalendarID: String {
        area?.linkedCalendarID ?? project?.linkedCalendarID ?? ""
    }

    private var eventNotes: [Note] {
        EventNoteSupport.meetingNotes(forLinkedCalendarID: linkedCalendarID, in: allNotes)
            .filter { !isPastEventNote($0) }
    }

    private var filteredListNotes: [Note] {
        filteredNotes(listNotes)
    }

    private var filteredEventNotes: [Note] {
        filteredNotes(eventNotes)
    }

    private var relatedNotes: [Note] {
        listNotes + eventNotes
    }

    private var filterableTags: [Tag] {
        let noteSlugs = relatedNotes.flatMap { ($0.tags ?? []).map(\.slug) }
        let taskSlugs = taskNotes.flatMap { ($0.tags ?? []).map(\.slug) }
        let slugs = Set(noteSlugs + taskSlugs)
        return allTags.filter { slugs.contains($0.slug) }
    }

    private var tasks: [AppTask] {
        CadenceTaskQuerySupport.tasks(for: area, project: project, in: allTasks)
    }

    private var taskNotes: [AppTask] {
        tasks.filter {
            !$0.isDone &&
            !$0.isCancelled &&
            !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
                    relatedTasks: tasks,
                    onOpenNote: openNote
                )
                .id(task.id)
            } else if let eventNote = selectedEventNote {
                NoteEditorPane(
                    note: eventNote,
                    relatedNotes: relatedNotes,
                    relatedTasks: tasks,
                    onOpenNote: openNote,
                    headerStyle: .compact
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
                    onDelete: { deleteNote(note) },
                    headerStyle: .compact
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
            normalizeSelectionIfNeeded()
        }
        .onChange(of: requestedEventNoteID) { _, _ in
            applyRequestedEventNoteSelection()
        }
        .onChange(of: allNotes.map(\.id)) { _, _ in
            backfillMeetingNoteMetadata()
            applyRequestedEventNoteSelection()
            normalizeSelectionIfNeeded()
        }
        .onChange(of: allTasks.map { "\($0.id.uuidString)-\($0.statusRaw)" }) { _, _ in
            normalizeSelectionIfNeeded()
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
            notesListHeader
            notesSearchField
            TagFilterBar(tags: filterableTags, selectedSlugs: $selectedTagFilterSlugs)

            Divider().background(Theme.borderSubtle)

            notesScroll
            notesListEmptyState
        }
    }

    private var notesListHeader: some View {
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
    }

    private var notesSearchField: some View {
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
    }

    private var notesScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                listNoteSection
                eventNoteSection
                taskNoteSection
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var listNoteSection: some View {
        if !filteredListNoteGroups.isEmpty {
            collapsibleNoteSection(
                title: "Notes",
                count: filteredListNotes.count,
                isCollapsed: $isListNotesCollapsed
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredListNoteGroups) { group in
                        listNoteGroup(group)
                    }
                }
            }
        }
    }

    private func listNoteGroup(_ group: ListNoteFolderGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !group.folderPath.isEmpty {
                Text(group.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
            }
            ForEach(group.notes) { note in
                listNoteRow(note)
            }
        }
    }

    private func listNoteRow(_ note: Note) -> some View {
        ListNoteRow(note: note, isSelected: selectedListNoteID == note.id)
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

    @ViewBuilder
    private var eventNoteSection: some View {
        if !filteredEventNotes.isEmpty {
            collapsibleNoteSection(
                title: "Event Notes",
                count: filteredEventNotes.count,
                isCollapsed: $isEventNotesCollapsed
            ) {
                ForEach(filteredEventNotes) { note in
                    MeetingNoteListRow(note: note, isSelected: selectedEventNoteID == note.id, showsPreview: false)
                        .onTapGesture {
                            select(.event(note.id))
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var taskNoteSection: some View {
        if !filteredTaskNotes.isEmpty {
            collapsibleNoteSection(
                title: "Task Notes",
                count: filteredTaskNotes.count,
                isCollapsed: $isTaskNotesCollapsed
            ) {
                ForEach(filteredTaskNotes) { task in
                    TaskNoteListRow(task: task, isSelected: selectedTaskNoteID == task.id)
                        .onTapGesture {
                            select(.task(task.id))
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var notesListEmptyState: some View {
        if listNotes.isEmpty && eventNotes.isEmpty && taskNotes.isEmpty {
            Spacer()
            EmptyStateView(
                message: "No notes",
                subtitle: "Tap + to create one",
                icon: "doc.text"
            )
            Spacer()
        } else if filteredListNotes.isEmpty && filteredEventNotes.isEmpty && filteredTaskNotes.isEmpty {
            Spacer()
            EmptyStateView(
                message: "No matches",
                subtitle: "Try a different search",
                icon: "magnifyingglass"
            )
            Spacer()
        }
    }

    private func collapsibleNoteSection<Content: View>(
        title: String,
        count: Int,
        isCollapsed: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isCollapsed.wrappedValue.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isCollapsed.wrappedValue ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 12)
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceElevated.opacity(0.75))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .cadenceHoverHighlight(
                cornerRadius: 7,
                fillColor: Theme.surfaceElevated.opacity(0.55),
                strokeColor: Theme.borderSubtle.opacity(0.8)
            )

            if !isCollapsed.wrappedValue {
                content()
            }
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
        CadenceListNoteSupport.attach(note, to: area, project: project)
        note.order = listNotes.count
        note.folderPath = normalizedFolderPath(folderPath)
        note.content = defaultNoteContent(for: note.title)
        modelContext.insert(note)
        select(.list(note.id), clearsRequestedEventNote: false)
    }

    private func openListNote(_ note: Note) {
        select(.list(note.id))
    }

    private func openNote(_ note: Note) {
        if note.kind == .meeting {
            select(.event(note.id))
        } else {
            openListNote(note)
        }
    }

    private func deleteNote(_ note: Note) {
        let noteID = note.id
        let title = note.displayTitle
        deleteConfirmationManager.present(
            title: "Delete Note?",
            message: "This will permanently delete \"\(title)\"."
        ) {
            guard let currentNote = listNotes.first(where: { $0.id == noteID }) else { return }
            if selection == .list(noteID) {
                selection = replacementSelectionAfterDeletingListNote(noteID)
            }
            modelContext.delete(currentNote)
            modelContext.deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: [noteID])
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
        guard eventNotes.contains(where: { $0.id == requestedEventNoteID }) else { return }
        select(.event(requestedEventNoteID))
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
        guard selection == nil else { return }
        selection = firstAvailableSelection()
    }

    private func normalizeSelectionIfNeeded() {
        if let selection, !containsSelection(selection) {
            self.selection = nil
        }
        selectFirstNoteIfNeeded()
    }

    private func select(_ newSelection: ListNotesSelection?, clearsRequestedEventNote: Bool = true) {
        selection = newSelection
        if clearsRequestedEventNote {
            requestedEventNoteID = nil
        }
    }

    private func containsSelection(_ selection: ListNotesSelection) -> Bool {
        switch selection {
        case .list(let noteID):
            return listNotes.contains { $0.id == noteID }
        case .event(let noteID):
            return eventNotes.contains { $0.id == noteID }
        case .task(let taskID):
            return taskNotes.contains { $0.id == taskID }
        }
    }

    private func firstAvailableSelection() -> ListNotesSelection? {
        if let noteID = filteredListNotes.first?.id {
            return .list(noteID)
        }
        if let noteID = filteredEventNotes.first?.id {
            return .event(noteID)
        }
        if let taskID = filteredTaskNotes.first?.id {
            return .task(taskID)
        }
        return nil
    }

    private func replacementSelectionAfterDeletingListNote(_ deletedNoteID: UUID) -> ListNotesSelection? {
        if let noteID = filteredListNotes.first(where: { $0.id != deletedNoteID })?.id {
            return .list(noteID)
        }
        if let noteID = filteredEventNotes.first?.id {
            return .event(noteID)
        }
        if let taskID = filteredTaskNotes.first?.id {
            return .task(taskID)
        }
        return nil
    }

    private func isPastEventNote(_ note: Note) -> Bool {
        guard !note.eventDateKey.isEmpty else { return false }
        let todayKey = DateFormatters.todayKey()
        if note.eventDateKey < todayKey { return true }
        guard note.eventDateKey == todayKey else { return false }

        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = ((components.hour ?? 0) * 60) + (components.minute ?? 0)
        let comparisonMinutes = note.eventEndMin >= 0 ? note.eventEndMin : note.eventStartMin
        return comparisonMinutes >= 0 && comparisonMinutes < nowMinutes
    }
}
#endif
