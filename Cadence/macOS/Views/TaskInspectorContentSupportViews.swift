#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct TaskDetailNotesSection: View {
    @Bindable var task: AppTask
    @Query(sort: \AppTask.order) private var referenceTasks: [AppTask]

    var body: some View {
        TaskInspectorInfoCard {
            VStack(spacing: 6) {
                HStack {
                    Spacer()
                    Button {
                        TaskNotesPanelController.shared.show(task: task, referenceTasks: referenceTasks)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.cadencePlain)
                    .help("Open task notes")
                }

                ZStack(alignment: .topLeading) {
                    MarkdownEditor(text: taskNotesBinding, showsToolbar: false, referenceTasks: referenceTasks)
                        .frame(minHeight: 120)
                        .background(Theme.surface.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add notes...")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.dim.opacity(0.6))
                            .padding(.leading, MarkdownEditorMetrics.firstTextColumnInset)
                            .padding(.top, MarkdownEditorMetrics.textInset)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var taskNotesBinding: Binding<String> {
        Binding(
            get: { task.notes },
            set: { task.notes = $0 }
        )
    }
}

struct TaskNotesExpandedEditorSheet: View {
    @Bindable var task: AppTask
    var referenceNotes: [Note] = []
    var referenceTasks: [AppTask] = []
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : task.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("Task notes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
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
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().background(Theme.borderSubtle)

            MarkdownEditor(
                text: Binding(
                    get: { task.notes },
                    set: { task.notes = $0 }
                ),
                referenceNotes: referenceNotes,
                referenceTasks: referenceTasks
            )
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 680)
        .background(Theme.bg)
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
        TaskInspectorInfoCard {
            VStack(alignment: .leading, spacing: 4) {
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
                    TextField("Add subtask...", text: $newSubtaskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .focused($subtaskFieldFocused)
                        .onSubmit { onAddSubtask() }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }
}

struct TaskDetailActionsSection: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if task.isDone {
                    TaskWorkflowService.markTodo(task)
                } else {
                    TaskWorkflowService.markDone(task, in: modelContext)
                }
            } label: {
                Label(task.isDone ? "Unmark Done" : "Mark Done",
                      systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)

            if task.scheduledStartMin >= 0 {
                Button {
                    SchedulingActions.removeFromCalendar(task)
                    task.scheduledStartMin = -1
                    task.scheduledDate = ""
                } label: {
                    Label("Unschedule", systemImage: "calendar.badge.minus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
            }

            Button {
                copyTaskReference()
            } label: {
                Label("Copy Ref", systemImage: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)
        }
    }

    private func copyTaskReference() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(NoteReferenceParser.taskReferenceMarkdown(for: task), forType: .string)
    }
}
#endif
