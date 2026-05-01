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
            get: {
                if let a = task.area    { return .area(a.id) }
                if let p = task.project { return .project(p.id) }
                return .inbox
            },
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
                        task.project = project; task.area = nil; task.context = project.context; task.sectionName = project.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                }
            }
        )
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
                        taskContainerBinding: taskContainerBinding
                    )

                    TaskInspectorSectionGroup(
                        title: "Overview",
                        subtitle: "Schedule, placement, and workflow in one compact view."
                    ) {
                        TaskDetailCompactOverviewSection(
                            task: task,
                            contexts: contexts,
                            areas: areas,
                            projects: projects,
                            taskContainerBinding: taskContainerBinding,
                            availableSections: availableSections
                        )
                    }

                    TaskInspectorSectionGroup(
                        title: "Notes",
                        subtitle: "Context and details."
                    ) {
                        TagPickerControl(
                            selectedTags: taskTagsBinding,
                            allTags: tags,
                            placeholder: "Tags",
                            onCreateTag: createTag
                        )
                        TaskDetailNotesSection(task: task)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title.isEmpty ? "Untitled task" : task.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Text("Add subtasks")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }
                }

                TaskInspectorSectionGroup(
                    title: "Subtasks",
                    subtitle: "Checklist for this task."
                ) {
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
                                modelContext.delete(subtask)
                            }
                        }
                    )
                }

                if presentationMode == .full {
                    TaskInspectorSectionGroup(title: "Actions") {
                        TaskDetailActionsSection(task: task)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: presentationMode == .subtasksOnly ? 332 : 360)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
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

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = (task.subtasks ?? []).count
        let subtask = Subtask(title: trimmed)
        subtask.parentTask = task
        subtask.order = existing
        modelContext.insert(subtask)
        newSubtaskTitle = ""
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

    private func createTag(_ name: String) -> Tag {
        TagSupport.resolveTags(named: [name], in: modelContext).first ?? Tag(name: name)
    }
}
#endif
