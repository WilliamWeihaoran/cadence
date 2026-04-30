#if os(macOS)
import SwiftUI
import SwiftData

struct NotesView: View {
    enum NotesPage: String, CaseIterable {
        case daily  = "Daily"
        case weekly = "Weekly"
        case meeting = "Meeting"
    }

    @Environment(NotesNavigationManager.self) private var notesNavigationManager
    @State private var page: NotesPage = .daily
    @State private var requestedMeetingNoteID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Page selector
            HStack(spacing: 0) {
                ForEach(NotesPage.allCases, id: \.self) { p in
                    Button {
                        page = p
                    } label: {
                        Text(p.rawValue)
                            .font(.system(size: 13, weight: page == p ? .semibold : .regular))
                            .foregroundStyle(page == p ? Theme.text : Theme.dim)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if page == p {
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
                case .daily:  DailyNotesPage()
                case .weekly: WeeklyNotesPage()
                case .meeting: MeetingNotesPage(requestedNoteID: $requestedMeetingNoteID)
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

// MARK: - Daily Notes Page

private struct DailyNotesPage: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNoteID: UUID? = nil

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
            // Left: list
            VStack(spacing: 0) {
                HStack {
                    Text("Daily Notes")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().background(Theme.borderSubtle)

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
                    EmptyStateView(message: "No notes yet",
                                   subtitle: "Notes are created automatically each day",
                                   icon: "doc.text")
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 240)
            .background(Theme.surface)

            // Right: editor
            if let note = selectedNote {
                NoteEditorPane(
                    note: note,
                    relatedNotes: notes,
                    relatedTasks: allTasks,
                    onOpenNote: { selectedNoteID = $0.id }
                )
            } else {
                noteEditorPlaceholder
            }
        }
        .onAppear { loadOrCreateToday() }
    }

    private var noteEditorPlaceholder: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 8) {
                Image(systemName: "doc.text").font(.system(size: 32)).foregroundStyle(Theme.dim)
                Text("Select a note").foregroundStyle(Theme.dim)
            }
        }
    }

    private func loadOrCreateToday() {
        let key = DateFormatters.todayKey()
        if let existing = notes.first(where: { $0.dateKey == key }) {
            selectedNoteID = existing.id
        } else {
            if let note = try? NoteMigrationService.dailyNote(for: key, in: modelContext) {
                selectedNoteID = note.id
            }
        }
    }
}

// MARK: - Weekly Notes Page

private struct WeeklyNotesPage: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNoteID: UUID? = nil

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
            // Left: list
            VStack(spacing: 0) {
                HStack {
                    Text("Weekly Notes")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().background(Theme.borderSubtle)

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
                    EmptyStateView(message: "No weekly notes yet",
                                   subtitle: "Weekly notes are created automatically",
                                   icon: "doc.text")
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 240)
            .background(Theme.surface)

            // Right: editor
            if let note = selectedNote {
                NoteEditorPane(
                    note: note,
                    relatedNotes: notes,
                    relatedTasks: allTasks,
                    onOpenNote: { selectedNoteID = $0.id }
                )
            } else {
                ZStack {
                    Theme.bg
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.system(size: 32)).foregroundStyle(Theme.dim)
                        Text("Select a week").foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .onAppear { loadOrCreateThisWeek() }
    }

    private func loadOrCreateThisWeek() {
        let key = DateFormatters.currentWeekKey()
        if let existing = notes.first(where: { $0.weekKey == key }) {
            selectedNoteID = existing.id
        } else {
            if let note = try? NoteMigrationService.weeklyNote(for: key, in: modelContext) {
                selectedNoteID = note.id
            }
        }
    }
}

// MARK: - Meeting Notes Page

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
                HStack {
                    Text("Meeting Notes")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().background(Theme.borderSubtle)

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
                noteEditorPlaceholder
            }
        }
        .onAppear {
            backfillMetadata()
            applyRequestedSelection()
            if selectedNoteID == nil {
                selectedNoteID = notes.first?.id
            }
        }
        .onChange(of: requestedNoteID) { _, _ in
            applyRequestedSelection()
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            applyRequestedSelection()
            if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
                return
            }
            selectedNoteID = notes.first?.id
        }
    }

    private var noteEditorPlaceholder: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 8) {
                Image(systemName: "doc.text").font(.system(size: 32)).foregroundStyle(Theme.dim)
                Text("Select a meeting note").foregroundStyle(Theme.dim)
            }
        }
    }

    private func applyRequestedSelection() {
        guard let requestedNoteID else { return }
        guard notes.contains(where: { $0.id == requestedNoteID }) else { return }
        selectedNoteID = requestedNoteID
        self.requestedNoteID = nil
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

// MARK: - Daily Note List Row

struct DailyNoteListRow: View {
    let note: Note
    let isSelected: Bool

    private var formattedDate: String {
        guard let date = DateFormatters.date(from: note.dateKey) else { return note.dateKey }
        return DateFormatters.longDate.string(from: date)
    }
    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Empty note"
    }
    private var isToday: Bool { note.dateKey == DateFormatters.todayKey() }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isToday ? "Today" : formattedDate)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isToday ? Theme.blue : Theme.muted)
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: 6,
            fillColor: Theme.blue.opacity(isSelected ? 0.14 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.22 : 0.12)
        )
    }
}

