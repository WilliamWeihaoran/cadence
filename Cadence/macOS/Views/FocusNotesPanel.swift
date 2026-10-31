#if os(macOS)
import SwiftUI
import SwiftData

struct FocusNotesPanel: View {
    let task: AppTask
    @Query(sort: \AppTask.order) private var referenceTasks: [AppTask]
    /// [[T-6461]]: the store's notes, sorted as `NotePanel` sorts them, so `[[` offers notes and a
    /// `[[note]]` link resolves. Without them both defaulted to `[]` / a no-op and a link did nothing.
    @Query(sort: \Note.updatedAt, order: .reverse) private var referenceNotes: [Note]
    @Environment(\.modelContext) private var modelContext
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @State private var editorContent = ""
    @State private var loadedTaskID: UUID?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?
    /// [[T-7810]]: when the oldest edit the pending fallback commit carries was made; only
    /// meaningful while `pendingFallbackContentSyncTask` is non-nil.
    @State private var fallbackContentWindowStart: Date?
    /// [[T-7811]]: this editor's key in `MarkdownEditorTerminationFlush`.
    @State private var terminationFlushID = UUID()
    /// The live-card embed handlers, shared with `TaskDetailNotesSection` and `TaskNoteEditorPane`
    /// ([[T-5120]]).
    @State private var embeds = TaskNotesEmbedHandlers(hoverIDPrefix: "focus-note-embed-task-")

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
            // unresolved text, so every card and task-link handler comes with it — the one set
            // `TaskDetailNotesSection` and `TaskNoteEditorPane` use too ([[T-5120]]).
            let embedScope = TaskNotesEmbedScope(referenceTasks: referenceTasks, ownerTask: task, modelContext: modelContext)
            let embedCallbacks = embeds.callbacks(
                in: embedScope,
                hoveredTaskManager: hoveredTaskManager,
                hoveredEditableManager: hoveredEditableManager
            )
            MarkdownEditor(
                text: taskNotesBinding,
                referenceNotes: referenceNotes,
                referenceTasks: referenceTasks,
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
            .taskNotesEmbedPopovers(embeds, scope: embedScope)

            // Under the editor rather than over the card: the card is drawn by the text view, so
            // there is nothing in SwiftUI's tree to attach a notice to at the point of refusal.
            if let embeddedTaskFailureNotice = embeds.embeddedTaskFailureNotice {
                CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { embeds.embeddedTaskFailureNotice = nil }
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
        // T-9123: an outside write to these notes (sync, MCP, another editor) reaches the buffer.
        .onChange(of: task.notes) { _, storeNotes in
            adoptStoreNotesIfIdle(storeNotes)
        }
        .onDisappear {
            flushPendingEditorContent()
            MarkdownEditorTerminationFlush.shared.unregister(terminationFlushID)
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

    // MARK: - `[[note]]` links. Embedded task cards and `[[task]]` links are `embeds` ([[T-5120]]).

    /// [[T-6461]]: a `[[note]]` link opens the note where every other note link goes (the Notes
    /// page, or a list note's own Notes tab) — [[T-5180]]'s `NotePanel` route. Leaving the Focus
    /// page does not stop the session: the timer is `FocusManager.shared`'s, not this view's.
    private func openNoteReference(id: UUID?, title: String) {
        guard let note = TaskNoteLinkRouting.note(id: id, title: title, in: referenceNotes) else { return }
        TaskNoteLinkRouting.open(note)
    }
}

#endif
