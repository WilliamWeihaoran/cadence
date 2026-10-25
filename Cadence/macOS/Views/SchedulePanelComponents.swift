#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct TaskDetailPopover: View {
    @Bindable var task: AppTask
    @Query(sort: \Tag.order)     private var tags:     [Tag]
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(TaskSubtaskEntryManager.self) private var taskSubtaskEntryManager

    @State private var notesFlush = TaskInspectorNotesFlush()
    @State private var newSubtaskTitle = ""
    /// Set when a subtask insert or delete was refused by the store. See `addSubtask()`.
    @State private var subtaskFailureNotice: String?
    /// Set when the store refused a tag created from the header's picker. See `createTag(_:)`.
    @State private var tagFailureNotice: String?
    @State private var presentationMode: TaskDetailPresentationMode = .full
    @FocusState private var subtaskFieldFocused: Bool

    /// "1/3" beside the SUBTASKS heading; nil (and so omitted) when there are no subtasks.
    private var subtaskProgressLabel: String? {
        CadenceTaskPresentationSupport.subtaskProgress(for: task)?.compactLabel
    }

    private var taskTagsBinding: Binding<[Tag]> {
        Binding(
            get: { task.tags ?? [] },
            set: {
                tagFailureNotice = TaskInspectorScheduleCommit.setTags(
                    $0, on: task, in: modelContext, commit: { try $0.save() }
                ) ? nil : CadenceTaskFieldEditCommit.saveFailureNotice
            }
        )
    }

    var body: some View {
        Group {
            if presentationMode == .full {
                TaskInspectorScheduleEditor(task: task, beforeSave: prepareToSave) {
                    recordSections
                }
                .id(task.id)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TaskTitleSupport.displayTitle(task.title))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Text("Add subtasks")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                    subtasksSection
                }
                .padding(TaskInspectorPopoverMetrics.contentInset)
            }
        }
        .frame(width: TaskInspectorPopoverMetrics.width)
        .cadenceFixedTypography()
        .background(Theme.surface)
        .onAppear { focusSubtaskFieldIfRequested() }
        .onChange(of: taskSubtaskEntryManager.requestedTaskID) { _, _ in
            focusSubtaskFieldIfRequested()
        }
    }

    /// Record actions keep their existing immediate commit boundaries; the panel owns the draft
    /// of the task's title, placement and schedule. Recurrence keeps its own scope picker.
    private var recordSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            TagPickerControl(
                selectedTags: taskTagsBinding,
                allTags: tags,
                onCreateTag: createTag,
                triggerSymbol: "plus"
            )
            if let tagFailureNotice { CadenceInlineFailureNotice(text: tagFailureNotice) }
            TaskInspectorRecurrenceControl(task: task, childPlacement: .besideInspector)
            subtasksSection
            TaskInspectorSectionGroup(title: "Notes") {
                TaskDetailNotesSection(task: task, flush: notesFlush)
            }
            TaskDetailActionsSection(task: task, offersUnschedule: false, offersDelete: false, offersStatusActions: true)
        }
    }

    private var subtasksSection: some View {
        TaskInspectorSectionGroup(title: "Subtasks", trailing: subtaskProgressLabel) {
            TaskDetailSubtasksSection(
                task: task,
                newSubtaskTitle: $newSubtaskTitle,
                subtaskFieldFocused: $subtaskFieldFocused,
                onAddSubtask: addSubtask,
                onDeleteSubtask: { subtask in
                    deleteConfirmationManager.present(
                        title: "Delete Subtask?",
                        message: "This will permanently delete \"\(TaskTitleSupport.displayTitle(subtask.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))\"."
                    ) { deleteSubtask(subtask) }
                }
            )
            if let subtaskFailureNotice { CadenceInlineFailureNotice(text: subtaskFailureNotice) }
        }
    }

    /// Flush the markdown well synchronously, and submit an unfinished checklist entry before
    /// Save can close the popover. A refused insert retains the text and keeps the form open.
    private func prepareToSave() -> Bool {
        notesFlush.flush()
        guard !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        addSubtask()
        return subtaskFailureNotice == nil
    }

    /// **T-634.** This reached no commit at all, and cleared the field regardless.
    ///
    /// `insertSubtask` is handed a `ModelContext`, so by the `try? save()` rule its caller owns the
    /// unit of work — and this popover is presented from seven surfaces, none of which committed
    /// on its behalf. The subtask sat pending until some unrelated screen's save happened to take
    /// it, or a `rollback()` threw it away, while the emptied field said it had landed.
    ///
    /// `restored` is the `CadenceListEditSnapshot` idiom shrunk to its one field. `commitInsert`'s
    /// own undo deletes the row it inserted, but `insertSubtask` had also appended it to
    /// `task.subtasks`, and that delete does not reach the array before this popover re-renders —
    /// measured by `arefusedSubtaskInsertLeavesAPhantomOnTheParentUntilTheCallerDropsIt`. Without
    /// the restore a refused insert leaves a subtask row on screen that no longer exists anywhere.
    private func addSubtask() {
        let restored = task.subtasks ?? []
        guard let inserted = CadenceTaskMutationSupport.insertSubtask(
            titled: newSubtaskTitle,
            into: task,
            modelContext: modelContext
        ) else { return }
        do {
            try CadencePendingChangePersistence.commitInsert(of: inserted, in: modelContext)
        } catch {
            task.subtasks = restored
            subtaskFailureNotice = CadenceTaskInspectorSupport.subtaskAddFailureNotice
            return
        }
        subtaskFailureNotice = nil
        newSubtaskTitle = ""
    }

    /// The delete half of T-634, and the mirror image of the restore above.
    ///
    /// `commitDelete` undoes with `rollback()`, which un-deletes the row in the store — but
    /// `deleteSubtask` had also *edited* `task.subtasks` to drop it, and through Xcode 26 a
    /// rollback's undo of an edit was invisible until something refetched (T-402). So the row came
    /// off the screen and stayed in the store: gone until the next launch brought it back.
    /// **Xcode 27 restores the relationship immediately** (T-1279), which makes re-applying
    /// `restored` an idempotent no-op rather than the repair — pinned, both halves, by
    /// `arefusedSubtaskDeleteIsRepairedByTheCapturedArrayOnEveryToolchain`. It stays
    /// for the reason that never depended on refresh timing: `commitDelete` rolls back the one
    /// app-wide `ModelContext`, so re-applying this parent's own array is how *this* caller repairs
    /// *its* object without depending on what else the rollback swept up.
    ///
    /// **[[T-1280]] asked that of every captured-array repair in the mutation support and kept all
    /// of them.** This line and its twin in `iOSTaskDetailSheet.deleteSubtask` are the only two
    /// that sit under a `rollback()` at all, so they are the only two Xcode 27 could have made
    /// redundant. Every other captured array is guarded by `commitInsert`, whose undo is
    /// `delete(model)` and never reaches the parent's array (the T-296 window, pinned by
    /// `arefusedSubtaskInsertLeavesAPhantomOnTheParentUntilTheCallerDropsIt`), or by `commitEdit`,
    /// where putting the array back *is* the undo — neither shape has anything to do with a
    /// rollback's timing. And the floor is whichever Xcode a contributor has: on 26 this line is
    /// still the repair, so deleting it on 27's behalf is a regression rather than a cleanup.
    private func deleteSubtask(_ subtask: Subtask) {
        let restored = task.subtasks ?? []
        CadenceTaskMutationSupport.deleteSubtask(subtask, parent: task, modelContext: modelContext)
        do {
            try CadencePendingChangePersistence.commitDelete(in: modelContext)
        } catch {
            task.subtasks = restored
            subtaskFailureNotice = CadenceTaskInspectorSupport.subtaskDeleteFailureNotice
            return
        }
        subtaskFailureNotice = nil
    }

    private func focusSubtaskFieldIfRequested() {
        guard taskSubtaskEntryManager.consumeIfMatches(taskID: task.id) else { return }
        presentationMode = .subtasksOnly
        DispatchQueue.main.async {
            subtaskFieldFocused = true
        }
    }

    /// **T-631**, and the third spelling of `addSubtask`'s sentence in this one popover: the
    /// inspector reached for its ambient `ModelContext`, inserted a `Tag` one frame down in
    /// `TagSupport.resolveTags`, and committed nothing. The tag sat pending behind whatever the
    /// user did next, and the picker drew a chip for it either way.
    ///
    /// The notice sits under the header section rather than beside the chips, next to the one
    /// `addSubtask` and `deleteSubtask` already use, so the popover has one place it says a write
    /// was refused.
    private func createTag(_ name: String) -> Tag? {
        guard let tag = TagSupport.committedTag(named: name, in: modelContext) else {
            tagFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return nil
        }
        tagFailureNotice = nil
        return tag
    }
}
#endif
