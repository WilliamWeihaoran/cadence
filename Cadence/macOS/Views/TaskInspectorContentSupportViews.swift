#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct TaskDetailNotesSection: View {
    @Bindable var task: AppTask
    var flush: TaskInspectorNotesFlush? = nil
    @Query(sort: \AppTask.order) private var referenceTasks: [AppTask]
    /// [[T-5061]]: what `[[note]]` links in these notes resolve against — the same query and order
    /// the Notes page and `EventNoteEditorSheet` use.
    @Query(sort: \Note.updatedAt, order: .reverse) private var referenceNotes: [Note]
    @State private var editorContent = ""
    @State private var loadedTaskID: UUID?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?
    /// [[T-7810]]: when the oldest edit the pending fallback commit carries was made; only
    /// meaningful while `pendingFallbackContentSyncTask` is non-nil.
    @State private var fallbackContentWindowStart: Date?
    /// [[T-7811]]: this editor's key in `MarkdownEditorTerminationFlush`.
    @State private var terminationFlushID = UUID()
    @Environment(\.modelContext) private var modelContext
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    /// The live-card embed handlers, shared with `TaskNoteEditorPane` and `FocusNotesPanel`
    /// ([[T-5120]]).
    @State private var embeds = TaskNotesEmbedHandlers(hoverIDPrefix: "task-inspector-note-embed-task-")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // T-5014: `referenceTasks` makes embeds draw as live cards, so every card and
                // `[[task]]` link handler is passed too — the one set `TaskNoteEditorPane` and
                // `FocusNotesPanel` use ([[T-5120]]). Without them the closures default to no-ops
                // and a ticked card checkbox did nothing.
                let embedScope = TaskNotesEmbedScope(referenceTasks: referenceTasks, ownerTask: task, modelContext: modelContext)
                let embedCallbacks = embeds.callbacks(
                    in: embedScope,
                    hoveredTaskManager: hoveredTaskManager,
                    hoveredEditableManager: hoveredEditableManager
                )
                MarkdownEditor(
                    text: taskNotesBinding,
                    showsToolbar: false,
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
                    // MarkdownEditor has no intrinsic content size — it fills exactly what it is
                    // given — so this height IS the notes box, not a floor it grows from.
                    .frame(minHeight: 120)
                    .background(Theme.surfaceRecessed)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .taskNotesEmbedPopovers(embeds, scope: embedScope)

                if displayedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add notes…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim.opacity(0.6))
                        .padding(.leading, MarkdownEditorMetrics.firstTextColumnInset)
                        .padding(.top, MarkdownEditorMetrics.textInset)
                        .allowsHitTesting(false)
                }

                Button {
                    TaskNotesPanelController.shared.show(
                        task: task,
                        referenceNotes: referenceNotes,
                        referenceTasks: referenceTasks
                    )
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 24, height: 22)
                        .background(Theme.surfaceElevated.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel("Open task notes")
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }

            // Under the box rather than over the card: the card is drawn by the text view, so
            // there is nothing in SwiftUI's tree to attach a notice to at the point of refusal.
            if let embeddedTaskFailureNotice = embeds.embeddedTaskFailureNotice {
                CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { embeds.embeddedTaskFailureNotice = nil }
            }
        }
        .onAppear {
            loadEditorStateIfNeeded(force: true)
            flush?.action = flushPendingEditorContent
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
            flush?.action = nil
            pendingFallbackContentSyncTask?.cancel()
            pendingFallbackContentSyncTask = nil
        }
    }

    private var displayedNotes: String {
        loadedTaskID == task.id ? editorContent : task.notes
    }

    private var taskNotesBinding: Binding<String> {
        Binding(
            get: { displayedNotes },
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

    /// [[T-5061]]: a `[[note]]` link opens the note where the rest of the Mac app opens it.
    private func openNoteReference(id: UUID?, title: String) {
        guard let note = TaskNoteLinkRouting.note(id: id, title: title, in: referenceNotes) else { return }
        TaskNoteLinkRouting.open(note)
    }
}

struct TaskNotesExpandedEditorSheet: View {
    @Bindable var task: AppTask
    var referenceNotes: [Note] = []
    var referenceTasks: [AppTask] = []
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TaskNoteEditorPane(
            task: task,
            relatedNotes: referenceNotes,
            relatedTasks: referenceTasks,
            // [[T-5061]]: the pane's default is a no-op, so a resolved note link went nowhere.
            onOpenNote: { TaskNoteLinkRouting.open($0) },
            trailingToolbarAccessory: AnyView(
                Button {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 30, height: 30)
                        .background(Theme.surfaceElevated.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel("Close")
            ),
            showsExpandButton: false
        )
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 680)
        .background(Theme.surface)
    }
}

