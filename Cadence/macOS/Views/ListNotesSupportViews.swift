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
    /// The live-card embed handlers, shared with `TaskDetailNotesSection` and `FocusNotesPanel`
    /// ([[T-5120]]). Its `editorTextView` is this pane's text view too (the outline jump reads it).
    @State private var embeds = TaskNotesEmbedHandlers(hoverIDPrefix: "task-note-embed-task-")
    @State private var editorContent = ""
    @State private var loadedTaskID: UUID?
    @State private var derivedState = TaskNoteDerivedState()
    @State private var pendingDerivedStateTask: Task<Void, Never>?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?
    /// [[T-7810]]: when the oldest edit the pending fallback commit carries was made; only
    /// meaningful while `pendingFallbackContentSyncTask` is non-nil.
    @State private var fallbackContentWindowStart: Date?
    /// [[T-7811]]: this editor's key in `MarkdownEditorTerminationFlush`.
    @State private var terminationFlushID = UUID()

    private var taskTitle: String {
        TaskTitleSupport.displayTitle(task.title)
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
                .accessibilityLabel("Task-linked note")
                .accessibilityValue(taskTitle)
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
                    .cadenceControlLabel("Open task notes")
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
                    onOpenNote: onOpenNote,
                    onOpenTask: { embeds.linkedTaskForPopover = $0 }
                )
            }
            let embedScope = TaskNotesEmbedScope(referenceTasks: relatedTasks, ownerTask: task, modelContext: modelContext)
            let embedCallbacks = embeds.callbacks(
                in: embedScope,
                hoveredTaskManager: hoveredTaskManager,
                hoveredEditableManager: hoveredEditableManager
            )
            MarkdownEditor(
                text: noteContentBinding,
                toolbarAccessory: toolbarAccessory,
                slashTemplates: templates,
                referenceNotes: relatedNotes,
                referenceTasks: relatedTasks,
                onOpenNoteReference: openNoteReference,
                onOpenTaskReference: embedCallbacks.openTaskReference,
                onCreateEmbeddedTask: embedCallbacks.createEmbeddedTask,
                onToggleEmbeddedTask: embedCallbacks.toggleEmbeddedTask,
                onToggleEmbeddedSubtask: embedCallbacks.toggleEmbeddedSubtask,
                onRenameEmbeddedTask: embedCallbacks.renameEmbeddedTask,
                onOpenEmbeddedTask: embedCallbacks.openEmbeddedTask,
                onEditEmbeddedTask: embedCallbacks.editEmbeddedTask,
                onHoverEmbeddedTask: embedCallbacks.hoverEmbeddedTask,
                onEditingChanged: handleEditorFocusChange,
                onTextViewChanged: embedCallbacks.textViewChanged
            )
            .overlay(alignment: .topLeading) {
                NoteEmptyBodyPlaceholder(templates: templates, isVisible: isNoteBlank, onApply: applyTemplate)
            }
            .taskNotesEmbedPopovers(embeds, scope: embedScope)

            // Under the editor rather than over the card: the card is drawn by the text view, so
            // there is nothing in SwiftUI's tree to attach a notice to at the point of the refusal.
            if let embeddedTaskFailureNotice = embeds.embeddedTaskFailureNotice {
                CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { embeds.embeddedTaskFailureNotice = nil }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
        // T-9123: an outside write to these notes (sync, MCP, another editor) reaches the buffer.
        .onChange(of: task.notes) { _, storeNotes in
            adoptStoreNotesIfIdle(storeNotes)
        }
        .onDisappear {
            flushPendingEditorContent()
            MarkdownEditorTerminationFlush.shared.unregister(terminationFlushID)
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

    /// [[T-9123]]: adopt an outside change to `task.notes` unless typing is still pending —
    /// `MarkdownEditorStoreAdoption` holds the rule.
    private func adoptStoreNotesIfIdle(_ storeNotes: String) {
        guard let adopted = MarkdownEditorStoreAdoption.adoptedBuffer(
            storeText: storeNotes,
            buffer: editorContent,
            bufferIsLoaded: loadedTaskID == task.id,
            commitIsPending: pendingFallbackContentSyncTask != nil
        ) else { return }
        editorContent = adopted
        refreshDerivedState(for: adopted)
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
        // T-7810: re-armed on every keystroke, but never later than the ceiling after the
        // first uncommitted one, so continuous typing still reaches the store.
        let schedule = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
            pendingWindowStart: pendingFallbackContentSyncTask == nil ? nil : fallbackContentWindowStart,
            now: Date()
        )
        fallbackContentWindowStart = schedule.windowStart
        pendingFallbackContentSyncTask?.cancel()
        // T-7811: something is pending now; a quit drains it through this editor's flush.
        // Gated on the pending task: once a load or flush clears it, this closure's captured
        // note/task may no longer be the one the buffer holds, and must write nothing.
        MarkdownEditorTerminationFlush.shared.register(terminationFlushID) {
            guard pendingFallbackContentSyncTask != nil else { return }
            flushPendingEditorContent()
        }
        pendingFallbackContentSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: schedule.delay)
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
        // T-4971: commit at the flush, not per keystroke. See `commitTypedContent`.
        CadencePendingChangePersistence.commitTypedContent(in: modelContext)
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

    private func jumpToOutline(_ item: MarkdownOutlineItem) {
        guard let editorTextView = embeds.editorTextView else { return }
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
        if let range = NoteUnlinkedMentionResolver.firstLoosePhraseRange(title, in: editorContent) {
            let nsContent = editorContent as NSString
            replaceEditorContent(nsContent.replacingCharacters(in: range, with: markdown))
        } else {
            let separator = editorContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            replaceEditorContent(editorContent + "\(separator)\(markdown)")
        }
    }
}

#endif
