#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTaskDetailSheet: View {
    @Bindable var task: AppTask
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
    }

    private var editorScrollView: some View {
        ScrollView {
            taskForm.padding(18)
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
            taskPropertiesSection
            organizeSection
            milestoneSection
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
        iOSTaskEditorSection(title: "Task") {
            iOSTaskEditorRow(label: "Status", systemImage: task.status.systemImage, color: statusColor(task.status)) {
                Picker("Status", selection: $task.status) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                .labelsHidden()
                .tint(statusColor(task.status))
            }

            iOSTaskEditorDivider()

            iOSTaskEditorRow(label: "Priority", systemImage: "flag.fill", color: Theme.priorityColor(task.priority)) {
                Picker("Priority", selection: $task.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                .labelsHidden()
                .tint(Theme.priorityColor(task.priority))
            }

            iOSTaskEditorDivider()

            iOSTaskEditorRow(label: "Repeat", systemImage: task.recurrenceRule.systemImage, color: Theme.purple) {
                Picker("Repeat", selection: recurrenceSelection) {
                    ForEach(TaskRecurrenceRule.allCases, id: \.self) { recurrence in
                        Text(recurrence.label).tag(recurrence)
                    }
                }
                .labelsHidden()
                .tint(Theme.purple)
            }

            iOSTaskEditorDivider()

            iOSTaskEditorRow(label: "Estimate", systemImage: "clock.fill", color: Theme.blue) {
                Stepper(value: $task.estimatedMinutes, in: 5...480, step: 5) {
                    Text(estimateLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }

            iOSTaskEditorDivider()

            iOSTaskEditorRow(label: "Logged", systemImage: "timer", color: Theme.green) {
                Stepper(value: $task.actualMinutes, in: 0...1440, step: 5) {
                    Text(actualTimeLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }

    private var organizeSection: some View {
        iOSTaskEditorSection(title: "Organize") {
            iOSTaskEditorRow(label: "List", systemImage: "tray.full.fill", color: Theme.blue) {
                Picker("List", selection: $containerSelection) {
                    Text("Inbox").tag("inbox")
                    areaPickerSection
                    projectPickerSection
                }
                .labelsHidden()
            }

            iOSTaskEditorDivider()

            iOSTaskEditorRow(label: "Section", systemImage: "rectangle.split.3x1.fill", color: Theme.purple) {
                Picker("Section", selection: $task.sectionName) {
                    ForEach(availableSectionNames, id: \.self) { section in
                        Text(section).tag(section)
                    }
                }
                .labelsHidden()
                .disabled(containerSelection == "inbox")
                .opacity(containerSelection == "inbox" ? 0.45 : 1)
            }
        }
    }

    private var milestoneSection: some View {
        iOSTaskEditorSection(title: "Milestone") {
            iOSTaskEditorRow(
                label: "Linked milestone",
                systemImage: selectedGoal == nil ? "circle.dashed" : "flag.fill",
                color: selectedGoal.map { Color(hex: $0.colorHex) } ?? Theme.dim
            ) {
                Picker("Milestone", selection: goalSelection) {
                    Text("None").tag(Optional<UUID>.none)
                    if !availableGoals.isEmpty {
                        Section("Milestones") {
                            ForEach(availableGoals) { goal in
                                Text(goal.title.isEmpty ? "Untitled Milestone" : goal.title)
                                    .tag(Optional(goal.id))
                            }
                        }
                    }
                }
                .labelsHidden()
                .tint(selectedGoal.map { Color(hex: $0.colorHex) } ?? Theme.blue)
            }

            if let selectedGoal {
                iOSTaskEditorDivider()

                HStack(spacing: 10) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: selectedGoal.colorHex))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: selectedGoal.colorHex).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedGoal.title.isEmpty ? "Untitled Milestone" : selectedGoal.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        Text(selectedGoal.pursuit?.title ?? selectedGoal.context?.name ?? selectedGoal.status.rawValue.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        CadenceTaskMutationSupport.setGoal(nil, for: task, modelContext: modelContext)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }
            } else if availableGoals.isEmpty {
                Text("Create a milestone first, then attach tasks here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var areaPickerSection: some View {
        if !activeAreas.isEmpty {
            Section("Areas") {
                ForEach(activeAreas) { area in
                    Text(area.name.isEmpty ? "Untitled Area" : area.name)
                        .tag("area:\(area.id.uuidString)")
                }
            }
        }
    }

    @ViewBuilder
    private var projectPickerSection: some View {
        if !activeProjects.isEmpty {
            Section("Projects") {
                ForEach(activeProjects) { project in
                    Text(project.name.isEmpty ? "Untitled Project" : project.name)
                        .tag("project:\(project.id.uuidString)")
                }
            }
        }
    }

    private var datesSection: some View {
        iOSTaskEditorSection(title: "Dates") {
            dateToggleSection(
                label: "Do date",
                systemImage: "sun.max.fill",
                color: Theme.amber,
                isOn: $hasScheduledDate,
                date: $scheduledDate,
                pickerLabel: "Do"
            )

            if hasScheduledDate {
                iOSTaskEditorDivider()
                scheduledTimeSection
            }

            iOSTaskEditorDivider()

            dateToggleSection(
                label: "Due date",
                systemImage: "flag.fill",
                color: Theme.red,
                isOn: $hasDueDate,
                date: $dueDate,
                pickerLabel: "Due"
            )
        }
    }

    @ViewBuilder
    private func dateToggleSection(
        label: String,
        systemImage: String,
        color: Color,
        isOn: Binding<Bool>,
        date: Binding<Date>,
        pickerLabel: String
    ) -> some View {
        iOSTaskEditorToggleRow(
            label: label,
            systemImage: systemImage,
            color: color,
            isOn: isOn
        )
        if isOn.wrappedValue {
            DatePicker(pickerLabel, selection: date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(color)
        }
    }

    private var notesSection: some View {
        iOSTaskEditorSection(title: "Notes") {
            iOSMarkdownEditor(text: Binding(
                get: { task.notes },
                set: {
                    task.notes = $0
                    try? modelContext.save()
                }
            ), isFocused: $isNotesFocused)
                .frame(minHeight: 150)
                .background(Theme.surfaceElevated.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
                }
        }
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
        iOSTaskEditorSection(title: "Subtasks") {
            subtaskList
            subtaskComposer
        }
    }

    @ViewBuilder
    private var subtaskList: some View {
        if sortedSubtasks.isEmpty {
            Text("No subtasks")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 7) {
                ForEach(sortedSubtasks) { subtask in
                    iOSSubtaskRow(subtask: subtask) {
                        deleteSubtask(subtask)
                    }
                }
            }
        }
    }

    private var subtaskComposer: some View {
        HStack(spacing: 8) {
            TextField("Add subtask", text: $newSubtaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Theme.surfaceElevated.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
                }
                .onSubmit(addSubtask)

            Button(action: addSubtask) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canAddSubtask ? Theme.blue : Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canAddSubtask)
        }
    }

    private var actionsSection: some View {
        iOSTaskEditorSection(title: "Actions") {
            Button(action: toggleCompletion) {
                Label(task.isDone ? "Mark Todo" : "Mark Done",
                      systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(task.isDone ? Theme.blue : Theme.green)

            iOSTaskEditorDivider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Task", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.red)
        }
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var scheduledTimeSection: some View {
        iOSTaskEditorRow(label: "Time", systemImage: "clock.fill", color: Theme.blue) {
            Toggle("Time", isOn: scheduledTimeEnabled)
                .labelsHidden()
                .tint(Theme.blue)

            Stepper(value: scheduledStartSelection, in: 0...1425, step: 15) {
                Text(scheduledTimeLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(task.scheduledStartMin >= 0 ? Theme.text : Theme.dim)
                    .monospacedDigit()
            }
            .labelsHidden()
            .disabled(task.scheduledStartMin < 0)
            .opacity(task.scheduledStartMin < 0 ? 0.45 : 1)
            .frame(width: 92)
        }
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
        if task.estimatedMinutes < 60 { return "\(task.estimatedMinutes)m" }
        if task.estimatedMinutes % 60 == 0 { return "\(task.estimatedMinutes / 60)h" }
        return String(format: "%.1fh", Double(task.estimatedMinutes) / 60.0)
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
    }

    private func saveTask() {
        CadenceTaskMutationSupport.normalizeCompletionState(for: task, modelContext: modelContext)
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

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .todo: return Theme.dim
        case .inProgress: return Theme.blue
        case .done: return Theme.green
        case .cancelled: return Theme.red
        }
    }
}

private struct iOSTaskEditorTitleCard: View {
    @Bindable var task: AppTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            TextField("Untitled task", text: $task.title, axis: .vertical)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct iOSTaskEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

private struct iOSTaskEditorRow<Content: View>: View {
    let label: String
    let systemImage: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer(minLength: 12)

            content()
        }
        .frame(minHeight: 34)
    }
}

private struct iOSTaskEditorToggleRow: View {
    let label: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        iOSTaskEditorRow(label: label, systemImage: systemImage, color: color) {
            Toggle(label, isOn: $isOn)
                .labelsHidden()
                .tint(color)
        }
    }
}

private struct iOSTaskEditorDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.55))
            .frame(height: 1)
    }
}

private struct iOSSubtaskRow: View {
    @Bindable var subtask: Subtask
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button {
                subtask.isDone.toggle()
            } label: {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(subtask.isDone ? Theme.green : Theme.dim)
            }
            .buttonStyle(.plain)

            Text(subtask.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(subtask.isDone ? Theme.dim : Theme.text)
                .strikethrough(subtask.isDone, color: Theme.dim)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .background(Theme.surfaceElevated.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surfaceElevated.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.4), lineWidth: 1)
        }
    }
}

private struct iOSTaskTagEditorSection: View {
    @Bindable var task: AppTask
    let allTags: [Tag]
    @Binding var newTagName: String
    @Environment(\.modelContext) private var modelContext

    private var selectedTags: [Tag] {
        TagSupport.sorted(task.tags ?? [])
    }

    private var availableTags: [Tag] {
        TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })
    }

    private var trimmedNewTagName: String {
        TagSupport.displayName(for: newTagName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if selectedTags.isEmpty {
                Text("No tags")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedTags) { tag in
                            Button {
                                remove(tag)
                            } label: {
                                HStack(spacing: 5) {
                                    iOSTagChip(tag: tag)
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.dim)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if availableTags.isEmpty {
                Button {
                    TagSupport.seedDefaultTags(in: modelContext)
                } label: {
                    Label("Add Default Tags", systemImage: "tag")
                }
            } else {
                ForEach(availableTags) { tag in
                    Button {
                        toggle(tag)
                    } label: {
                        HStack {
                            iOSTagChip(tag: tag)
                            Spacer()
                            if isSelected(tag) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("New tag", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Theme.surfaceElevated.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
                    }
                    .onSubmit(addTag)

                Button(action: addTag) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(trimmedNewTagName.isEmpty ? Theme.surfaceElevated : Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                    .buttonStyle(.plain)
                    .disabled(trimmedNewTagName.isEmpty)
            }
        }
    }

    private func isSelected(_ tag: Tag) -> Bool {
        (task.tags ?? []).contains { $0.id == tag.id }
    }

    private func toggle(_ tag: Tag) {
        if isSelected(tag) {
            remove(tag)
        } else {
            task.tags = TagSupport.sorted((task.tags ?? []) + [tag])
            try? modelContext.save()
        }
    }

    private func remove(_ tag: Tag) {
        task.tags = (task.tags ?? []).filter { $0.id != tag.id }
        try? modelContext.save()
    }

    private func addTag() {
        let name = trimmedNewTagName
        guard !name.isEmpty else { return }

        let resolved = TagSupport.resolveTags(named: [name], in: modelContext)
        guard let tag = resolved.first else { return }
        if !isSelected(tag) {
            task.tags = TagSupport.sorted((task.tags ?? []) + [tag])
        }
        newTagName = ""
        try? modelContext.save()
    }
}

struct iOSTagChip: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 7, height: 7)
            Text(tag.name.isEmpty ? tag.slug : tag.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color(hex: tag.colorHex))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: tag.colorHex).opacity(0.13))
        .clipShape(Capsule())
    }
}
#endif