// MARK: - Weekly Note List Row

private struct WeeklyNoteListRow: View {
    let note: Note
    let isSelected: Bool

    private var isThisWeek: Bool { note.weekKey == DateFormatters.currentWeekKey() }
    private var label: String { isThisWeek ? "This Week" : DateFormatters.weekLabel(from: note.weekKey) }
    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Empty note"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isThisWeek ? Theme.blue : Theme.muted)
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: 6,
            fillColor: Theme.blue.opacity(isSelected ? 0.14 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.22 : 0.12)
        )
    }
}

struct MeetingNoteListRow: View {
    let note: Note
    let isSelected: Bool

    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "Empty note"
    }

    private var detail: String {
        if let date = DateFormatters.date(from: note.eventDateKey) {
            if note.eventStartMin >= 0, note.eventEndMin >= 0 {
                return "\(DateFormatters.shortDate.string(from: date)) • \(TimeFormatters.timeRange(startMin: note.eventStartMin, endMin: note.eventEndMin))"
            }
            return DateFormatters.shortDate.string(from: date)
        }
        return "Updated \(DateFormatters.shortDate.string(from: note.updatedAt))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: 6,
            fillColor: Theme.blue.opacity(isSelected ? 0.14 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.22 : 0.12)
        )
    }
}

// MARK: - Note Editor Pane

