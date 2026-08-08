#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct TaskDetailNotesSection: View {
    @Bindable var task: AppTask
    @Query(sort: \AppTask.order) private var referenceTasks: [AppTask]
    @State private var editorContent = ""
    @State private var loadedTaskID: UUID?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            MarkdownEditor(
                text: taskNotesBinding,
                showsToolbar: false,
                referenceTasks: referenceTasks,
                onEditingChanged: handleEditorFocusChange
            )
                // MarkdownEditor has no intrinsic content size — it fills exactly what it is
                // given — so this height IS the notes box, not a floor it grows from.
                .frame(minHeight: 120)
                .background(Theme.surfaceRecessed)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if displayedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Add notes…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim.opacity(0.6))
                    .padding(.leading, MarkdownEditorMetrics.firstTextColumnInset)
                    .padding(.top, MarkdownEditorMetrics.textInset)
                    .allowsHitTesting(false)
            }

            Button {
                TaskNotesPanelController.shared.show(task: task, referenceTasks: referenceTasks)
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
            .help("Open task notes")
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
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
                .help("Close")
            ),
            showsExpandButton: false
        )
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 680)
        .background(Theme.surface)
    }
}

@MainActor
final class TaskNotesPanelController: NSObject, NSWindowDelegate {
    static let shared = TaskNotesPanelController()

    private var panel: TaskNotesPanel?
    private var hostingView: TaskNotesHostingView?

    private override init() {}

    func show(task: AppTask, referenceNotes: [Note] = [], referenceTasks: [AppTask] = []) {
        let panel = ensurePanel()
        let content = TaskNotesExpandedEditorSheet(
            task: task,
            referenceNotes: referenceNotes,
            referenceTasks: referenceTasks,
            onClose: { [weak self] in self?.close() }
        )
        .modelContainer(PersistenceController.shared.container)
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

        panel.title = "Task notes"
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
        }
    }
}

struct TaskDetailActionsSection: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager

    private static let controlHeight: CGFloat = 32
    private static let cornerRadius: CGFloat = 7

    var body: some View {
        // One row: a flexible primary action plus two square icon buttons. The old layout used
        // three equal-width text buttons, which forced "Unschedule" to wrap mid-word.
        HStack(spacing: 8) {
            Button {
                if task.isDone {
                    TaskWorkflowService.markTodo(task)
                } else {
                    TaskWorkflowService.markDone(task, in: modelContext)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: task.isDone ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(task.isDone ? "Mark not done" : "Mark done")
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

            if task.scheduledStartMin >= 0 {
                iconButton(
                    systemImage: "calendar.badge.minus",
                    tint: Theme.dim,
                    help: "Unschedule"
                ) {
                    SchedulingActions.removeFromCalendar(task)
                    task.scheduledStartMin = -1
                    task.scheduledDate = ""
                }
            }

            iconButton(systemImage: "trash", tint: Theme.red, help: "Delete task") {
                deleteConfirmationManager.present(
                    title: "Delete Task?",
                    message: "This will permanently delete \"\(TaskTitleSupport.displayTitle(task.title, fallback: "Untitled"))\"."
                ) {
                    modelContext.deleteTask(task)
                }
            }
        }
    }

    @ViewBuilder
    private func iconButton(
        systemImage: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .help(help)
    }
}
#endif
