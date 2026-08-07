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
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var notesEditorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
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

    private var selectedGoal: Goal? {
        task.goal
    }

    private var currentContainerTitle: String {
        if let selectedArea {
            return selectedArea.name.isEmpty ? "Untitled Area" : selectedArea.name
        }
        if let selectedProject {
            return selectedProject.name.isEmpty ? "Untitled Project" : selectedProject.name
        }
        if let area = task.area {
            return area.name.isEmpty ? "Untitled Area" : area.name
        }
        if let project = task.project {
            return project.name.isEmpty ? "Untitled Project" : project.name
        }
        return "Inbox"
    }

    private var currentGoalTitle: String? {
        guard let selectedGoal else { return nil }
        return selectedGoal.title.isEmpty ? "Untitled Goal" : selectedGoal.title
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var notesEditorMode: iOSMarkdownEditorMode {
        iOSMarkdownEditorPreferences.mode(from: notesEditorModeRaw)
    }

    private var notesEditorModeBinding: Binding<iOSMarkdownEditorMode> {
        iOSMarkdownEditorPreferences.binding(for: $notesEditorModeRaw)
    }

    private var notesEditorMinHeight: CGFloat {
        if notesEditorMode == .live {
            return isRegularWidth ? 360 : 340
        }
        return isRegularWidth ? 240 : 170
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
        .onChange(of: hasScheduledDate) { _, newValue in
            if newValue && task.scheduledDate.isEmpty {
                scheduledDate = Date()
            }
            applyDates()
        }
        .onChange(of: hasDueDate) { _, newValue in
            if newValue && task.dueDate.isEmpty {
                dueDate = Date()
            }
            applyDates()
        }
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
                .background(Color(hex: "#151824"))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var taskForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            iOSTaskEditorTitleCard(task: task)
            iOSTaskEditorOverviewCard(
                task: task,
                containerTitle: currentContainerTitle,
                goalTitle: currentGoalTitle
            )
            taskPropertiesSection
            organizeSection
            goalSection
            datesSection
            notesSection
            tagsSection
            subtasksSection
            actionsSection
        }
    }

    @ToolbarContentBuilder
    private var taskToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
                finishEditingAndDismiss()
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                isNotesFocused = false
            }
        }
    }

    private var taskPropertiesSection: some View {
        iOSTaskPropertiesSection(
            task: task,
            recurrenceSelection: recurrenceSelection,
            estimateLabel: estimateLabel,
            actualTimeLabel: actualTimeLabel
        )
    }

    private var organizeSection: some View {
        iOSTaskOrganizeSection(
            task: task,
            containerSelection: $containerSelection,
            activeAreas: activeAreas,
            activeProjects: activeProjects,
            availableSectionNames: availableSectionNames
        )
    }

    private var goalSection: some View {
        iOSTaskGoalSection(
            selectedGoal: selectedGoal,
            availableGoals: availableGoals,
            goalSelection: goalSelection,
            onRemoveGoal: {
                CadenceTaskMutationSupport.setGoal(nil, for: task, modelContext: modelContext)
            }
        )
    }

    private var datesSection: some View {
        iOSTaskDatesSection(
            hasScheduledDate: $hasScheduledDate,
            scheduledDate: $scheduledDate,
            hasDueDate: $hasDueDate,
            dueDate: $dueDate,
            hasScheduledStartMin: task.scheduledStartMin >= 0,
            scheduledTimeEnabled: scheduledTimeEnabled,
            scheduledStartSelection: scheduledStartSelection,
            scheduledTimeLabel: scheduledTimeLabel
        )
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
            notesEditorModeBinding: notesEditorModeBinding,
            minHeight: notesEditorMinHeight,
            referenceNotes: allNotes,
            referenceTasks: allTasks,
            onOpenReference: openMarkdownReference
        )
    }

    private var tagsSection: some View {
        iOSTaskEditorSection(title: "Tags") {
            iOSTaskTagEditorSection(
                task: task,
                allTags: tags,
                newTagName: $newTagName
            )
        }
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

    private var actionsSection: some View {
        iOSTaskActionsSection(
            isDone: task.isDone,
            onToggleCompletion: toggleCompletion,
            onDeleteRequested: { showDeleteConfirmation = true }
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

    private var scheduledTimeEnabled: Binding<Bool> {
        Binding(
            get: { task.scheduledStartMin >= 0 },
            set: { isEnabled in
                if isEnabled {
                    enableScheduledTime()
                } else {
                    CadenceTaskMutationSupport.clearScheduledTime(task, modelContext: modelContext)
                }
            }
        )
    }

    private var scheduledStartSelection: Binding<Int> {
        Binding(
            get: { task.scheduledStartMin >= 0 ? task.scheduledStartMin : defaultScheduledStartMin },
            set: { minutes in
                if !hasScheduledDate {
                    hasScheduledDate = true
                    scheduledDate = Date()
                    applyDates()
                }
                CadenceTaskMutationSupport.setScheduledTime(minutes, for: task, modelContext: modelContext)
            }
        )
    }

    private var goalSelection: Binding<UUID?> {
        Binding(
            get: { task.goal?.id },
            set: { goalID in
                let goal = goalID.flatMap { id in goals.first { $0.id == id } }
                CadenceTaskMutationSupport.setGoal(goal, for: task, modelContext: modelContext)
            }
        )
    }

    private func finishEditingAndDismiss() {
        isNotesFocused = false
        applyDates()
        try? modelContext.save()
        dismiss()
    }

    private var estimateLabel: String {
        CadenceTaskPresentationSupport.estimateLabel(for: task)
    }

    private var actualTimeLabel: String {
        if task.actualMinutes == 0 { return "None" }
        if task.actualMinutes < 60 { return "\(task.actualMinutes)m" }
        if task.actualMinutes % 60 == 0 { return "\(task.actualMinutes / 60)h" }
        return String(format: "%.1fh", Double(task.actualMinutes) / 60.0)
    }

    private var scheduledTimeLabel: String {
        task.scheduledStartMin >= 0 ? TimeFormatters.timeString(from: task.scheduledStartMin) : "No time"
    }

    private var defaultScheduledStartMin: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let raw = ((comps.hour ?? 9) * 60) + (comps.minute ?? 0)
        return min(1425, max(0, Int((Double(raw) / 15.0).rounded()) * 15))
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

    private func enableScheduledTime() {
        if !hasScheduledDate {
            hasScheduledDate = true
            scheduledDate = Date()
            applyDates()
        }
        CadenceTaskMutationSupport.setScheduledTime(defaultScheduledStartMin, for: task, modelContext: modelContext)
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