struct NoteEditorPane: View {
    @Bindable var note: Note
    var area: Area?
    var project: Project?
    var relatedNotes: [Note] = []
    var relatedTasks: [AppTask] = []
    var onOpenNote: (Note) -> Void = { _ in }
    var onDelete: (() -> Void)?
    var headerDetail: String?
    var headerAccessory: AnyView?
    @Environment(\.modelContext) private var modelContext
    @State private var editorTextView: CadenceTextView?
    @State private var linkedTaskForPopover: AppTask?
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]

    private var titleBinding: Binding<String> {
        Binding(
            get: { note.title },
            set: {
                note.title = $0
                note.updatedAt = Date()
            }
        )
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { note.content },
            set: {
                note.content = $0
                note.updatedAt = Date()
                syncTitleFromH1IfNeeded()
            }
        )
    }

    private var shouldEditTitle: Bool {
        note.kind == .list || note.kind == .meeting
    }

    private var kindLabel: String {
        switch note.kind {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .permanent: return "Permanent"
        case .list: return "Note"
        case .meeting: return "Meeting"
        }
    }

    private var headerTitle: String {
        switch note.kind {
        case .daily:
            guard let date = DateFormatters.date(from: note.dateKey) else { return note.displayTitle }
            return DateFormatters.longDate.string(from: date)
        case .weekly:
            return DateFormatters.weekLabel(from: note.weekKey)
        default:
            return note.displayTitle
        }
    }

    private var referenceNotes: [Note] {
        relatedNotes.filter { $0.id != note.id }
    }

    private var unlinkedMentions: [Note] {
        NoteUnlinkedMentionResolver.unlinkedMentions(for: note, in: referenceNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kindLabel.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim).kerning(0.8)
                    Spacer()
                    if let headerAccessory {
                        headerAccessory
                    } else {
                        NoteActionMenu(note: note, area: area, project: project, onDelete: onDelete)
                    }
                }
                if shouldEditTitle {
                    TextField("Note title", text: titleBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                } else {
                    Text(headerTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                if let headerDetail,
                   !headerDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(headerDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)
            Divider().background(Theme.borderSubtle)
            NoteReferenceStrip(
                note: note,
                notes: relatedNotes,
                tasks: relatedTasks,
                onOpenNote: onOpenNote
            )
            HSplitView {
                MarkdownEditor(
                    text: contentBinding,
                    referenceNotes: referenceNotes,
                    referenceTasks: relatedTasks,
                    onOpenNoteReference: openNoteReference,
                    onOpenTaskReference: openTaskReference,
                    onCreateEmbeddedTask: createEmbeddedTask,
                    onToggleEmbeddedTask: toggleEmbeddedTask,
                    onOpenEmbeddedTask: openEmbeddedTask,
                    onTextViewChanged: { editorTextView = $0 }
                )
                .frame(minWidth: 360)

                NoteMarkdownSidePanel(
                    content: note.content,
                    noteTitle: note.displayTitle,
                    noteKind: note.kind,
                    unlinkedMentions: unlinkedMentions,
                    onJumpToOutline: jumpToOutline,
                    onInsertFrontmatter: insertFrontmatter,
                    onApplyTemplate: applyTemplate,
                    onLinkMention: linkMention
                )
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 290)
            }
        }
        .background(Theme.surface)
        .popover(item: $linkedTaskForPopover) { task in
            TaskDetailPopover(task: task)
                .frame(width: 380)
        }
    }

    private func syncTitleFromH1IfNeeded() {
        guard note.kind == .list else { return }
        let firstLine = note.content.prefix(while: { $0 != "\n" })
        guard firstLine.hasPrefix("# ") else { return }
        let h1Text = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !h1Text.isEmpty, h1Text != note.title else { return }
        note.title = h1Text
            try? modelContext.save()
    }

    private func openNoteReference(id: UUID?, title: String) {
        if let id, let note = referenceNotes.first(where: { $0.id == id }) {
            onOpenNote(note)
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let note = referenceNotes.first(where: {
                  $0.displayTitle.caseInsensitiveCompare(targetTitle) == .orderedSame
              }) else { return }
        onOpenNote(note)
    }

    private func openTaskReference(id: UUID?, title: String) {
        if let id, let task = relatedTasks.first(where: { $0.id == id }) {
            linkedTaskForPopover = task
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let task = relatedTasks.first(where: {
                  $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare(targetTitle) == .orderedSame
              }) else { return }
        linkedTaskForPopover = task
    }

    private func createEmbeddedTask(title: String) -> MarkdownReferenceSuggestion? {
        let ownerArea = note.kind == .list ? (area ?? note.area) : nil
        let ownerProject = note.kind == .list ? (project ?? note.project) : nil
        let container: TaskContainerSelection
        let areas: [Area]
        let projects: [Project]

        if let ownerArea {
            container = .area(ownerArea.id)
            areas = [ownerArea]
            projects = []
        } else if let ownerProject {
            container = .project(ownerProject.id)
            areas = []
            projects = [ownerProject]
        } else {
            container = .inbox
            areas = []
            projects = []
        }

        let draft = TaskCreationDraft(
            title: title,
            notes: "",
            priority: .none,
            container: container,
            sectionName: TaskSectionDefaults.defaultName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: []
        )

        guard let task = TaskCreationService(areas: areas, projects: projects).insertTask(from: draft, into: modelContext) else {
            return nil
        }

        note.updatedAt = Date()
        try? modelContext.save()
        recentEmbeddedTasks[task.id] = task
        editorTextView?.markdownTaskEmbeds[task.id] = MarkdownTaskEmbedRenderInfo.task(task)
        return .task(task)
    }

    private func toggleEmbeddedTask(id: UUID) {
        guard let task = embeddedTask(id: id) else { return }
        if task.isDone {
            TaskWorkflowService.markTodo(task)
        } else {
            TaskWorkflowService.markDone(task, in: modelContext)
        }
        try? modelContext.save()
        editorTextView?.markdownTaskEmbeds[id] = MarkdownTaskEmbedRenderInfo.task(task)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
    }

    private func openEmbeddedTask(id: UUID) {
        guard let task = embeddedTask(id: id) else { return }
        linkedTaskForPopover = task
    }

    private func embeddedTask(id: UUID) -> AppTask? {
        relatedTasks.first(where: { $0.id == id }) ?? recentEmbeddedTasks[id]
    }

    private func jumpToOutline(_ item: MarkdownOutlineItem) {
        guard let editorTextView else { return }
        let safeLocation = min(max(item.location, 0), (editorTextView.string as NSString).length)
        editorTextView.window?.makeFirstResponder(editorTextView)
        editorTextView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        editorTextView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
    }

    private func insertFrontmatter() {
        let metadata = MarkdownMetadataParser.metadata(in: note.content)
        guard metadata.frontmatter.range == nil else { return }
        note.content = MarkdownMetadataParser.frontmatterInsertion(title: note.displayTitle) + note.content
        note.updatedAt = Date()
    }

    private func applyTemplate(_ template: NoteTemplate) {
        let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "# \(note.displayTitle)" {
            note.content = template.body
        } else {
            note.content = note.content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + template.body
        }
        note.updatedAt = Date()
        syncTitleFromH1IfNeeded()
    }

    private func linkMention(_ mentionedNote: Note) {
        let markdown = NoteReferenceParser.noteReferenceMarkdown(for: mentionedNote)
        let title = mentionedNote.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = firstLoosePhraseRange(title, in: note.content) {
            let nsContent = note.content as NSString
            note.content = nsContent.replacingCharacters(in: range, with: markdown)
        } else {
            let separator = note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            note.content += "\(separator)\(markdown)"
        }
        note.updatedAt = Date()
    }

    private func firstLoosePhraseRange(_ phrase: String, in content: String) -> NSRange? {
        guard !phrase.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length))?.range
    }
}

