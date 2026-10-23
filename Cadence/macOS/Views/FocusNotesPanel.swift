#if os(macOS)
import SwiftUI
import SwiftData

struct FocusNotesPanel: View {
    let task: AppTask
    @Query(sort: \AppTask.order) private var referenceTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @State private var editorContent = ""
    @State private var loadedTaskID: UUID?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?
    @State private var editorTextView: CadenceTextView?
    @State private var linkedTaskForPopover: AppTask?
    @State private var embeddedTaskEditRequest: TaskEmbedFieldEditRequest?
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]
    /// Set when an edit made on an embedded task card was refused. See `TaskDetailNotesSection`.
    @State private var embeddedTaskFailureNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                        .frame(width: 24, height: 24)
                        .background(Theme.blue.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Task notes")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Capture the details you need while working.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)

            Divider().background(Theme.borderSubtle)

            // T-5060 (c): `referenceTasks` makes `[[task:…]]` embeds draw as live cards rather than
            // unresolved text, so every card and task-link handler comes with it — the same set as
            // `TaskDetailNotesSection` and `TaskNoteEditorPane`, which edit these same notes.
            MarkdownEditor(
                text: taskNotesBinding,
                referenceTasks: referenceTasks,
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

            // Under the editor rather than over the card: the card is drawn by the text view, so
            // there is nothing in SwiftUI's tree to attach a notice to at the point of refusal.
            if let embeddedTaskFailureNotice {
                CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { self.embeddedTaskFailureNotice = nil }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
        .onAppear {
            loadEditorStateIfNeeded(force: true)
        }
        .onChange(of: task.id) { _, _ in
            loadEditorStateIfNeeded(force: true)
        }
        .onDisappear {
            flushPendingEditorContent()
            pendingFallbackContentSyncTask?.cancel()
            pendingFallbackContentSyncTask = nil
        }
    }

    private var taskNotesBinding: Binding<String> {
        Binding(
            get: { loadedTaskID == task.id ? editorContent : task.notes },
            set: { updateEditorContent($0) }
        )
    }

    private func loadEditorStateIfNeeded(force: Bool = false) {
        guard force || loadedTaskID != task.id else { return }
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        loadedTaskID = task.id
        editorContent = task.notes
    }

    private func updateEditorContent(_ content: String) {
        if loadedTaskID != task.id {
            loadedTaskID = task.id
            editorContent = task.notes
        }
        guard editorContent != content else { return }
        editorContent = content
        scheduleFallbackContentSync(for: content, taskID: task.id)
    }

    private func scheduleFallbackContentSync(for content: String, taskID: UUID) {
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: MarkdownEditorSyncTiming.fallbackContentCommitDelay)
            guard !Task.isCancelled, loadedTaskID == taskID else { return }
            persistEditorContentIfNeeded(content, taskID: taskID)
            pendingFallbackContentSyncTask = nil
        }
    }

    private func flushPendingEditorContent() {
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        guard loadedTaskID == task.id else { return }
        persistEditorContentIfNeeded(editorContent, taskID: task.id)
    }

    private func handleEditorFocusChange(_ isFocused: Bool) {
        guard !isFocused else { return }
        flushPendingEditorContent()
    }

    private func persistEditorContentIfNeeded(_ content: String, taskID: UUID) {
        guard task.id == taskID, task.notes != content else { return }
        task.notes = content
        // T-4971: commit at the flush, not per keystroke. See `commitTypedContent`.
        CadencePendingChangePersistence.commitTypedContent(in: modelContext)
    }

    // MARK: - Embedded task cards and `[[task]]` links (T-5060 (c))
    //
    // Copied from `TaskDetailNotesSection`, which mirrors `TaskNoteEditorPane`; a fix to one
    // belongs in all three.

    private func openTaskReference(id: UUID?, title: String) {
        if let id, let linkedTask = referenceTasks.first(where: { $0.id == id }) {
            linkedTaskForPopover = linkedTask
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let linkedTask = referenceTasks.first(where: {
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

        // T-364: commit first, hand the reference back second — a refused commit returns nil so
        // the note never points at a task the store did not take.
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
        do {
            try CadenceTaskMutationSupport.setStatus(
                embeddedTask.isDone ? .todo : .done,
                for: embeddedTask,
                modelContext: modelContext
            )
        } catch {
            embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        embeddedTaskFailureNotice = nil
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
        editorTextView?.markdownTaskEmbeds[id] = MarkdownTaskEmbedRenderInfo.task(embeddedTask)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
    }

    /// T-648: repaint only after the save took, so a swallowed save is not drawn as a success.
    private func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID) {
        guard let embeddedTask = embeddedTask(id: taskID),
              let subtask = (embeddedTask.subtasks ?? []).first(where: { $0.id == subtaskID }) else { return }
        guard CadenceNoteTaskEmbedEditing.toggleSubtask(subtask, in: modelContext) else {
            embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        embeddedTaskFailureNotice = nil
        refreshEmbeddedTask(embeddedTask)
    }

    private func renameEmbeddedTask(id: UUID, title: String) {
        guard let embeddedTask = embeddedTask(id: id) else { return }
        guard CadenceNoteTaskEmbedEditing.rename(embeddedTask, to: title, in: modelContext) else {
            embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        embeddedTaskFailureNotice = nil
        refreshEmbeddedTask(embeddedTask)
    }

    private func openEmbeddedTask(id: UUID) {
        guard let embeddedTask = embeddedTask(id: id) else { return }
        linkedTaskForPopover = embeddedTask
    }

    /// Every field chip but status opens the shared task panel inside the note ([[T-1481]]);
    /// without a text view yet the popover is the fallback.
    private func editEmbeddedTask(id: UUID, field: MarkdownTaskEmbedField) {
        guard let embeddedTask = embeddedTask(id: id) else { return }
        if MarkdownInlineTaskPanelRouting.opensPanel(for: field), let editorTextView {
            editorTextView.presentInlineTaskPanel(for: embeddedTask, field: field, in: modelContext, onSaved: refreshEmbeddedTask)
            return
        }
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
        "focus-note-embed-task-\(id.uuidString)"
    }

    /// See `NotePanel.reconcileEmbeddedTaskReferenceTitles`.
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

    /// The live query first, then the creation-latency cache, re-verified against the store (T-349).
    private func embeddedTask(id: UUID) -> AppTask? {
        MarkdownEmbeddedTaskLookup.resolve(
            id: id,
            liveTasks: referenceTasks,
            cache: &recentEmbeddedTasks,
            in: modelContext
        )
    }
}

#endif