/// [[T-5061]]: where a `[[note]]` link clicked in a task's notes goes, from a host that is not
/// itself a notes page (the inspector box, the floating Task Notes panel, the Today note panel,
/// and — through `openDismissing` — the meeting-note sheet, [[T-5151]]).
///
/// A standalone note takes the route global search takes — `NotesNavigationManager.openNote`, which
/// `macOSRootView` answers by selecting the Notes page. A `.list` note has no Notes page; it opens
/// its list's Notes tab through `ListNavigationManager` **with that note selected** — the
/// `listNoteID:` overload global search uses ([[T-3084]]). Without the id the tab selected whatever
/// document it reached first ([[T-6092]]).
enum TaskNoteLinkRouting {
    /// Same resolution as `TaskNoteEditorPane.openNoteReference`: the id first, then the title.
    static func note(id: UUID?, title: String, in notes: [Note]) -> Note? {
        if let id, let note = notes.first(where: { $0.id == id }) {
            return note
        }
        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty else { return nil }
        return notes.first { $0.displayTitle.caseInsensitiveCompare(targetTitle) == .orderedSame }
    }

    static func open(
        _ note: Note,
        notesNavigation: NotesNavigationManager = .shared,
        listNavigation: ListNavigationManager = .shared
    ) {
        guard note.kind == .list else {
            notesNavigation.openNote(id: note.id, kind: note.kind)
            return
        }
        if let project = note.project {
            listNavigation.open(projectID: project.id, page: .documents, listNoteID: note.id)
        } else if let area = note.area {
            listNavigation.open(areaID: area.id, page: .documents, listNoteID: note.id)
        }
    }

    /// [[T-5151]] (b): a link clicked inside a modal sheet (the meeting-note sheet) closes the
    /// sheet first, then takes the same route as `open` — the owner's 2026-10-24 decision, so a
    /// note link never stays trapped behind the modal it was clicked in.
    static func openDismissing(
        _ note: Note,
        dismiss: () -> Void,
        notesNavigation: NotesNavigationManager = .shared,
        listNavigation: ListNavigationManager = .shared
    ) {
        dismiss()
        open(note, notesNavigation: notesNavigation, listNavigation: listNavigation)
    }
}

@MainActor
final class TaskNotesPanelController: NSObject, NSWindowDelegate {
    static let shared = TaskNotesPanelController()

    private var panel: TaskNotesPanel?
    private var hostingView: TaskNotesHostingView?

    private override init() {}