private struct NoteMarkdownSidePanel: View {
    let content: String
    let noteTitle: String
    let noteKind: NoteKind
    let unlinkedMentions: [Note]
    let onJumpToOutline: (MarkdownOutlineItem) -> Void
    let onInsertFrontmatter: () -> Void
    let onApplyTemplate: (NoteTemplate) -> Void
    let onLinkMention: (Note) -> Void

    private var outline: [MarkdownOutlineItem] {
        MarkdownOutlineParser.items(in: content)
    }

    private var metadata: MarkdownNoteMetadata {
        MarkdownMetadataParser.metadata(in: content)
    }

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.templates(for: noteKind)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection("Outline") {
                    if outline.isEmpty {
                        sidebarEmpty("No headings")
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(outline) { item in
                                Button {
                                    onJumpToOutline(item)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(String(repeating: "  ", count: max(0, item.level - 1)) + item.title)
                                            .font(.system(size: 11, weight: item.level <= 2 ? .semibold : .regular))
                                            .foregroundStyle(item.level <= 2 ? Theme.muted : Theme.dim)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.cadencePlain)
                            }
                        }
                    }
                }

                sidebarSection("Properties") {
                    if metadata.frontmatter.properties.isEmpty && metadata.tags.isEmpty {
                        Button {
                            onInsertFrontmatter()
                        } label: {
                            Label("Add frontmatter", systemImage: "tag")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.cadencePlain)
                    } else {
                        if !metadata.frontmatter.properties.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(metadata.frontmatter.properties.keys.sorted(), id: \.self) { key in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(key)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Theme.dim)
                                            .frame(width: 58, alignment: .leading)
                                        Text(metadata.frontmatter.properties[key] ?? "")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.muted)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        if !metadata.tags.isEmpty {
                            FlowTags(tags: metadata.tags)
                        }
                    }
                }

                sidebarSection("Templates") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(templates) { template in
                            Button {
                                onApplyTemplate(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                    Text(template.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.dim)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }

                sidebarSection("Unlinked") {
                    if unlinkedMentions.isEmpty {
                        sidebarEmpty("No mentions")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(unlinkedMentions, id: \.id) { note in
                                HStack(spacing: 6) {
                                    Text(note.displayTitle)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Button {
                                        onLinkMention(note)
                                    } label: {
                                        Image(systemName: "link")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Theme.blue)
                                    }
                                    .buttonStyle(.cadencePlain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(Theme.bg.opacity(0.34))
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.borderSubtle).frame(width: 1)
        }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarEmpty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.dim)
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}

private struct NoteReferenceStrip: View {
    let note: Note
    let notes: [Note]
    let tasks: [AppTask]
    let onOpenNote: (Note) -> Void

    private var linkedNotes: [Note] {
        NoteReferenceResolver.linkedNotes(for: note, in: notes)
    }

    private var linkedTasks: [AppTask] {
        NoteReferenceResolver.linkedTasks(for: note, in: tasks)
    }

    private var backlinks: [Note] {
        NoteReferenceResolver.backlinks(for: note, in: notes)
    }

    var body: some View {
        if linkedNotes.isEmpty && linkedTasks.isEmpty && backlinks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !linkedNotes.isEmpty {
                    ReferenceSection(label: "Linked Notes") {
                        ForEach(linkedNotes, id: \.id) { linked in
                            Button {
                                onOpenNote(linked)
                            } label: {
                                ReferenceChip(icon: "doc.text", title: linked.displayTitle, tint: Theme.blue)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }

                if !linkedTasks.isEmpty {
                    ReferenceSection(label: "Task References") {
                        ForEach(linkedTasks, id: \.id) { task in
                            ReferenceChip(icon: "checkmark.circle", title: task.title.isEmpty ? "Untitled Task" : task.title, tint: Theme.green)
                        }
                    }
                }

                if !backlinks.isEmpty {
                    ReferenceSection(label: "Backlinks") {
                        ForEach(backlinks, id: \.id) { backlink in
                            Button {
                                onOpenNote(backlink)
                            } label: {
                                ReferenceChip(icon: "arrow.uturn.backward.circle", title: backlink.displayTitle, tint: Theme.amber)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(alignment: .bottom) {
                Divider().background(Theme.borderSubtle)
            }
        }
    }
}

private struct ReferenceSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content }
            }
        }
    }
}

private struct ReferenceChip: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}
#endif
