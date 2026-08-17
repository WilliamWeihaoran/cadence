#if os(macOS)
import SwiftUI
import SwiftData

private struct NoteEditorDerivedState {
    var linkedNotes: [Note] = []
    var linkedTasks: [AppTask] = []
    var backlinks: [Note] = []
    var unlinkedMentions: [Note] = []
    var outline: [MarkdownOutlineItem] = []
}

struct NoteEditorPane: View {
    enum HeaderStyle {
        case full
        case compact
    }

    @Bindable var note: Note
    var area: Area?
    var project: Project?
    var relatedNotes: [Note] = []
    var relatedTasks: [AppTask] = []
    var onOpenNote: (Note) -> Void = { _ in }
    var onDelete: (() -> Void)?
    var onPersistContent: (Note, String) -> Void = { _, _ in }
    var headerDetail: String?
    var headerAccessory: AnyView?
    var headerStyle: HeaderStyle = .full
    @Environment(\.modelContext) private var modelContext
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @AppStorage(NoteTemplateLibrary.storageKey) private var noteTemplateOverridesRaw = ""
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var editorTextView: CadenceTextView?
    @State private var editorContent = ""
    @State private var linkedTaskForPopover: AppTask?
    @State private var embeddedTaskEditRequest: TaskEmbedFieldEditRequest?
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @State private var loadedNoteID: UUID?
    @State private var derivedState = NoteEditorDerivedState()
    @State private var isEditorFocused = false
    @State private var pendingDerivedStateTask: Task<Void, Never>?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?

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
            get: { loadedNoteID == note.id ? editorContent : note.content },
            set: { updateEditorContent($0) }
        )
    }

    private var noteTagsBinding: Binding<[Tag]> {
        Binding(
            get: { note.tags ?? [] },
            set: { newTags in
                // Single write path: `setTags` resolves the `Tag` rows, folds in inline `#tags`
                // already in the body, and mirrors the result into the note's frontmatter so the
                // YAML stays in sync with the chips even though the block is never rendered.
                TagSupport.setTags(
                    named: newTags.map(\.name),
                    on: note,
                    in: modelContext,
                    writeFrontmatter: true
                )
                editorContent = note.content
                loadedNoteID = note.id
                refreshDerivedState(for: note.content)
            }
        )
    }

    private var shouldEditTitle: Bool {
        note.kind == .list || note.kind == .meeting
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

    private var hasReferenceStripContent: Bool {
        !derivedState.linkedNotes.isEmpty ||
        !derivedState.linkedTasks.isEmpty ||
        !derivedState.backlinks.isEmpty
    }

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.templates(for: note.kind, overridesRaw: noteTemplateOverridesRaw)
    }

    /// Drives the empty-body placeholder — one of the three routes to a template, and the only one
    /// that shows itself. Same notion of "blank" that `applyTemplate` uses, so the placeholder
    /// disappears exactly when applying one would start appending rather than filling.
    ///
    /// Measured against the body, not the raw content: a note that has only been tagged carries a
    /// frontmatter block the user cannot see, and it should still read as empty.
    private var isNoteBlank: Bool {
        let source = loadedNoteID == note.id ? editorContent : note.content
        return isBlankBody(MarkdownMetadataParser.splitFrontmatter(in: source).body)
    }

    private func isBlankBody(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "# \(note.displayTitle)"
    }

    /// The note's entire header: one row.
    ///
    /// It used to be four stacked rows — an eyebrow spelling out the tab you were already looking
    /// at, the title, the tag control, and a strip of template chips. The eyebrow is gone because
    /// "DAILY" above a note you opened from the Daily tab is a label for nobody, and the templates
    /// are gone from here permanently: they are a thing you reach for once, at the start of an
    /// empty note, and they had taken a permanent row at the top of every note forever. They live
    /// in the empty body's placeholder, the `/` menu, and the Actions popover now.
    ///
    /// What is left reads left to right as title, then the note's metadata, then what you can do
    /// to it. Below this there is one more row — the format toolbar — and then the note.
    @ViewBuilder
    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if shouldEditTitle {
                    TextField("Note title", text: titleBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                } else {
                    Text(headerTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                noteTagControl
                headerControls
            }
            // Only the linked-event sheet sets this; the four Notes tabs leave it nil and stay at
            // one row.
            if let headerDetail,
               !headerDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(headerDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    /// Editable chips plus a "+" to add one. This is the note's whole metadata surface —
    /// frontmatter is kept in the file for portability but never rendered, so these chips are the
    /// only place tags are read or written. Writes go through
    /// `TagSupport.setTags(...writeFrontmatter: true)`.
    private var noteTagControl: some View {
        TagPickerControl(
            selectedTags: noteTagsBinding,
            allTags: tags,
            onCreateTag: createTag,
            triggerSymbol: "plus"
        )
        .fixedSize()
    }

    /// Compact surfaces (the list-detail Notes tab) have no header row of their own — a list
    /// note's title is the `# Heading` at the top of its own body. They get the same three
    /// controls in the same order, parked in the format toolbar, so the two read as one component.
    private var toolbarAccessory: AnyView? {
        guard headerStyle == .compact else { return nil }
        return AnyView(
            HStack(spacing: 10) {
                noteTagControl
                headerControls
            }
        )
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            NoteOutlineJumpButton(outline: derivedState.outline, onJump: jumpToOutline)

            if let headerAccessory {
                headerAccessory
            } else {
                NoteActionMenu(
                    note: note,
                    area: area,
                    project: project,
                    templates: templates,
                    onApplyTemplate: applyTemplate,
                    onDelete: onDelete
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if headerStyle == .full {
                noteHeader
                    .zIndex(50)
                // Hairline under the tag strip: the header (title + tags) is metadata, everything
                // below it is the note.
                Divider().background(Theme.borderSubtle)
            }
            if hasReferenceStripContent {
                NoteReferenceStrip(
                    linkedNotes: derivedState.linkedNotes,
                    linkedTasks: derivedState.linkedTasks,
                    backlinks: derivedState.backlinks,
                    onOpenNote: onOpenNote
                )
                .zIndex(10)
            }
            MarkdownEditor(
                text: contentBinding,
                toolbarAccessory: toolbarAccessory,
                slashTemplates: templates,
                referenceNotes: relatedNotes.filter { $0.id != note.id },
                referenceTasks: relatedTasks,
                onOpenNoteReference: openNoteReference,
                onOpenTaskReference: openTaskReference,
                onCreateEmbeddedTask: createEmbeddedTask,
                onToggleEmbeddedTask: toggleEmbeddedTask,
                onToggleEmbeddedSubtask: toggleEmbeddedSubtask,
                onRenameEmbeddedTask: renameEmbeddedTask,
                onOpenEmbeddedTask: openEmbeddedTask,
                onEditEmbeddedTask: editEmbeddedTask,
                onHoverEmbeddedTask: hoverEmbeddedTask,
                onEditingChanged: handleEditorFocusChange,
                onTextViewChanged: { editorTextView = $0 }
            )
            .zIndex(0)
            .overlay(alignment: .topLeading) {
                NoteEmptyBodyPlaceholder(templates: templates, isVisible: isNoteBlank, onApply: applyTemplate)
            }
            .popover(item: $linkedTaskForPopover) { task in
                TaskDetailPopover(task: task)
                    .frame(width: 380)
            }
            .onChange(of: linkedTaskForPopover?.id) { previous, current in
                guard previous != nil, current == nil else { return }
                reconcileEmbeddedTaskReferenceTitles()
            }
            .popover(item: $embeddedTaskEditRequest) { request in
                if let task = embeddedTask(id: request.taskID) {
                    TaskEmbedFieldEditorPopover(task: task, initialField: request.field) {
                        refreshEmbeddedTask(task)
                    }
                } else {
                    Text("Task no longer exists")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .padding()
                }
            }

            NoteUnlinkedMentionsFooter(mentions: derivedState.unlinkedMentions, onLink: linkMention)
                .zIndex(5)
        }
        .background(Theme.surface)
        .onAppear {
            loadEditorStateIfNeeded(force: true)
            TagSupport.syncNoteTagsFromMarkdown(note, in: modelContext)
        }
        .onChange(of: note.id) { _, _ in
            loadEditorStateIfNeeded(force: true)
        }
        .onDisappear {
            flushPendingEditorContent()
            pendingDerivedStateTask?.cancel()
            pendingDerivedStateTask = nil
            pendingFallbackContentSyncTask?.cancel()
            pendingFallbackContentSyncTask = nil
        }
    }

    private func loadEditorStateIfNeeded(force: Bool = false) {
        guard force || loadedNoteID != note.id else { return }
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        loadedNoteID = note.id
        editorContent = note.content
        refreshDerivedState(for: note.content)
    }

    private func updateEditorContent(_ content: String) {
        if loadedNoteID != note.id {
            loadedNoteID = note.id
            editorContent = note.content
        }
        guard editorContent != content else { return }
        editorContent = content
        scheduleDerivedStateRefresh(for: content)
        scheduleFallbackContentSync(for: content)
    }

    private func scheduleDerivedStateRefresh(for content: String) {
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: MarkdownEditorSyncTiming.derivedStateRefreshDelay)
            guard !Task.isCancelled else { return }
            refreshDerivedState(for: content)
            pendingDerivedStateTask = nil
        }
    }

    private func scheduleFallbackContentSync(for content: String) {
        pendingFallbackContentSyncTask?.cancel()
        // The note this content belongs to, captured now. Fifteen seconds is long enough for the
        // pane to be looking at a different note by the time the task fires.
        let noteID = note.id
        pendingFallbackContentSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: MarkdownEditorSyncTiming.fallbackContentCommitDelay)
            guard !Task.isCancelled else { return }
            persistEditorContentIfNeeded(content, noteID: noteID)
            pendingFallbackContentSyncTask = nil
        }
    }

    private func flushPendingEditorContent() {
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        persistEditorContentIfNeeded(editorContent, noteID: loadedNoteID ?? note.id)
        refreshDerivedState(for: editorContent)
    }

    private func handleEditorFocusChange(_ isFocused: Bool) {
        isEditorFocused = isFocused
        guard !isFocused else { return }
        flushPendingEditorContent()
    }

    /// Writes the buffer back to the note it came from, and only to that note.
    ///
    /// The guard used to be `note.content != content || loadedNoteID != note.id`, whose second
    /// clause *forced the write through* during a note switch — the one moment `content` belongs
    /// to a different note than `note` does. That is not a harmless mix-up: `syncTitleFromH1IfNeeded`
    /// below would rename the newly-opened note from the previous note's `# Heading`, and
    /// `onPersistContent` is wired to the event-note sheet, which pushes the body into the user's
    /// real Calendar event. `NotePanel` already threads an id through its debounce for this reason.
    private func persistEditorContentIfNeeded(_ content: String, noteID: UUID) {
        guard note.id == noteID else { return }
        guard note.content != content else { return }
        note.content = content
        note.updatedAt = Date()
        syncTitleFromH1IfNeeded(in: content)
        TagSupport.syncNoteTagsFromMarkdown(note, in: modelContext)
        onPersistContent(note, content)
        loadedNoteID = note.id
    }

    private func refreshDerivedState(for content: String) {
        let relatedReferenceNotes = relatedNotes.filter { $0.id != note.id }
        derivedState = NoteEditorDerivedState(
            linkedNotes: NoteReferenceResolver.linkedNotes(noteID: note.id, content: content, in: relatedNotes),
            linkedTasks: NoteReferenceResolver.linkedTasks(in: content, tasks: relatedTasks),
            backlinks: NoteReferenceResolver.backlinks(noteID: note.id, title: note.displayTitle, in: relatedNotes),
            unlinkedMentions: NoteUnlinkedMentionResolver.unlinkedMentions(
                noteID: note.id,
                content: content,
                in: relatedReferenceNotes
            ),
            outline: MarkdownOutlineParser.items(in: content)
        )
    }

    private func replaceEditorContent(_ content: String) {
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        editorContent = content
        // Synchronous and user-initiated (template apply / mention link), so `note` is the note
        // the content is for.
        persistEditorContentIfNeeded(content, noteID: note.id)
        refreshDerivedState(for: content)
    }

    /// The `# Heading` at the top of the body *is* the rename control for the kinds whose title is
    /// otherwise unreachable.
    ///
    /// `.permanent` joined `.list` here when Notepad stopped being a singleton: a notepad note has
    /// a row in a list now, so it needs a name, and its header renders that name as plain text
    /// rather than a field. Rather than grow a rename UI, it reuses the mechanism list notes have
    /// always used. Daily and weekly are excluded because their titles are their date keys, and
    /// meeting/list notes with an editable header field do not need it — well, `.list` does, since
    /// the list-detail Notes tab hides the header entirely.
    private func syncTitleFromH1IfNeeded(in content: String) {
        guard note.kind == .list || note.kind == .permanent else { return }
        let firstLine = content.prefix(while: { $0 != "\n" })
        guard firstLine.hasPrefix("# ") else { return }
        let h1Text = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !h1Text.isEmpty, h1Text != note.title else { return }
        note.title = h1Text
    }

    private func createTag(_ name: String) -> Tag {
        TagSupport.resolveTags(named: [name], in: modelContext)?.first ?? Tag(name: name)
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
            subtaskTitles: [],
            tags: []
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

    private func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID) {
        guard let task = embeddedTask(id: taskID),
              let subtask = (task.subtasks ?? []).first(where: { $0.id == subtaskID }) else { return }
        subtask.isDone.toggle()
        try? modelContext.save()
        refreshEmbeddedTask(task)
    }

    private func renameEmbeddedTask(id: UUID, title: String) {
        guard let task = embeddedTask(id: id) else { return }
        var priority = task.priority
        task.title = TaskTitleSupport.titleApplyingPriorityShortcut(title, priority: &priority)
        task.priority = priority
        try? modelContext.save()
        refreshEmbeddedTask(task)
    }

    private func openEmbeddedTask(id: UUID) {
        guard let task = embeddedTask(id: id) else { return }
        linkedTaskForPopover = task
    }

    private func editEmbeddedTask(id: UUID, field: MarkdownTaskEmbedField) {
        guard embeddedTask(id: id) != nil else { return }
        embeddedTaskEditRequest = TaskEmbedFieldEditRequest(taskID: id, field: field)
    }

    private func hoverEmbeddedTask(id: UUID, hovering: Bool) {
        guard let task = embeddedTask(id: id) else { return }
        if hovering {
            hoveredTaskManager.beginHovering(task, source: .note)
            hoveredEditableManager.beginHovering(id: embeddedTaskHoverID(id)) {
                openEmbeddedTask(id: id)
            }
        } else {
            hoveredTaskManager.endHovering(task)
            hoveredEditableManager.endHovering(id: embeddedTaskHoverID(id))
            refreshEmbeddedTask(task)
        }
    }

    private func embeddedTaskHoverID(_ id: UUID) -> String {
        "note-embed-task-\(id.uuidString)"
    }

    /// Bring the open note's `[[task:UUID|Title]]` source back in line with the tasks it embeds.
    ///
    /// See `NotePanel.reconcileEmbeddedTaskReferenceTitles` for why this hangs off the inspector
    /// closing rather than off the rename itself, and for what it deliberately does not reach.
    private func reconcileEmbeddedTaskReferenceTitles() {
        guard let editorTextView else { return }
        editorTextView.reconcileEmbeddedTaskReferenceTitles(
            titles: editorTextView.markdownTaskEmbeds.mapValues(\.title)
        )
    }

    private func refreshEmbeddedTask(_ task: AppTask) {
        editorTextView?.markdownTaskEmbeds[task.id] = MarkdownTaskEmbedRenderInfo.task(task)
        editorTextView?.replaceEmbeddedTaskReferenceTitle(id: task.id, title: task.title)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
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

    private func applyTemplate(_ template: NoteTemplate) {
        // Split the frontmatter off first and put it back after. The block is invisible, so
        // rewriting `editorContent` wholesale would silently take the note's tags with it.
        let parts = MarkdownMetadataParser.splitFrontmatter(in: editorContent)
        let trimmedBody = parts.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let newBody = isBlankBody(parts.body) ? template.body : trimmedBody + "\n\n" + template.body
        replaceEditorContent(MarkdownMetadataParser.content(frontmatter: parts.frontmatter, body: newBody))
    }

    private func linkMention(_ mentionedNote: Note) {
        let markdown = NoteReferenceParser.noteReferenceMarkdown(for: mentionedNote)
        let title = mentionedNote.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = firstLoosePhraseRange(title, in: editorContent) {
            let nsContent = editorContent as NSString
            replaceEditorContent(nsContent.replacingCharacters(in: range, with: markdown))
        } else {
            let separator = editorContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            replaceEditorContent(editorContent + "\(separator)\(markdown)")
        }
    }

    private func firstLoosePhraseRange(_ phrase: String, in content: String) -> NSRange? {
        guard !phrase.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length))?.range
    }
}

#endif