    func show(task: AppTask, referenceNotes: [Note] = [], referenceTasks: [AppTask] = []) {
        // T-817: `container` is `nil` only on a launch degraded enough that no `AppTask` this
        // panel could be asked to open even exists to have been fetched — but the type is
        // optional now, so this stays a guard rather than a force unwrap.
        guard let container = PersistenceController.shared.container else { return }

        let panel = ensurePanel()
        let content = TaskNotesExpandedEditorSheet(
            task: task,
            referenceNotes: referenceNotes,
            referenceTasks: referenceTasks,
            onClose: { [weak self] in self?.close() }
        )
        .modelContainer(container)
        .environment(CadenceDeepLinkManager.shared)
        .environment(CalendarManager.shared)
        .environment(AISettingsManager.shared)
        .environment(AppleAccountManager.shared)
        .environment(FocusManager.shared)
        .environment(DeleteConfirmationManager.shared)
        .environment(HoveredTaskManager.shared)
        .environment(HoveredEditableManager.shared)
        .environment(HoveredKanbanColumnManager.shared)
        .environment(HoveredSectionManager.shared)
        .environment(HoveredTaskDatePickerManager.shared)
        .environment(TaskCompletionAnimationManager.shared)
        .environment(SectionCompletionAnimationManager.shared)
        .environment(TaskCreationManager.shared)
        .environment(TodayTimelineFocusManager.shared)
        .environment(GlobalSearchManager.shared)
        .environment(ListNavigationManager.shared)
        .environment(NotesNavigationManager.shared)
        .environment(CalendarNavigationManager.shared)
        .environment(TaskSubtaskEntryManager.shared)
        .preferredColorScheme(.dark)

        let hostingView = TaskNotesHostingView(rootView: AnyView(content))
        panel.contentView = hostingView
        self.hostingView = hostingView

        if panel.frame.width < 100 || panel.frame.height < 100 {
            panel.setFrame(NSRect(x: 0, y: 0, width: 900, height: 680), display: false)
            panel.center()
        }

        panel.title = "Task Notes"
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        hostingView = nil
    }

    private func ensurePanel() -> TaskNotesPanel {
        if let panel { return panel }

        let panel = TaskNotesPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .managed]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 560, height: 360)
        panel.animationBehavior = .utilityWindow
        self.panel = panel
        return panel
    }
}

private final class TaskNotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class TaskNotesHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct TaskDetailSubtasksSection: View {
    @Bindable var task: AppTask
    @Binding var newSubtaskTitle: String
    @FocusState.Binding var subtaskFieldFocused: Bool
    let onAddSubtask: () -> Void
    let onDeleteSubtask: (Subtask) -> Void

    var body: some View {
        TaskInspectorRecessedGroup(verticalPadding: 6) {
            VStack(alignment: .leading, spacing: 2) {
                let sortedSubtasks = (task.subtasks ?? []).sorted { $0.order < $1.order }
                ForEach(sortedSubtasks) { subtask in
                    SubtaskRow(subtask: subtask, showDelete: true) {
                        onDeleteSubtask(subtask)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim.opacity(0.6))
                    TextField("Add subtask…", text: $newSubtaskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .focused($subtaskFieldFocused)
                        .onSubmit { onAddSubtask() }
                }
                .padding(.vertical, 3)
            }
            // The recessed group stopped padding its contents so field rows could hover full
            // bleed; content that isn't a field row supplies the inset itself.
            .padding(.horizontal, TaskInspectorFieldRowMetrics.groupHorizontalPadding)
        }
    }
}

/// The inspector's action row: one flexible primary ("Complete" / "Reopen", [[T-7447]]; absent on
/// a cancelled task) and square icon buttons for
/// everything else.
///
/// **Cancel/Restore is one of the icon buttons** ([[T-6231]]). [[T-5015]] (a) added it as its own
/// `TaskInspectorStatusActionsRow` under this one, a Start/Stop + Cancel/Restore pair; (b) retired
/// In Progress, and the pair became one button stretched across the inspector — a second wide
/// control directly under the primary, with the weight of the action the panel is *for*. Cancelling
/// a task is a secondary action, so it takes the secondary shape this row already had for
/// Unschedule and Delete: a 32pt square with its glyph, its name as the label and tooltip, and the
/// shared `StatusAction` copy and glyphs so it still cannot drift from iOS. The row's rule is that
/// the primary is the only control here that takes the width, and
/// `CadenceMacTaskInspectorStatusActionsTests` pins it.
struct TaskDetailActionsSection: View {
    @Bindable var task: AppTask
    var offersUnschedule = true
    var offersDelete = true
    /// The shared `CadenceTaskInspectorSupport.StatusAction` set (Cancel/Restore since [[T-5015]]
    /// (b)), as icon buttons after the primary. Off by default: the full inspector is the one host
    /// that offers it.
    var offersStatusActions = false
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager

