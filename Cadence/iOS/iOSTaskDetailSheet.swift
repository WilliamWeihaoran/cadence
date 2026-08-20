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
    @State private var pendingRecurrenceChange: PendingRecurrenceChange?
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

    /// The **only** thing this sheet reads the size class for: the margin between its card and the
    /// edge of the host. Everything else it draws is `iOSTaskInspectorMetrics`, which takes no
    /// width — see that file for why a sheet's measurements are its own.
    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
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
                applyPendingRecurrenceChange(scope: .thisTask)
            }
            Button(CadenceTaskRecurrenceEditScope.thisAndFuture.label) {
                applyPendingRecurrenceChange(scope: .thisAndFuture)
            }
            Button("Cancel", role: .cancel) {
                pendingRecurrenceChange = nil
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
                .padding(iOSTaskInspectorMetrics.cardPadding)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
                .frame(maxWidth: iOSTaskInspectorMetrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(iOSTaskInspectorMetrics.sheetGutter(isRegularWidth: isRegularWidth))
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
        VStack(alignment: .leading, spacing: iOSTaskInspectorMetrics.sectionSpacing) {
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
            // Completion-circle width plus the title row's spacing, so everything under the title
            // lines up with the title text rather than with the circle. Derived in
            // `iOSTaskInspectorMetrics` from the circle itself, rather than restated here where it
            // could — and did — go on ramping after the circle stopped.
            .padding(.leading, iOSTaskInspectorMetrics.titleColumnInset)
        }
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
            applyRecurrenceEnd: selectRecurrenceEnd,
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
            get: { pendingRecurrenceChange != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRecurrenceChange = nil
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
        stage(.rule(rule))
    }

    /// The Ends rows' one write path. Same shape as the rule edit above, and deliberately the same
    /// scope question: an end condition belongs to the series, so "only this one" against "this and
    /// future" is exactly as meaningful here as it is for the frequency, and it would be strange
    /// for one of the two edits in the same well to ask and the other to decide silently.
    private func selectRecurrenceEnd(mode: TaskRecurrenceEndMode, dateKey: String, count: Int) {
        let normalizedDate = mode == .onDate ? dateKey : ""
        let normalizedCount = mode == .afterCount
            ? CadenceTaskRecurrenceEndPresentation.normalizedEndCount(count)
            : 0
        guard mode != task.recurrenceEndMode
                || normalizedDate != task.recurrenceEndDate
                || normalizedCount != task.recurrenceEndCount else { return }
        stage(.end(mode: mode, dateKey: normalizedDate, count: normalizedCount))
    }

    /// A task with no siblings has nothing to propagate to, so there is no scope to ask about and
    /// the edit lands immediately. One staging function for both edits, so a future change to how
    /// the scope is asked — the inline "APPLY TO" row macOS uses instead of this dialog — has one
    /// place to land rather than two.
    private func stage(_ change: PendingRecurrenceChange) {
        guard task.isRecurrenceSeriesMember else {
            apply(change, scope: .thisTask)
            return
        }
        pendingRecurrenceChange = change
    }

    private func applyPendingRecurrenceChange(scope: CadenceTaskRecurrenceEditScope) {
        guard let pendingRecurrenceChange else { return }
        apply(pendingRecurrenceChange, scope: scope)
        self.pendingRecurrenceChange = nil
    }

    private func apply(_ change: PendingRecurrenceChange, scope: CadenceTaskRecurrenceEditScope) {
        switch change {
        case .rule(let rule):
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: scope
            )
            if rule == .none {
                // An end condition on a task that no longer repeats is meaningless, and leaving it
                // behind would re-arm the moment repeating is switched back on.
                CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                    mode: .never,
                    to: task,
                    allTasks: allTasks,
                    scope: scope
                )
            }
        case .end(let mode, let dateKey, let count):
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                mode: mode,
                endDateKey: dateKey,
                endCount: count,
                to: task,
                allTasks: allTasks,
                scope: scope
            )
        }
        try? modelContext.save()
    }
}

/// One recurrence edit awaiting its scope. Rule and end changes share a single case list — the
/// same shape macOS's inspector uses — so neither can grow a path that forgets the scope.
private enum PendingRecurrenceChange {
    case rule(TaskRecurrenceRule)
    case end(mode: TaskRecurrenceEndMode, dateKey: String, count: Int)
}

#endif
