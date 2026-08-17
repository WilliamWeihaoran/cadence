#if os(macOS)
import SwiftUI
import SwiftData

struct TaskEmbedFieldEditRequest: Identifiable, Hashable {
    let id = UUID()
    let taskID: UUID
    let field: MarkdownTaskEmbedField
}

struct TaskEmbedFieldEditorPopover: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasks: [AppTask]

    @Bindable var task: AppTask
    let initialField: MarkdownTaskEmbedField
    var onChanged: () -> Void = {}

    @State private var dateSelection = Date()
    @State private var dateViewMonth = Date()
    @State private var pendingRecurrenceRule: TaskRecurrenceRule?

    var body: some View {
        content
            .padding(popoverPadding)
            .frame(width: popoverWidth)
            .background(Theme.surfaceElevated)
            .onAppear { resetDateState() }
            .confirmationDialog(
                "Change repeating task?",
                isPresented: Binding(
                    get: { pendingRecurrenceRule != nil },
                    set: { if !$0 { pendingRecurrenceRule = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(TaskRecurrenceEditScope.thisTask.label) {
                    applyPendingRecurrenceRule(scope: .thisTask)
                }
                Button(TaskRecurrenceEditScope.thisAndFuture.label) {
                    applyPendingRecurrenceRule(scope: .thisAndFuture)
                }
                Button("Cancel", role: .cancel) {
                    pendingRecurrenceRule = nil
                }
            } message: {
                Text("Choose whether this repeat change applies only here or to this task and future instances.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch initialField {
        case .title:
            EmptyView()
        case .status:
            // No heading, and no four-option list. `TaskStatus.allCases` offered Todo and Done as
            // picker rows when the embed card's own checkbox already owns both — one field, two
            // controls, and the one that looked authoritative was the one nobody used. What is
            // left is the pair a checkbox cannot express, from the same
            // `CadenceTaskInspectorSupport.StatusAction` the iOS inspector renders, so the two
            // platforms cannot drift on what a status control offers again.
            //
            // "Start" is deliberately kept rather than deleted with the list: it is the **only**
            // writer of `.inProgress` on macOS, and dropping it would strand every task already in
            // that state with no way back out except completing it.
            VStack(spacing: 2) {
                ForEach(CadenceTaskInspectorSupport.StatusAction.allCases, id: \.self) { action in
                    statusActionButton(action)
                }
            }
        case .priority:
            KanbanPriorityPickerPopover(
                priority: Binding(
                    get: { task.priority },
                    set: {
                        task.priority = $0
                        persist()
                    }
                ),
                isPresented: Binding(
                    get: { true },
                    set: { isPresented in
                        if !isPresented { dismiss() }
                    }
                )
            )
        case .container:
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("List")
                ContainerPickerBadge(
                    selection: containerBinding,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    compact: true
                )
                if availableSections.count > 1 {
                    fieldLabel("Section")
                    TaskSectionPickerBadge(selection: sectionBinding, sections: availableSections)
                }
            }
        case .section:
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Section")
                TaskSectionPickerBadge(selection: sectionBinding, sections: availableSections)
            }
        case .scheduledDate:
            VStack(spacing: 0) {
                CadenceQuickDatePopover(
                    selection: Binding(
                        get: { dateSelection },
                        set: {
                            dateSelection = $0
                            task.scheduledDate = DateFormatters.dateKey(from: $0)
                            persist()
                        }
                    ),
                    viewMonth: $dateViewMonth,
                    isOpen: popoverOpenBinding,
                    showsClear: true,
                    onClear: {
                        task.scheduledDate = ""
                        task.scheduledStartMin = -1
                        persist()
                    },
                    inlineStyle: true
                )
                Divider().background(Theme.borderSubtle)
                scheduledTimeControls
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        case .dueDate:
            CadenceQuickDatePopover(
                selection: Binding(
                    get: { dateSelection },
                    set: {
                        dateSelection = $0
                        task.dueDate = DateFormatters.dateKey(from: $0)
                        persist()
                    }
                ),
                viewMonth: $dateViewMonth,
                isOpen: popoverOpenBinding,
                showsClear: true,
                onClear: {
                    task.dueDate = ""
                    persist()
                },
                inlineStyle: true
            )
        case .estimate:
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Estimate")
                Stepper(value: Binding(
                    get: { task.estimatedMinutes },
                    set: {
                        task.estimatedMinutes = max(0, min($0, 1440))
                        persist()
                    }
                ), in: 0...1440, step: 15) {
                    Text(task.estimatedMinutes > 0 ? durationLabel(task.estimatedMinutes) : "No estimate")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                }
                if task.actualMinutes > 0 {
                    Text("Logged \(durationLabel(task.actualMinutes))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
        case .recurrence:
            optionList(title: "Repeat") {
                ForEach(TaskRecurrenceRule.allCases, id: \.self) { rule in
                    optionButton(rule.label, isSelected: task.recurrenceRule == rule) {
                        selectRecurrenceRule(rule)
                    }
                }
            }
        }
    }

    private var popoverWidth: CGFloat {
        switch initialField {
        case .scheduledDate, .dueDate:
            return 270
        case .container, .section:
            return 220
        case .estimate:
            return 190
        default:
            return 170
        }
    }

    private var popoverPadding: CGFloat {
        switch initialField {
        case .scheduledDate, .dueDate, .priority:
            return 0
        default:
            return 10
        }
    }

    private var popoverOpenBinding: Binding<Bool> {
        Binding(
            get: { true },
            set: { isOpen in
                if !isOpen { dismiss() }
            }
        )
    }

    private var currentContainerSelection: TaskContainerSelection {
        if let area = task.area { return .area(area.id) }
        if let project = task.project { return .project(project.id) }
        return .inbox
    }

    private var availableSections: [String] {
        TaskContainerResolver(areas: areas, projects: projects)
            .availableSections(for: currentContainerSelection)
    }

    private var containerBinding: Binding<TaskContainerSelection> {
        Binding(
            get: { currentContainerSelection },
            set: { selection in
                let resolver = TaskContainerResolver(areas: areas, projects: projects)
                resolver.applyContainer(selection, to: task)
                task.sectionName = resolver.normalizedSectionName(task.sectionName, for: selection)
                persist()
            }
        )
    }

    private var sectionBinding: Binding<String> {
        Binding(
            get: { task.resolvedSectionName },
            set: {
                task.sectionName = $0
                persist()
            }
        )
    }

    private func resetDateState() {
        let dateKey = initialField == .dueDate ? task.dueDate : task.scheduledDate
        let resolved = DateFormatters.date(from: dateKey) ?? Date()
        dateSelection = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        dateViewMonth = Calendar.current.date(from: comps) ?? resolved
    }

    private var scheduledTimeControls: some View {
        HStack(spacing: 8) {
            fieldLabel("Time")
            Spacer()
            Stepper(value: scheduledStartBinding, in: 0...1425, step: 15) {
                Text(scheduledTimeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(task.scheduledStartMin >= 0 ? Theme.text : Theme.dim)
                    .monospacedDigit()
            }
            .labelsHidden()
            .frame(width: 84)

            if task.scheduledStartMin >= 0 {
                Button {
                    task.scheduledStartMin = -1
                    persist()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.cadencePlain)
                .help("Clear time")
            }
        }
    }

    private var scheduledStartBinding: Binding<Int> {
        Binding(
            get: { task.scheduledStartMin >= 0 ? task.scheduledStartMin : defaultScheduledStartMin },
            set: {
                if task.scheduledDate.isEmpty {
                    task.scheduledDate = DateFormatters.dateKey(from: dateSelection)
                }
                task.scheduledStartMin = max(0, min($0, 1425))
                persist()
            }
        )
    }

    private var scheduledTimeLabel: String {
        task.scheduledStartMin >= 0 ? TimeFormatters.timeString(from: task.scheduledStartMin) : "No time"
    }

    private var defaultScheduledStartMin: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let raw = ((comps.hour ?? 9) * 60) + (comps.minute ?? 0)
        return min(1425, max(0, Int((Double(raw) / 15.0).rounded()) * 15))
    }

    /// One status transition, labelled by what the tap will *do* — so an already-started task
    /// reads "Stop" and is its own undo back to `todo`.
    private func statusActionButton(_ action: CadenceTaskInspectorSupport.StatusAction) -> some View {
        let isActive = action.isActive(task.status)
        return Button {
            setStatus(action.target(from: task.status))
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: action.systemImage(for: task.status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? Theme.statusColor(action.status) : Theme.dim)
                    .frame(width: 14)
                Text(action.title(for: task.status))
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Theme.text : Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        // `.plain`, not `.cadencePlain`: `TaskPickerRowHover` below is the one hover layer, and
        // cadencePlain's radius-10 fill would nest a second one at a different radius.
        .buttonStyle(.plain)
        .modifier(TaskPickerRowHover())
    }

    private func setStatus(_ status: TaskStatus) {
        switch status {
        case .todo:
            TaskWorkflowService.markTodo(task)
        case .done:
            TaskWorkflowService.markDone(task, in: modelContext)
        case .inProgress:
            task.completedAt = nil
            task.status = .inProgress
        case .cancelled:
            TaskWorkflowService.markCancelled(task, in: modelContext)
        }
        persist()
    }

    private func selectRecurrenceRule(_ rule: TaskRecurrenceRule) {
        guard task.recurrenceRule != rule else {
            dismiss()
            return
        }

        if task.isRecurrenceSeriesMember {
            pendingRecurrenceRule = rule
        } else {
            TaskWorkflowService.applyRecurrenceRule(rule, to: task, allTasks: allTasks, scope: .thisTask)
            persist()
            dismiss()
        }
    }

    private func applyPendingRecurrenceRule(scope: TaskRecurrenceEditScope) {
        guard let pendingRecurrenceRule else { return }
        TaskWorkflowService.applyRecurrenceRule(
            pendingRecurrenceRule,
            to: task,
            allTasks: allTasks,
            scope: scope
        )
        self.pendingRecurrenceRule = nil
        persist()
        dismiss()
    }

    private func persist() {
        try? modelContext.save()
        onChanged()
    }

    private func durationLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "-" }
        return CadenceTaskPresentationSupport.estimateLabel(minutes: minutes)
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.dim)
    }

    private func optionList<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title)
            VStack(spacing: 2) { content() }
        }
    }

    private func optionButton(
        _ label: String,
        isSelected: Bool,
        color: Color = Theme.blue,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .modifier(TaskPickerRowHover())
    }

}

#endif
