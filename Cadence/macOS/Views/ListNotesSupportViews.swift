#if os(macOS)
import SwiftUI
import SwiftData

private struct TaskNoteDerivedState {
    var linkedNotes: [Note] = []
    var linkedTasks: [AppTask] = []
    var outline: [MarkdownOutlineItem] = []
    var unlinkedMentions: [Note] = []
}

struct TaskNoteEditorPane: View {
    @Bindable var task: AppTask
    let relatedNotes: [Note]
    let relatedTasks: [AppTask]
    var onOpenNote: (Note) -> Void = { _ in }
    var trailingToolbarAccessory: AnyView? = nil
    var showsExpandButton = true
    @Environment(\.modelContext) private var modelContext
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @AppStorage(NoteTemplateLibrary.storageKey) private var noteTemplateOverridesRaw = ""
    @State private var editorTextView: CadenceTextView?
    @State private var linkedTaskForPopover: AppTask?
    @State private var embeddedTaskEditRequest: TaskEmbedFieldEditRequest?
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @State private var editorContent = ""
    @State private var loadedTaskID: UUID?
    @State private var derivedState = TaskNoteDerivedState()
    @State private var pendingDerivedStateTask: Task<Void, Never>?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?

    private var taskTitle: String {
        task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : task.title
    }

    private var noteContentBinding: Binding<String> {
        Binding(
            get: { loadedTaskID == task.id ? editorContent : task.notes },
            set: { updateEditorContent($0) }
        )
    }

