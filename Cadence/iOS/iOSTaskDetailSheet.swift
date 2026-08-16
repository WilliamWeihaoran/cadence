#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTaskDetailSheet: View {
    @Bindable var task: AppTask
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Goal.order) private var goals: [Goal]
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var newSubtaskTitle = ""
    @State private var newTagName = ""
    @State private var scheduledDate = Date()
    @State private var dueDate = Date()
    @State private var hasScheduledDate = false
    @State private var hasDueDate = false
    @State private var containerSelection = "inbox"
    @State private var showDeleteConfirmation = false
    @State private var isNotesFocused = false
    @State private var pendingRecurrenceRule: TaskRecurrenceRule?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    private var sortedSubtasks: [Subtask] {
        (task.subtasks ?? []).sorted { $0.order < $1.order }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var availableGoals: [Goal] {
        let openGoals = goals.filter { $0.status != .done }
        guard let currentGoal = task.goal,
              !openGoals.contains(where: { $0.id == currentGoal.id })
        else { return openGoals }
        return openGoals + [currentGoal]
    }

    private var availableSectionNames: [String] {
        CadenceTaskMutationSupport.sectionNames(forArea: selectedArea, project: selectedProject)
    }

    private var selectedAreaID: UUID? {
        guard containerSelection.hasPrefix("area:") else { return nil }
        return UUID(uuidString: String(containerSelection.dropFirst(5)))
    }

    private var selectedProjectID: UUID? {
        guard containerSelection.hasPrefix("project:") else { return nil }
        return UUID(uuidString: String(containerSelection.dropFirst(8)))
    }

    private var selectedArea: Area? {
        guard let selectedAreaID else { return nil }
        return areas.first { $0.id == selectedAreaID }
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var notesEditorMinHeight: CGFloat {
        isRegularWidth ? 360 : 340
    }

    var body: some View {
        NavigationStack {
            editorScrollView
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: initializeTaskSheet)
        .onChange(of: containerSelection) { _, _ in
            applyContainerSelection()
        }
        // No "seed today when switched on" fallback any more: nothing turns these on except a day
        // being picked, so seeding here would overwrite the day the user just chose.
        .onChange(of: hasScheduledDate) { _, _ in applyDates() }
        .onChange(of: hasDueDate) { _, _ in applyDates() }
        .onChange(of: scheduledDate) { _, _ in applyDates() }
        .onChange(of: dueDate) { _, _ in applyDates() }
        .onChange(of: task.title) { _, _ in saveTask() }
        .onChange(of: task.priorityRaw) { _, _ in saveTask() }
        .onChange(of: task.statusRaw) { _, _ in saveTask() }
        .onChange(of: task.recurrenceRaw) { _, _ in saveTask() }
        .onChange(of: task.estimatedMinutes) { _, _ in saveTask() }
        .onChange(of: task.actualMinutes) { _, _ in saveTask() }
        .onChange(of: task.sectionName) { _, _ in saveTask() }
        .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                CadenceTaskMutationSupport.delete(task, modelContext: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the task and its subtasks.")
        }
        .confirmationDialog(
            "Change repeating task?",
            isPresented: recurrenceScopeDialogPresentation,
            titleVisibility: .visible
        ) {
            Button(CadenceTaskRecurrenceEditScope.thisTask.label) {
                applyPendingRecurrenceRule(scope: .thisTask)
            }
            Button(CadenceTaskRecurrenceEditScope.thisAndFuture.label) {
                applyPendingRecurrenceRule(scope: .thisAndFuture)
            }
            Button("Cancel", role: .cancel) {
                pendingRecurrenceRule = nil
            }
        } message: {
            Text("Choose whether this repeat change applies only here or to this task and future instances.")
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
    }

    private var editorScrollView: some View {
        ScrollView {
            taskForm
                .padding(14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(isRegularWidth ? 20 : 18)
        }
        .background(Theme.bg)
        .navigationTitle("Edit Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { taskToolbar }
        .tint(Theme.blue)
    }

    /// Same order as macOS's inspector, for the same reasons: what the task *is* (title, tags,
    /// where it lives), then when it happens, then the work inside it, then its notes, then the
    /// actions that change its state.
    private var taskForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBlock
            propertiesSection
            scheduleSection
            subtasksSection
            notesSection
            statusActionsSection
        }
    }

    /// Title row, then the task's tags and its `List › Section` line indented to the title column —
    /// the same identity block `TaskDetailHeaderSection` draws on macOS.
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            iOSTaskEditorTitleCard(task: task, onToggleCompletion: toggleCompletion)

            VStack(alignment: .leading, spacing: 8) {
                iOSTaskTagStrip(task: task, allTags: tags, newTagName: $newTagName)

                iOSTaskPlacementBreadcrumb(
                    task: task,
                    containerSelection: $containerSelection,
                    activeAreas: activeAreas,
                    activeProjects: activeProjects,
                    availableSectionNames: availableSectionNames
                )
            }
            .padding(.leading, titleColumnInset)
        }
    }

    /// Completion-circle width plus the title row's spacing, so everything under the title lines up
    /// with the title text rather than with the circle.
    private var titleColumnInset: CGFloat {
        (isRegularWidth ? 26 : 24) + 12
    }

    @ToolbarContentBuilder
    private var taskToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
                finishEditingAndDismiss()
            }
        }
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
        }
    }

    private var propertiesSection: some View {
        iOSTaskPropertiesSection(task: task, availableGoals: availableGoals)
    }

    private var scheduleSection: some View {
        iOSTaskScheduleSection(
            task: task,
            recurrenceSelection: recurrenceSelection,
            hasScheduledDate: $hasScheduledDate,
            scheduledDate: $scheduledDate,
            hasDueDate: $hasDueDate,
            dueDate: $dueDate,
            scheduledStartSelection: scheduledStartSelection,
            scheduledTimeLabel: scheduledTimeLabel
        )
    }

    private var statusActionsSection: some View {
        iOSTaskStatusActionsSection(task: task) { status in
            CadenceTaskMutationSupport.setStatus(status, for: task, modelContext: modelContext)
        }
    }

    private var notesSection: some View {
        iOSTaskNotesSection(
            notesText: Binding(
                get: { task.notes },
                set: {
                    task.notes = $0
                    try? modelContext.save()
                }
            ),
            isFocused: $isNotesFocused,
            minHeight: notesEditorMinHeight,
            referenceNotes: allNotes,
            referenceTasks: allTasks,
            onOpenReference: openMarkdownReference
        )
    }

    private var subtasksSection: some View {
        iOSTaskSubtasksSection(
            subtasks: sortedSubtasks,
            newSubtaskTitle: $newSubtaskTitle,
            canAddSubtask: canAddSubtask,
            onAdd: addSubtask,
            onDelete: deleteSubtask
        )
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recurrenceSelection: Binding<TaskRecurrenceRule> {
        Binding(
            get: { task.recurrenceRule },
            set: { selectRecurrenceRule($0) }
        )
    }

    private var recurrenceScopeDialogPresentation: Binding<Bool> {
        Binding(
            get: { pendingRecurrenceRule != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRecurrenceRule = nil
                }
            }
        )
    }

    /// The time picker's own "No time" row is what clears the time, so this binding is the single
    /// control for the field — there is no separate switch beside it to fall out of step.
    private var scheduledStartSelection: Binding<Int> {
        Binding(
            get: { task.scheduledStartMin },
            set: { minutes in
                guard minutes >= 0 else {
                    CadenceTaskMutationSupport.clearScheduledTime(task, modelContext: modelContext)
                    return
                }
                if !hasScheduledDate {
                    scheduledDate = Date()
                    hasScheduledDate = true
                    applyDates()
                }
                CadenceTaskMutationSupport.setScheduledTime(minutes, for: task, modelContext: modelContext)
            }
        )
    }

    private func finishEditingAndDismiss() {
        isNotesFocused = false
        applyDates()
        try? modelContext.save()
        dismiss()
    }

    private var scheduledTimeLabel: String {
        task.scheduledStartMin >= 0 ? TimeFormatters.timeString(from: task.scheduledStartMin) : "No time"
    }

    private func initializeTaskSheet() {
        loadDates()
        loadContainerSelection()
    }

    private func loadContainerSelection() {
        if let area = task.area {
            containerSelection = "area:\(area.id.uuidString)"
        } else if let project = task.project {
            containerSelection = "project:\(project.id.uuidString)"
        } else {
            containerSelection = "inbox"
        }
        normalizeSectionForCurrentContainer()
    }

    private func loadDates() {
        if let date = DateFormatters.date(from: task.scheduledDate) {
            scheduledDate = date
            hasScheduledDate = true
        } else {
            scheduledDate = Date()
            hasScheduledDate = false
        }

        if let date = DateFormatters.date(from: task.dueDate) {
            dueDate = date
            hasDueDate = true
        } else {
            dueDate = Date()
            hasDueDate = false
        }
    }

    private func applyDates() {
        CadenceTaskMutationSupport.setPlanningDates(
            scheduledDate: hasScheduledDate ? DateFormatters.dateKey(from: scheduledDate) : nil,
            dueDate: hasDueDate ? DateFormatters.dateKey(from: dueDate) : nil,
            for: task,
            modelContext: modelContext
        )
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
    }

    private func saveTask() {
        CadenceTaskMutationSupport.normalizeCompletionState(for: task, modelContext: modelContext)
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }

    private func applyContainerSelection() {
        CadenceTaskMutationSupport.moveToContainer(
            task,
            area: selectedArea,
            project: selectedProject,
            sectionName: task.resolvedSectionName,
            allTasks: allTasks,
            modelContext: modelContext
        )
    }

    private func normalizeSectionForCurrentContainer() {
        task.sectionName = CadenceTaskMutationSupport.normalizedSectionName(
            task.resolvedSectionName,
            area: selectedArea,
            project: selectedProject
        )
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let subtask = Subtask(title: trimmed)
        subtask.order = ((task.subtasks ?? []).map(\.order).max() ?? -1) + 1
        subtask.parentTask = task
        modelContext.insert(subtask)
        task.subtasks = (task.subtasks ?? []) + [subtask]
        newSubtaskTitle = ""
        try? modelContext.save()
    }

    private func deleteSubtask(_ subtask: Subtask) {
        task.subtasks = (task.subtasks ?? []).filter { $0.id != subtask.id }
        modelContext.delete(subtask)
        try? modelContext.save()
    }

    private func toggleCompletion() {
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
    }

    private func selectRecurrenceRule(_ rule: TaskRecurrenceRule) {
        guard task.recurrenceRule != rule else { return }
        if task.isRecurrenceSeriesMember {
            pendingRecurrenceRule = rule
        } else {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: .thisTask
            )
            try? modelContext.save()
        }
    }

    private func applyPendingRecurrenceRule(scope: CadenceTaskRecurrenceEditScope) {
        guard let pendingRecurrenceRule else { return }
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
            pendingRecurrenceRule,
            to: task,
            allTasks: allTasks,
            scope: scope
        )
        self.pendingRecurrenceRule = nil
        try? modelContext.save()
    }
}

#endif
