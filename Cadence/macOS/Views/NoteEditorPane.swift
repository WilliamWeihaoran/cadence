#if os(macOS)
import SwiftUI
import SwiftData

private struct NoteEditorDerivedState {
    var linkedNotes: [Note] = []
    var linkedTasks: [AppTask] = []
    var backlinks: [Note] = []
    var unlinkedMentions: [Note] = []
    var outline: [MarkdownOutlineItem] = []
    var metadata = MarkdownNoteMetadata(
        frontmatter: MarkdownFrontmatter(properties: [:], range: nil),
        tags: []
    )
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
    var headerDetail: String?
    var headerAccessory: AnyView?
    var headerStyle: HeaderStyle = .full
    @Environment(\.modelContext) private var modelContext
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var editorTextView: CadenceTextView?
    @State private var editorContent = ""
    @State private var linkedTaskForPopover: AppTask?
    @State private var embeddedTaskEditRequest: TaskEmbedFieldEditRequest?
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @State private var isInspectorCollapsed = false
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
                let names = newTags.map(\.name) + MarkdownMetadataParser.inlineTagNames(in: note.content)
                note.tags = TagSupport.resolveTags(named: names, in: modelContext)
                note.content = MarkdownMetadataParser.content(note.content, replacingFrontmatterTags: newTags.map(\.name))
                note.updatedAt = Date()
                editorContent = note.content
                loadedNoteID = note.id
                refreshDerivedState(for: note.content)
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

    private var hasReferenceStripContent: Bool {
        !derivedState.linkedNotes.isEmpty ||
        !derivedState.linkedTasks.isEmpty ||
        !derivedState.backlinks.isEmpty
    }

    @ViewBuilder
    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(kindLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim).kerning(0.8)
                Spacer()
                headerControls
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
            TagPickerControl(
                selectedTags: noteTagsBinding,
                allTags: tags,
                onCreateTag: createTag
            )
        }
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)
    }

    private var toolbarAccessory: AnyView? {
        guard headerStyle == .compact else { return nil }
        return AnyView(headerControls)
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            Button {
                isInspectorCollapsed.toggle()
            } label: {
                Image(systemName: isInspectorCollapsed ? "rectangle.split.2x1" : "rectangle.split.2x1.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isInspectorCollapsed ? Theme.muted : Theme.blue)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isInspectorCollapsed ? Theme.surfaceElevated.opacity(0.72) : Theme.blue.opacity(0.14))
                    )
            }
            .buttonStyle(.cadencePlain)
            .help(isInspectorCollapsed ? "Show note sidebar" : "Hide note sidebar")

            if let headerAccessory {
                headerAccessory
            } else {
                NoteActionMenu(note: note, area: area, project: project, onDelete: onDelete)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if headerStyle == .full {
                noteHeader
                    .zIndex(50)
            }
            if hasReferenceStripContent {
                Divider().background(Theme.borderSubtle)
                NoteReferenceStrip(
                    linkedNotes: derivedState.linkedNotes,
                    linkedTasks: derivedState.linkedTasks,
                    backlinks: derivedState.backlinks,
                    onOpenNote: onOpenNote
                )
                .zIndex(10)
            }
            HSplitView {
                MarkdownEditor(
                    text: contentBinding,
                    toolbarAccessory: toolbarAccessory,
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
                .frame(minWidth: 360)

                if !isInspectorCollapsed {
                    NoteMarkdownSidePanel(
                        outline: derivedState.outline,
                        metadata: derivedState.metadata,
                        templates: NoteTemplateLibrary.templates(for: note.kind),
                        unlinkedMentions: derivedState.unlinkedMentions,
                        onJumpToOutline: jumpToOutline,
                        onInsertFrontmatter: insertFrontmatter,
                        onApplyTemplate: applyTemplate,
                        onLinkMention: linkMention
                    )
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 290)
                }
            }
            .zIndex(0)
        }
        .background(Theme.surface)
        .popover(item: $linkedTaskForPopover) { task in
            TaskDetailPopover(task: task)
                .frame(width: 380)
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
        pendingFallbackContentSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: MarkdownEditorSyncTiming.fallbackContentCommitDelay)
            guard !Task.isCancelled else { return }
            persistEditorContentIfNeeded(content)
            pendingFallbackContentSyncTask = nil
        }
    }

    private func flushPendingEditorContent() {
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        persistEditorContentIfNeeded(editorContent)
        refreshDerivedState(for: editorContent)
    }

    private func handleEditorFocusChange(_ isFocused: Bool) {
        isEditorFocused = isFocused
        guard !isFocused else { return }
        flushPendingEditorContent()
    }

    private func persistEditorContentIfNeeded(_ content: String) {
        guard note.content != content || loadedNoteID != note.id else { return }
        note.content = content
        note.updatedAt = Date()
        syncTitleFromH1IfNeeded(in: content)
        TagSupport.syncNoteTagsFromMarkdown(note, in: modelContext)
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
            outline: MarkdownOutlineParser.items(in: content),
            metadata: MarkdownMetadataParser.metadata(in: content)
        )
    }

    private func replaceEditorContent(_ content: String) {
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        editorContent = content
        persistEditorContentIfNeeded(content)
        refreshDerivedState(for: content)
    }

    private func syncTitleFromH1IfNeeded(in content: String) {
        guard note.kind == .list else { return }
        let firstLine = content.prefix(while: { $0 != "\n" })
        guard firstLine.hasPrefix("# ") else { return }
        let h1Text = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !h1Text.isEmpty, h1Text != note.title else { return }
        note.title = h1Text
    }

    private func createTag(_ name: String) -> Tag {
        TagSupport.resolveTags(named: [name], in: modelContext).first ?? Tag(name: name)
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

    private func insertFrontmatter() {
        let metadata = MarkdownMetadataParser.metadata(in: editorContent)
        guard metadata.frontmatter.range == nil else { return }
        replaceEditorContent(MarkdownMetadataParser.frontmatterInsertion(title: note.displayTitle) + editorContent)
    }

    private func applyTemplate(_ template: NoteTemplate) {
        let trimmed = editorContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "# \(note.displayTitle)" {
            replaceEditorContent(template.body)
        } else {
            replaceEditorContent(editorContent.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + template.body)
        }
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