    private var hasReferenceStripContent: Bool {
        !derivedState.linkedNotes.isEmpty || !derivedState.linkedTasks.isEmpty
    }

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.templates(for: .list, overridesRaw: noteTemplateOverridesRaw)
    }

    /// Drives the empty-body placeholder — same rule as `applyTemplate`'s fill-vs-append branch.
    private var isNoteBlank: Bool {
        let source = loadedTaskID == task.id ? editorContent : task.notes
        return MarkdownMetadataParser.splitFrontmatter(in: source).body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var toolbarAccessory: AnyView {
        AnyView(
            HStack(spacing: 8) {
                NoteOutlineJumpButton(outline: derivedState.outline, onJump: jumpToOutline)

                HStack(spacing: 8) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
                    Text(taskTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated.opacity(0.88))
                .clipShape(Capsule())
                .help("Task-linked note")

                if showsExpandButton {
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

                if let trailingToolbarAccessory {
                    trailingToolbarAccessory
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasReferenceStripContent {
                NoteReferenceStrip(
                    linkedNotes: derivedState.linkedNotes,
                    linkedTasks: derivedState.linkedTasks,
                    backlinks: [],
                    onOpenNote: onOpenNote
                )
            }
            MarkdownEditor(
                text: noteContentBinding,
                toolbarAccessory: toolbarAccessory,
                slashTemplates: templates,
                referenceNotes: relatedNotes,
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
            .overlay(alignment: .topLeading) {
                NoteEmptyBodyPlaceholder(templates: templates, isVisible: isNoteBlank, onApply: applyTemplate)
            }
            .popover(item: $linkedTaskForPopover) { linkedTask in
                TaskDetailPopover(task: linkedTask)
                    .frame(width: 380)
            }
            .onChange(of: linkedTaskForPopover?.id) { previous, current in
                guard previous != nil, current == nil else { return }
                reconcileEmbeddedTaskReferenceTitles()
            }
            .popover(item: $embeddedTaskEditRequest) { request in
                if let embeddedTask = embeddedTask(id: request.taskID) {
                    TaskEmbedFieldEditorPopover(task: embeddedTask, initialField: request.field) {
                        refreshEmbeddedTask(embeddedTask)
                    }
                } else {
                    Text("Task no longer exists")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .padding()
                }
            }

            NoteUnlinkedMentionsFooter(mentions: derivedState.unlinkedMentions, onLink: linkMention)
        }
        .background(Theme.surface)
        .onAppear {
            loadEditorStateIfNeeded(force: true)
        }
        .onChange(of: task.id) { _, _ in
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
        guard force || loadedTaskID != task.id else { return }
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        loadedTaskID = task.id
        editorContent = task.notes
        refreshDerivedState(for: task.notes)
    }

    private func updateEditorContent(_ content: String) {
        if loadedTaskID != task.id {
            loadedTaskID = task.id
            editorContent = task.notes
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
        guard !isFocused else { return }
        flushPendingEditorContent()
    }

    private func persistEditorContentIfNeeded(_ content: String) {
        guard task.notes != content || loadedTaskID != task.id else { return }
        task.notes = content
        loadedTaskID = task.id
    }

    private func refreshDerivedState(for content: String) {
        let relatedReferenceNotes = relatedNotes.filter { $0.id.uuidString != task.id.uuidString }
        derivedState = TaskNoteDerivedState(
            linkedNotes: NoteReferenceResolver.linkedNotes(noteID: task.id, content: content, in: relatedNotes),
            linkedTasks: NoteReferenceResolver.linkedTasks(
                in: content,
                tasks: relatedTasks.filter { $0.id != task.id }
            ),
            outline: MarkdownOutlineParser.items(in: content),
            unlinkedMentions: NoteUnlinkedMentionResolver.unlinkedMentions(
                noteID: task.id,
                content: content,
                in: relatedReferenceNotes
            )
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

    private func openNoteReference(id: UUID?, title: String) {
        if let id, let note = relatedNotes.first(where: { $0.id == id }) {
            onOpenNote(note)
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let note = relatedNotes.first(where: {
                  $0.displayTitle.caseInsensitiveCompare(targetTitle) == .orderedSame
              }) else { return }
        onOpenNote(note)
    }

    private func openTaskReference(id: UUID?, title: String) {
        if let id, let linkedTask = relatedTasks.first(where: { $0.id == id }) {
            linkedTaskForPopover = linkedTask
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let linkedTask = relatedTasks.first(where: {
                  $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare(targetTitle) == .orderedSame
              }) else { return }
        linkedTaskForPopover = linkedTask
    }

    private func createEmbeddedTask(title: String) -> MarkdownReferenceSuggestion? {
        let container: TaskContainerSelection
        let areas: [Area]
        let projects: [Project]

        if let area = task.area {
            container = .area(area.id)
            areas = [area]
            projects = []
        } else if let project = task.project {
            container = .project(project.id)
            areas = []
            projects = [project]
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
            sectionName: task.resolvedSectionName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )

        // T-364: commit first, hand the reference back second. The editor writes
        // `[[task:UUID|Title]]` into the note only when this returns non-nil, so a refused commit
        // has to return nil rather than leave the note pointing at a task the store never took.
        let created: AppTask?
        do {
            created = try TaskCreationService(areas: areas, projects: projects)
                .createTask(from: draft, into: modelContext)
        } catch {
            return nil
        }
        guard let embeddedTask = created else { return nil }

        recentEmbeddedTasks[embeddedTask.id] = embeddedTask
        editorTextView?.markdownTaskEmbeds[embeddedTask.id] = MarkdownTaskEmbedRenderInfo.task(embeddedTask)
        return .task(embeddedTask)
    }

    private func toggleEmbeddedTask(id: UUID) {
        guard let embeddedTask = embeddedTask(id: id) else { return }
        if embeddedTask.isDone {
            TaskWorkflowService.markTodo(embeddedTask)
        } else {
            TaskWorkflowService.markDone(embeddedTask, in: modelContext)
        }
        try? modelContext.save()
        editorTextView?.markdownTaskEmbeds[id] = MarkdownTaskEmbedRenderInfo.task(embeddedTask)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
    }

    private func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID) {
        guard let embeddedTask = embeddedTask(id: taskID),
              let subtask = (embeddedTask.subtasks ?? []).first(where: { $0.id == subtaskID }) else { return }
        subtask.isDone.toggle()
        try? modelContext.save()
        refreshEmbeddedTask(embeddedTask)
    }

    private func renameEmbeddedTask(id: UUID, title: String) {
        guard let embeddedTask = embeddedTask(id: id) else { return }
        var priority = embeddedTask.priority
        embeddedTask.title = TaskTitleSupport.titleApplyingPriorityShortcut(title, priority: &priority)
        embeddedTask.priority = priority
        try? modelContext.save()
        refreshEmbeddedTask(embeddedTask)
    }

    private func openEmbeddedTask(id: UUID) {
        guard let embeddedTask = embeddedTask(id: id) else { return }
        linkedTaskForPopover = embeddedTask
    }

    private func editEmbeddedTask(id: UUID, field: MarkdownTaskEmbedField) {
        guard embeddedTask(id: id) != nil else { return }
        embeddedTaskEditRequest = TaskEmbedFieldEditRequest(taskID: id, field: field)
    }

    private func hoverEmbeddedTask(id: UUID, hovering: Bool) {
        guard let embeddedTask = embeddedTask(id: id) else { return }
        if hovering {
            hoveredTaskManager.beginHovering(embeddedTask, source: .note)
            hoveredEditableManager.beginHovering(id: embeddedTaskHoverID(id)) {
                openEmbeddedTask(id: id)
            }
        } else {
            hoveredTaskManager.endHovering(embeddedTask)
            hoveredEditableManager.endHovering(id: embeddedTaskHoverID(id))
            refreshEmbeddedTask(embeddedTask)
        }
    }

    private func embeddedTaskHoverID(_ id: UUID) -> String {
        "task-note-embed-task-\(id.uuidString)"
    }

    /// Bring this task's note text back in line with the tasks it embeds.
    ///
    /// See `NotePanel.reconcileEmbeddedTaskReferenceTitles` for why this hangs off the inspector
    /// closing rather than off the rename itself, and for what it deliberately does not reach.
    private func reconcileEmbeddedTaskReferenceTitles() {
        guard let editorTextView else { return }
        editorTextView.reconcileEmbeddedTaskReferenceTitles(
            titles: editorTextView.markdownTaskEmbeds.mapValues(\.title)
        )
    }

    private func refreshEmbeddedTask(_ embeddedTask: AppTask) {
        editorTextView?.markdownTaskEmbeds[embeddedTask.id] = MarkdownTaskEmbedRenderInfo.task(embeddedTask)
        editorTextView?.replaceEmbeddedTaskReferenceTitle(id: embeddedTask.id, title: embeddedTask.title)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
    }

    /// The live query first, then the creation-latency cache — re-verified against the store, so
    /// a task deleted elsewhere stops being interactive in this note instead of living on in
    /// `recentEmbeddedTasks` (T-349).
    private func embeddedTask(id: UUID) -> AppTask? {
        MarkdownEmbeddedTaskLookup.resolve(
            id: id,
            liveTasks: relatedTasks,
            cache: &recentEmbeddedTasks,
            in: modelContext
        )
    }

    private func jumpToOutline(_ item: MarkdownOutlineItem) {
        guard let editorTextView else { return }
        let safeLocation = min(max(item.location, 0), (editorTextView.string as NSString).length)
        editorTextView.window?.makeFirstResponder(editorTextView)
        editorTextView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        editorTextView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
    }

    private func applyTemplate(_ template: NoteTemplate) {
        // Same split-and-restore as `NoteEditorPane.applyTemplate`: a leading `---` block renders
        // at zero height, so a wholesale rewrite would destroy content the user cannot see.
        let parts = MarkdownMetadataParser.splitFrontmatter(in: editorContent)
        let trimmedBody = parts.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let newBody = trimmedBody.isEmpty ? template.body : trimmedBody + "\n\n" + template.body
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
