#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct TaskDetailNotesSection: View {
    @Bindable var task: AppTask

    var body: some View {
        TaskInspectorInfoCard {
            ZStack(alignment: .topLeading) {
                MarkdownEditor(text: Binding(
                    get: { task.notes },
                    set: { task.notes = $0 }
                ), showsToolbar: false)
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
