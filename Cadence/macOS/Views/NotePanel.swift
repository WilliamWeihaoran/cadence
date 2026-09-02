#if os(macOS)
import SwiftUI
import SwiftData

struct NotePanel: View {
    private enum CoreNoteSyncTiming {
        static let fallbackContentCommitDelay: UInt64 = 15_000_000_000
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    var useStandardHeaderHeight = false

    @State private var activeTab: CadenceCoreNoteTab = .today
    @State private var todayNote:  Note?
    @State private var weekNote:   Note?
    @State private var permNote:   Note?
    @State private var notesContext: ModelContext?
    @State private var activeTextView: CadenceTextView?
    @State private var linkedTaskForPopover: AppTask?
    @State private var embeddedTaskEditRequest: TaskEmbedFieldEditRequest?
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @State private var editorContent = ""
    /// Set when an edit made on a task card embedded in the open note was refused. See
    /// `toggleEmbeddedSubtask` (T-648).
    @State private var embeddedTaskFailureNotice: String?
    @State private var loadedNoteID: UUID?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?

    /// The context this panel's notes are loaded into and written back through.
    ///
    /// `refreshFromStore()` replaces `notesContext` wholesale, so the environment's context is
    /// only the fallback for the frames before `loadOrCreate()` runs. Writing through
    /// `modelContext` once `notesContext` exists would update a `Note` the panel is not showing;
    /// writing through a `notesContext` that has already been discarded loses the edit outright,
    /// and SwiftData reports neither. One spelling, one place.
    private var currentNotesContext: ModelContext {
        notesContext ?? modelContext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    // The column's one name. It read `NOTES / <active tab>` — the column named
                    // once in the eyebrow, then the tab strip's own answer restated in the title,
                    // with the strip eight lines below already drawing that word lit. See
                    // `PanelHeader` (T-602). The strip answers "which note"; this answers "which
                    // column"; neither question is now answered twice.
                    PanelHeader(title: "Notes")
                    Spacer()
                    if let activeNote {
                        NoteActionMenu(note: activeNote, onAppendSummary: { summary in
                            appendSummary(summary, to: activeNote)
                        })
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(CadenceCoreNoteTab.allCases) { tab in
                        NotePanelTabButton(tab: tab, isSelected: activeTab == tab) {
                            selectTab(tab)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .frame(height: useStandardHeaderHeight ? todayPanelHeaderHeight : nil, alignment: .top)
            .zIndex(50)

            Divider().background(Theme.borderSubtle)

            // Content
            Group {
                switch activeTab {
                case .today:
                    if let note = todayNote {
                        noteEditor(for: note)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .week:
                    if let note = weekNote {
                        noteEditor(for: note)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .notepad:
                    if let note = permNote {
                        noteEditor(for: note)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .zIndex(0)

            // Under the editor rather than over the card: the card is drawn by the text view, so
            // there is nothing in SwiftUI's tree to attach a notice to at the point of the refusal.
            if let embeddedTaskFailureNotice {
                CadenceInlineFailureNotice(text: embeddedTaskFailureNotice)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .background(Theme.surface)
        .onAppear { loadOrCreate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            flushPendingEditorContent()
            refreshFromStore()
        }
        .onChange(of: activeTab) { _, _ in
            refreshFromStore()
        }
        .onDisappear {
            flushPendingEditorContent()
            pendingFallbackContentSyncTask?.cancel()
            pendingFallbackContentSyncTask = nil
        }
    }

    private var activeNote: Note? {
        notesSnapshot.note(for: activeTab)
    }

    private var notesSnapshot: CadenceCoreNoteState {
        CadenceCoreNoteState(today: todayNote, week: weekNote, notepad: permNote)
    }

    @ViewBuilder
    private func noteEditor(for note: Note) -> some View {
        MarkdownEditor(
            text: coreNoteContentBinding(for: note),
            referenceTasks: allTasks,
            onOpenTaskReference: openTaskReference,
            onCreateEmbeddedTask: createEmbeddedTask,
            onToggleEmbeddedTask: toggleEmbeddedTask,
            onToggleEmbeddedSubtask: toggleEmbeddedSubtask,
            onRenameEmbeddedTask: renameEmbeddedTask,
            onOpenEmbeddedTask: openEmbeddedTask,
            onEditEmbeddedTask: editEmbeddedTask,
            onHoverEmbeddedTask: hoverEmbeddedTask,
            onEditingChanged: handleEditorFocusChange,
            onTextViewChanged: { activeTextView = $0 }
        )
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
        .onAppear {
            loadEditorStateIfNeeded(for: note)
        }
    }

    private func loadOrCreate() {
        // Deliberately *not* `currentNotesContext`. This is the one site that wants a brand new
        // private context when there isn't one yet, rather than the environment's — the panel's
        // notes must live in a context it can discard and rebuild without disturbing the rest of
        // the window.
        let context = notesContext ?? makeNotesContext()
        notesContext = context

        let snapshot = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: context)
        todayNote = snapshot.today
        weekNote = snapshot.week
        permNote = snapshot.notepad
    }

    private func refreshFromStore() {
        // The flush has to come first: it moves the editor's in-flight text into the context so
        // the save below can see it. Then `CadenceModelContextRefresh` saves before it swaps —
        // the same contract `macOSRootView.refreshAppData()` relies on.
        flushPendingEditorContent()
        notesContext = CadenceModelContextRefresh.replacement(for: currentNotesContext)
        todayNote = nil
        weekNote = nil
        permNote = nil
        loadOrCreate()
    }

    private func makeNotesContext() -> ModelContext {
        ModelContext(modelContext.container)
    }

    private func selectTab(_ tab: CadenceCoreNoteTab) {
        guard activeTab != tab else { return }
        flushPendingEditorContent()
        activeTab = tab
    }

    private func coreNoteContentBinding(for note: Note) -> Binding<String> {
        Binding(
            get: { loadedNoteID == note.id ? editorContent : note.content },
            set: { updateEditorContent($0, for: note) }
        )
    }

    private func loadEditorStateIfNeeded(for note: Note, force: Bool = false) {
        guard force || loadedNoteID != note.id else { return }
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        loadedNoteID = note.id
        editorContent = note.content
    }

    private func updateEditorContent(_ content: String, for note: Note) {
        if loadedNoteID != note.id {
            loadedNoteID = note.id
            editorContent = note.content
        }
        guard editorContent != content else { return }
        editorContent = content
        scheduleFallbackContentSync(for: content, noteID: note.id)
    }

    private func scheduleFallbackContentSync(for content: String, noteID: UUID) {
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: CoreNoteSyncTiming.fallbackContentCommitDelay)
            guard !Task.isCancelled, loadedNoteID == noteID else { return }
            persistEditorContentIfNeeded(content, noteID: noteID)
            pendingFallbackContentSyncTask = nil
        }
    }

    private func flushPendingEditorContent() {
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        guard let loadedNoteID else { return }
        persistEditorContentIfNeeded(editorContent, noteID: loadedNoteID)
    }

    private func handleEditorFocusChange(_ isFocused: Bool) {
        guard !isFocused else { return }
        flushPendingEditorContent()
    }

    private func persistEditorContentIfNeeded(_ content: String, noteID: UUID) {
        guard let note = notesSnapshot.note(for: activeTab), note.id == noteID else { return }
        guard note.content != content else { return }
        CadenceCoreNoteSupport.update(note, content: content, in: currentNotesContext)
    }

    private func createEmbeddedTask(title: String) -> MarkdownReferenceSuggestion? {
        let draft = TaskCreationDraft(
            title: title,
            notes: "",
            priority: .none,
            container: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )
        // T-364: commit first, hand the reference back second. The editor writes
        // `[[task:UUID|Title]]` into the note only when this returns non-nil, so a refused commit
        // has to return nil — otherwise the note keeps a reference to a task the store never took,
        // and the line renders as a broken embed forever. `createTask` has already removed the
        // task again by the time it throws.
        let created: AppTask?
        do {
            created = try TaskCreationService(areas: [], projects: [])
                .createTask(from: draft, into: modelContext)
        } catch {
            return nil
        }
        guard let task = created else { return nil }

        recentEmbeddedTasks[task.id] = task
        activeTextView?.markdownTaskEmbeds[task.id] = MarkdownTaskEmbedRenderInfo.task(task)
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
        activeTextView?.markdownTaskEmbeds[id] = MarkdownTaskEmbedRenderInfo.task(task)
        if let activeTextView {
            MarkdownStylist.apply(to: activeTextView)
            activeTextView.needsDisplay = true
        }
    }

    /// **T-648.** `refreshEmbeddedTask` repaints the card in the note, so calling it over a
    /// swallowed save showed a tick the store may not hold — [[T-366]] again, in the spelling that
    /// hands the render info sideways instead of returning it.
    private func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID) {
        guard let task = embeddedTask(id: taskID),
              let subtask = (task.subtasks ?? []).first(where: { $0.id == subtaskID }) else { return }
        guard CadenceNoteTaskEmbedEditing.toggleSubtask(subtask, in: modelContext) else {
            embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        embeddedTaskFailureNotice = nil
        refreshEmbeddedTask(task)
    }

    /// See `toggleEmbeddedSubtask` — the same claim, about the card's title rather than its ticks.
    private func renameEmbeddedTask(id: UUID, title: String) {
        guard let task = embeddedTask(id: id) else { return }
        guard CadenceNoteTaskEmbedEditing.rename(task, to: title, in: modelContext) else {
            embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        embeddedTaskFailureNotice = nil
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
    /// Run when the inspector this pane opens on a card closes, which is the one moment where a
    /// rename has demonstrably just happened and this note is the note on screen. The inline rename
    /// over the card already writes both halves; the inspector writes `task.title` alone, and the
    /// card goes on looking right because it is drawn from the live task rather than from the text
    /// under it. `MarkdownTaskEmbedParser` decides which references move — the same call iOS makes
    /// when its task sheet dismisses.
    ///
    /// This closes the renames made *through this note*. A rename made anywhere else while the note
    /// is open — Today's task column beside this very pane, a list, the timeline — still leaves the
    /// reference stale until the pointer next crosses the card (`hoverEmbeddedTask`) or the note is
    /// reopened after a rename here.
    private func reconcileEmbeddedTaskReferenceTitles() {
        guard let activeTextView else { return }
        activeTextView.reconcileEmbeddedTaskReferenceTitles(
            titles: activeTextView.markdownTaskEmbeds.mapValues(\.title)
        )
    }

    private func refreshEmbeddedTask(_ task: AppTask) {
        activeTextView?.markdownTaskEmbeds[task.id] = MarkdownTaskEmbedRenderInfo.task(task)
        activeTextView?.replaceEmbeddedTaskReferenceTitle(id: task.id, title: task.title)
        if let activeTextView {
            MarkdownStylist.apply(to: activeTextView)
            activeTextView.needsDisplay = true
        }
    }

    private func openTaskReference(id: UUID?, title: String) {
        if let id, let task = embeddedTask(id: id) {
            linkedTaskForPopover = task
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let task = allTasks.first(where: {
                  $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare(targetTitle) == .orderedSame
              }) else { return }
        linkedTaskForPopover = task
    }

    /// The live query first, then the creation-latency cache — re-verified against the store, so
    /// a task deleted elsewhere stops being interactive in this note instead of living on in
    /// `recentEmbeddedTasks` (T-349).
    private func embeddedTask(id: UUID) -> AppTask? {
        MarkdownEmbeddedTaskLookup.resolve(
            id: id,
            liveTasks: allTasks,
            cache: &recentEmbeddedTasks,
            in: modelContext
        )
    }

    private func appendSummary(_ summary: String, to note: Note) {
        flushPendingEditorContent()
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return }
        let separator = note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        let content = "\(note.content)\(separator)## AI Summary\n\n\(trimmedSummary)"
        CadenceCoreNoteSupport.update(note, content: content, in: currentNotesContext)
        if loadedNoteID == note.id {
            editorContent = content
        }
    }
}

// MARK: - Tab Button

private struct NotePanelTabButton: View {
    let tab: CadenceCoreNoteTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
                .frame(minWidth: 78, minHeight: 30)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Rectangle().fill(Theme.blue.opacity(0.8)).frame(height: 1)
                    }
                }
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
