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

    /// This list's tasks. Feeds `taskNotes` — the sidebar's "tasks in this list that have notes" —
    /// which is genuinely a per-list question and must stay scoped.
    ///
    /// It deliberately does **not** feed the editor's `relatedTasks`. `MarkdownEditor` uses that one
    /// input for two jobs: the `[[task:` suggestion list *and* the map it renders embedded task
    /// cards from. Scoping it to this list meant an embed of a task from another list found no
    /// entry in the render map and fell through to `.missing` styling — a live task drawn as if it
    /// had been deleted. The editor now gets `allTasks`, which is what `NotePanel` has always
    /// passed, so a task embed renders the same wherever the note is opened.
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

    /// The folders this list already has, for the row menu. Shared with iOS — see
    /// `CadenceNoteFolderPath` for the convention `folderPath` is a string under.
    private var listNoteFolderNames: [String] {
        CadenceNoteFolderGrouping.folderNames(in: listNotes)
    }

    private var filteredListNoteGroups: [CadenceNoteFolderGroup] {
        CadenceNoteFolderGrouping.groups(for: filteredListNotes)
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
                    relatedTasks: allTasks,
                    onOpenNote: openNote
                )
                .id(task.id)
            } else if let eventNote = selectedEventNote {
                NoteEditorPane(
                    note: eventNote,
                    relatedNotes: relatedNotes,
                    relatedTasks: allTasks,
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
                    relatedTasks: allTasks,
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
            ListNotesHeaderView(
                onNewNote: { addNote() },
                onNewNoteInFolder: { folderSheetRequest = NoteFolderSheetRequest(mode: .newNote) }
            )
            ListNotesSearchField(searchText: $searchText, hasTagFilters: !filterableTags.isEmpty)
            TagFilterBar(tags: filterableTags, selectedSlugs: $selectedTagFilterSlugs)

            Divider().background(Theme.borderSubtle)

            notesScroll
            notesListEmptyState
        }
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
            CollapsibleNoteSection(
                title: "Notes",
                count: filteredListNotes.count,
                isCollapsed: $isListNotesCollapsed
            ) {
                NoteFolderGroupList(groups: filteredListNoteGroups) { note in
                    ListNoteFolderRow(
                        note: note,
                        isSelected: selectedListNoteID == note.id,
                        folderNames: listNoteFolderNames,
                        onSelect: openListNote,
                        onCopyLink: { NoteActionSupport.copyMarkdownLink(to: $0) },
                        onMoveToFolder: { CadenceListNoteFiling.move(note, toFolder: $0) },
                        onNewFolder: { folderSheetRequest = NoteFolderSheetRequest(mode: .moveNote(note.id)) },
                        onDelete: deleteNote
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var eventNoteSection: some View {
        if !filteredEventNotes.isEmpty {
            CollapsibleNoteSection(
                title: "Event Notes",
                count: filteredEventNotes.count,
                isCollapsed: $isEventNotesCollapsed
            ) {
                ListEventNoteSectionRows(
                    notes: filteredEventNotes,
                    selectedNoteID: selectedEventNoteID,
                    onSelect: { select(.event($0.id)) }
                )
            }
        }
    }

    @ViewBuilder
    private var taskNoteSection: some View {
        if !filteredTaskNotes.isEmpty {
            CollapsibleNoteSection(
                title: "Task Notes",
                count: filteredTaskNotes.count,
                isCollapsed: $isTaskNotesCollapsed
            ) {
                ListTaskNoteSectionRows(
                    tasks: filteredTaskNotes,
                    selectedTaskID: selectedTaskNoteID,
                    onSelect: { select(.task($0.id)) }
                )
            }
        }
    }

    private var notesListEmptyState: some View {
        ListNotesEmptyState(
            hasAnyNotes: !(listNotes.isEmpty && eventNotes.isEmpty && taskNotes.isEmpty),
            hasAnyFilteredMatches: !(filteredListNotes.isEmpty && filteredEventNotes.isEmpty && filteredTaskNotes.isEmpty)
        )
    }

    private var noteEditorPlaceholder: some View {
        ListNotesEditorPlaceholder()
    }

    private func addNote(folderPath: String = CadenceNoteFolderPath.root) {
        let note = CadenceListNoteFiling.createNote(
            in: modelContext,
            area: area,
            project: project,
            folderPath: folderPath,
            order: listNotes.count
        )
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
            // The shared delete: the note *and* the images it was the last reader of. Both this
            // site and `NotesView`'s spelled those two steps out separately until T-226 needed a
            // third caller on iOS — see `CadenceNoteActionSupport`.
            modelContext.deleteNote(currentNote)
        }
    }

    private func applyFolderRequest(_ request: NoteFolderSheetRequest, folderPath: String) {
        switch request.mode {
        case .newNote:
            addNote(folderPath: folderPath)
        case .moveNote(let noteID):
            guard let note = listNotes.first(where: { $0.id == noteID }) else { return }
            CadenceListNoteFiling.move(note, toFolder: folderPath)
        }
    }

    private func filteredNotes(_ notes: [Note]) -> [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiredTagSlugs = selectedTagFilterSlugs
        guard !query.isEmpty || !requiredTagSlugs.isEmpty else { return notes }
        // Task embeds are searched under the task's live title, not the copy cached in the note
        // text — see `MarkdownTaskEmbedTitleCache`. Built once here, not once per note.
        let taskTitles = MarkdownTaskEmbedTitleCache.titles(for: allTasks)
        return notes.filter { note in
            let noteTagSlugs = Set((note.tags ?? []).map(\.slug))
            guard requiredTagSlugs.isSubset(of: noteTagSlugs) else { return false }
            guard !query.isEmpty else { return true }
            return note.displayTitle.localizedCaseInsensitiveContains(query) ||
                    MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)
                        .localizedCaseInsensitiveContains(query) ||
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
