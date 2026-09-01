#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct TaskDetailPopover: View {
    @Bindable var task: AppTask
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Tag.order)     private var tags:     [Tag]
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(TaskSubtaskEntryManager.self) private var taskSubtaskEntryManager

    @State private var showPriorityPicker = false
    @State private var newSubtaskTitle = ""
    /// Set when a subtask insert or delete was refused by the store. See `addSubtask()`.
    @State private var subtaskFailureNotice: String?
    /// Set when the store refused a tag created from the header's picker. See `createTag(_:)`.
    @State private var tagFailureNotice: String?
    @State private var presentationMode: TaskDetailPresentationMode = .full
    @FocusState private var subtaskFieldFocused: Bool

    private var availableSections: [String] {
        switch taskContainerBinding.wrappedValue {
        case .inbox:
            return [TaskSectionDefaults.defaultName]
        case .area(let id):
            return areas.first(where: { $0.id == id })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        case .project(let id):
            return projects.first(where: { $0.id == id })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        }
    }

    private var taskContainerBinding: Binding<TaskContainerSelection> {
        Binding(
            get: { CadenceTaskComposerSupport.container(of: task) },
            set: { newSelection in
                switch newSelection {
                case .inbox:
                    task.area = nil; task.project = nil; task.context = nil; task.sectionName = TaskSectionDefaults.defaultName
                case .area(let id):
                    if let area = areas.first(where: { $0.id == id }) {
                        task.area = area; task.project = nil; task.context = area.context; task.sectionName = area.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                case .project(let id):
                    if let project = projects.first(where: { $0.id == id }) {
                        task.project = project; task.area = nil; task.context = project.resolvedContext; task.sectionName = project.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                }
            }
        )
    }

    /// "1/3" beside the SUBTASKS heading; nil (and so omitted) when there are no subtasks.
    private var subtaskProgressLabel: String? {
        CadenceTaskPresentationSupport.subtaskProgress(for: task)?.compactLabel
    }

    private var taskTagsBinding: Binding<[Tag]> {
        Binding(
            get: { task.tags ?? [] },
            set: { task.tags = TagSupport.sorted($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if presentationMode == .full {
                    TaskDetailHeaderSection(
                        task: task,
                        showPriorityPicker: $showPriorityPicker,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        tags: tags,
                        taskContainerBinding: taskContainerBinding,
                        taskTagsBinding: taskTagsBinding,
                        availableSections: availableSections,
                        onCreateTag: createTag
                    )

                    if let tagFailureNotice {
                        CadenceInlineFailureNotice(text: tagFailureNotice)
                    }

                    TaskDetailScheduleGroupSection(task: task)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        // **T-513.** `TaskTitleSupport.defaultDisplayTitle`, so the compact
                        // inspector's title agrees with the ~18 other surfaces that show a
                        // blank-titled task. It read "Untitled task" against the constant's capital.
                        Text(task.title.isEmpty ? TaskTitleSupport.defaultDisplayTitle : task.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Text("Add subtasks")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }
                }

                TaskInspectorSectionGroup(title: "Subtasks", trailing: subtaskProgressLabel) {
                    TaskDetailSubtasksSection(
                        task: task,
                        newSubtaskTitle: $newSubtaskTitle,
                        subtaskFieldFocused: $subtaskFieldFocused,
                        onAddSubtask: addSubtask,
                        onDeleteSubtask: { subtask in
                            deleteConfirmationManager.present(
                                title: "Delete Subtask?",
                                message: "This will permanently delete \"\(subtask.title.isEmpty ? "Untitled" : subtask.title)\"."
                            ) {
                                deleteSubtask(subtask)
                            }
                        }
                    )

                    if let subtaskFailureNotice {
                        CadenceInlineFailureNotice(text: subtaskFailureNotice)
                    }
                }

                if presentationMode == .full {
                    TaskInspectorSectionGroup(title: "Notes") {
                        TaskDetailNotesSection(task: task)
                    }

                    // No "Actions" heading: a label over two buttons at the foot of the panel
                    // names something the buttons already say.
                    TaskDetailActionsSection(task: task)
                }
            }
            .padding(14)
        }
        // Both presentation modes share one width now that the field rows drive the layout.
        .frame(width: 336)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
        )
        .onAppear {
            focusSubtaskFieldIfRequested()
        }
        .onChange(of: taskSubtaskEntryManager.requestedTaskID) { _, _ in
            focusSubtaskFieldIfRequested()
        }
        .onChange(of: taskContainerBinding.wrappedValue) { _, _ in
            normalizeTaskSectionSelection()
        }
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
    /// `deleteSubtask` had also *edited* `task.subtasks` to drop it, and a rollback's undo of an
    /// edit is invisible until something refetches (T-402). So the row would come off the screen
    /// and stay in the store: gone until the next launch brought it back. Pinned by
    /// `arefusedSubtaskDeleteLeavesTheRowMissingFromTheParentUntilTheCallerPutsItBack`.
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

    private func normalizeTaskSectionSelection() {
        let cleaned = availableSections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let validSections = cleaned.isEmpty ? [TaskSectionDefaults.defaultName] : cleaned
        if !validSections.contains(where: { $0.caseInsensitiveCompare(task.sectionName) == .orderedSame }) {
            task.sectionName = validSections.first ?? TaskSectionDefaults.defaultName
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