    private static let controlHeight: CGFloat = 32
    private static let cornerRadius: CGFloat = Theme.radiusControlCompact

    /// Set when the primary (Complete / Reopen) or a status action was refused and put back (T-628). The inspector is
    /// the one surface that reaches the settle *without* going through
    /// `TaskCompletionAnimationManager`, so the root alert cannot speak for it and it says so where
    /// the button is. One notice for the row: both refusals read the same sentence.
    @State private var failureNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controlRow
            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
            }
        }
    }

    private var controlRow: some View {
        // One row: a flexible primary action plus two square icon buttons. The old layout used
        // three equal-width text buttons, which forced "Unschedule" to wrap mid-word.
        HStack(spacing: 8) {
            // [[T-7447]]: not on a cancelled task, where it said "Mark done" beside "Restore task"
            // and completed it — abandoned work turned into accomplished work (T-344). iOS hides
            // its button there too ([[T-7012]]); "Restore task" is the one way back.
            if let primaryTitle = Self.primaryTitle(for: task.status) {
                Button {
                    markDoneOrNotDone()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: task.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(primaryTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.green)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.controlHeight)
                    .background(task.isDone ? Theme.surfaceElevated : Theme.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .accessibilityLabel(CadenceTaskCompletionState.resolve(status: task.status).accessibilityActionLabel)
                .help(CadenceTaskCompletionState.resolve(status: task.status).accessibilityActionLabel)
            } else {
                // Keeps the icon buttons right-aligned where the primary used to sit.
                Spacer(minLength: 0)
            }

            if offersUnschedule && task.scheduledStartMin >= 0 {
                iconButton(
                    systemImage: "calendar.badge.minus",
                    tint: Theme.dim,
                    accessibilityLabel: "Unschedule"
                ) {
                    SchedulingActions.removeFromCalendar(task)
                    CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
                }
            }

            if offersStatusActions {
                ForEach(CadenceTaskInspectorSupport.StatusAction.allCases, id: \.self) { action in
                    statusActionButton(action)
                }
            }

            if offersDelete {
                iconButton(systemImage: "trash", tint: Theme.red, accessibilityLabel: "Delete task") {
                    deleteConfirmationManager.presentTaskDelete(task, in: modelContext)
                }
            }
        }
    }

    /// A status action as an icon button. Active (the task is already cancelled) it fills with its
    /// status's tint and says "Restore", so the button is its own undo, as on iOS.
    private func statusActionButton(_ action: CadenceTaskInspectorSupport.StatusAction) -> some View {
        let isActive = action.isActive(task.status)
        return iconButton(
            systemImage: action.systemImage(for: task.status),
            tint: isActive ? Theme.statusColor(action.status) : Theme.dim,
            accessibilityLabel: Self.statusActionLabel(action, for: task.status),
            isActive: isActive
        ) {
            do {
                try Self.apply(action, to: task, in: modelContext)
                failureNotice = nil
            } catch {
                failureNotice = CadencePendingChangePersistence.editFailureNotice
            }
        }
    }

    /// [[T-7201]]: the icon button's name and tooltip — "Cancel task" / "Restore task", the shape
    /// the Delete sibling in this row already reads ("Delete task"). The bare shared title said
    /// "Cancel", and the schedule panel's footer button directly below is also "Cancel" (discard
    /// edits), so VoiceOver and the tooltip offered two "Cancel" controls that do opposite things.
    static func statusActionLabel(
        _ action: CadenceTaskInspectorSupport.StatusAction,
        for status: TaskStatus
    ) -> String {
        "\(action.title(for: status)) task"
    }

    /// One tap: the action's target from the current status, committed, then the notification
    /// reconcile every other macOS status writer runs. A refused commit has already been put back
    /// by the shared mutation, so it throws without reconciling.
    static func apply(
        _ action: CadenceTaskInspectorSupport.StatusAction,
        to task: AppTask,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try CadenceTaskMutationSupport.setStatus(
            action.target(from: task.status),
            for: task,
            modelContext: context,
            commit: commit
        )
        HabitNotificationReconcileSupport.scheduleReconcile(in: context)
    }

    /// The primary's visible word, or `nil` where it is not drawn ([[T-7447]]).
    ///
    /// "Complete" / "Reopen" — the iOS sheet's words ([[T-7012]]) and the leading word of the
    /// shared `CadenceTaskCompletionState.accessibilityActionLabel` ("Complete task" / "Reopen
    /// task") every row's circle reads, which this button also takes as its name. It said "Mark
    /// done" / "Mark not done". A cancelled task gets none: `offersCompletionAction` is the rule
    /// iOS reads, so the two platforms cannot disagree about where the control exists.
    static func primaryTitle(for status: TaskStatus) -> String? {
        guard CadenceTaskInspectorSupport.offersCompletionAction(for: status) else { return nil }
        return status == .done ? "Reopen" : "Complete"
    }

    /// The settle, with a commit boundary and the failure named where the button is (T-628).
    ///
    /// Reopening commits before publishing its widget override reversal; finishing also owns
    /// the successor insertion's undo.
    private func markDoneOrNotDone() {
        do {
            try Self.settle(task, in: modelContext)
            failureNotice = nil
        } catch {
            failureNotice = CadencePendingChangePersistence.editFailureNotice
        }
    }

    /// The primary's tap. A cancelled task is left alone ([[T-7447]], T-344): the button is not
    /// drawn there, and this refuses as well, so a stale tap cannot complete abandoned work.
    static func settle(_ task: AppTask, in context: ModelContext) throws {
        guard CadenceTaskInspectorSupport.offersCompletionAction(for: task.status) else { return }
        if task.isDone {
            try TaskWorkflowService.commitMarkTodo(task, in: context)
        } else {
            try TaskWorkflowService.commitMarkDone(task, in: context)
        }
    }

    @ViewBuilder
    private func iconButton(
        systemImage: String,
        tint: Color,
        accessibilityLabel: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .background(isActive ? tint.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .strokeBorder(isActive ? Color.clear : Theme.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .cadenceControlLabel(accessibilityLabel)
    }
}

/// The MarkdownEditor owns an unsent text buffer. Save flushes that buffer before reading the
/// live notes into the schedule commit; focus-loss delivery alone can arrive after dismissal.
@MainActor
final class TaskInspectorNotesFlush {
    var action: (@MainActor () -> Void)?
    func flush() { action?() }
}

/// The full macOS inspector's schedule form, using the same panel and edit commit as iOS and
/// the inline note inspector. Record actions in `content` retain their own commits.
struct TaskInspectorScheduleEditor<Content: View>: View {
    @Bindable var task: AppTask
    let beforeSave: () -> Bool
    let content: () -> Content
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @State private var draft: CadenceScheduleDraft

    init(task: AppTask, beforeSave: @escaping () -> Bool, @ViewBuilder content: @escaping () -> Content) {
        _task = Bindable(wrappedValue: task)
        self.beforeSave = beforeSave
        self.content = content
        _draft = State(initialValue: CadenceScheduleDraft(editing: task))
    }

    private var selection: TaskContainerSelection {
        CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
    }

    private var selectedArea: Area? {
        guard let id = CadenceTaskComposerSupport.selectedAreaID(selection) else { return nil }
        return areas.first { $0.id == id }
    }

    private var selectedProject: Project? {
        guard let id = CadenceTaskComposerSupport.selectedProjectID(selection) else { return nil }
        return projects.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            CadenceSchedulePanel(
                draft: $draft,
                listChoices: CadenceSchedulePanelChoice.editableTaskListChoices(
                    areas: areas, projects: projects, selection: selection
                ),
                sectionChoices: CadenceTaskMutationSupport.sectionNames(forArea: selectedArea, project: selectedProject),
                titleStatus: CadenceSchedulePanelTitleStatus(
                    // Cancelled alone since [[T-5015]] (b) retired In Progress; the sibling
                    // eyebrows in `iOSTaskDetailSheet` and `CadenceTaskInlinePanel` read the same.
                    eyebrow: task.isCancelled ? task.status.label : nil,
                    eyebrowTint: CadenceTaskPresentationSupport.statusColor(task.status),
                    isSettled: CadenceTaskCompletionState.resolve(task: task).isSettled
                ),
                // The host's recurrence control includes its existing end and scope picker.
                offersTaskRepeat: false,
                actions: CadenceSchedulePanelActions(
                    commit: save,
                    cancel: { dismiss() },
                    delete: {
                        deleteConfirmationManager.presentTaskDelete(task, in: modelContext)
                        return nil
                    }
                ),
                notesField: content
            )
        }
        .frame(maxHeight: 720)
        .cadenceFixedTypography()
        // [[T-6191]]: an After count stored below this occurrence before [[T-6114]]'s floor is
        // repaired when the task is opened, and only then. A coherent count is not written.
        .onAppear { CadenceTaskRecurrenceWorkflowSupport.repairEndCountOnOpen(task, in: modelContext) }
        .onChange(of: task.statusRaw) { _, _ in draft.isDone = task.isDone }
        // No `.onChange(of: draft.listToken)` here: the panel reconciles the Section row itself,
        // over the `sectionChoices` above ([[T-8591]], host copy removed under [[T-8601]]).
    }

    private func save() -> String? {
        guard beforeSave() else { return CadenceTaskInspectorSupport.subtaskAddFailureNotice }
        guard TaskInspectorScheduleCommit.save(
            draft, to: task, areas: areas, projects: projects, allTasks: allTasks,
            in: modelContext, commit: { try $0.save() }
        ) else { return CadenceTaskFieldEditCommit.saveFailureNotice }
        dismiss()
        return nil
    }
}

/// The host edits recurrence and notes through existing record controls. Read those fields at
/// Save, after the markdown flush, so a schedule edit cannot restore their opening values.
@MainActor
enum TaskInspectorScheduleCommit {
    static func save(
        _ draft: CadenceScheduleDraft,
        to task: AppTask,
        areas: [Area],
        projects: [Project],
        allTasks: [AppTask],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void
    ) -> Bool {
        let selection = CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
        let area = areas.first { $0.id == CadenceTaskComposerSupport.selectedAreaID(selection) }
        let project = projects.first { $0.id == CadenceTaskComposerSupport.selectedProjectID(selection) }
        if CadenceTaskComposerSupport.selectedAreaID(selection) != nil && area == nil { return false }
        if CadenceTaskComposerSupport.selectedProjectID(selection) != nil && project == nil { return false }
        let current = CadenceScheduleDraft(editing: task)
        var payload = draft
        payload.notes = task.notes
        payload.repeatRule = current.repeatRule
        payload.seriesEndMode = current.seriesEndMode
        payload.seriesEndDateKey = current.seriesEndDateKey
        payload.seriesEndCount = current.seriesEndCount
        payload.seriesOccurrenceNumber = current.seriesOccurrenceNumber
        payload.isDone = current.isDone
        let clearsSchedule = (payload.startDateKey.isEmpty && !current.startDateKey.isEmpty)
            || (payload.scheduledStartMin < 0 && current.scheduledStartMin >= 0)
        return CadenceTaskEditDraftCommit.save(
            payload, opened: current, to: task, area: area, project: project,
            allTasks: allTasks, scope: .thisTask, in: modelContext,
            commit: { context in
                // The old Unschedule action also retired this legacy link. Stay inside the
                // field snapshot's commit so a refusal restores the link with the schedule.
                if clearsSchedule { SchedulingActions.removeFromCalendar(task) }
                try commit(context)
            }
        )
    }

    static func setTags(
        _ tags: [Tag], on task: AppTask, in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void
    ) -> Bool {
        let restored = task.tags
        task.tags = TagSupport.sorted(tags)
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit, undo: {
                task.tags = restored
            })
            return true
        } catch { return false }
    }
}
#endif
