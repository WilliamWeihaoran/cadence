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
    /// Set when the commit was refused. The popover stays open holding it and the note editor is
    /// never told to repaint the card — see `commit(alsoRestoring:_:)`.
    @State private var failureNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(popoverPadding)

            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: popoverWidth)
        .background(Theme.surfaceElevated)
        .onAppear { resetDateState() }
        .confirmationDialog(
            CadenceRecurrenceScopeCopy.taskScopeTitle,
            isPresented: Binding(
                get: { pendingRecurrenceRule != nil },
                set: { if !$0 { pendingRecurrenceRule = nil } }
            ),
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
            Text(CadenceRecurrenceScopeCopy.taskScopeMessage)
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
                    set: { priority in
                        commit { task.priority = priority }
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
                        set: { date in
                            dateSelection = date
                            commit {
                                CadenceTaskDateEditing.setScheduledDate(
                                    DateFormatters.dateKey(from: date),
                                    for: task,
                                    in: modelContext
                                )
                            }
                        }
                    ),
                    viewMonth: $dateViewMonth,
                    isOpen: popoverOpenBinding,
                    showsClear: true,
                    onClear: {
                        commit { CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext) }
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
                    set: { date in
                        dateSelection = date
                        commit {
                            CadenceTaskDateEditing.setDueDate(
                                DateFormatters.dateKey(from: date),
                                for: task,
                                in: modelContext
                            )
                        }
                    }
                ),
                viewMonth: $dateViewMonth,
                isOpen: popoverOpenBinding,
                showsClear: true,
                onClear: {
                    commit { CadenceTaskDateEditing.clearDueDate(task, in: modelContext) }
                },
                inlineStyle: true
            )
        case .estimate:
            // The same roller every other estimate surface opens, not a stepper of its own.
            //
            // `3ecfeaf` unified the inspector's roller with the iOS picker and missed this one, so
            // for a while the app had *three* ways to set one field: editing a task from its embed
            // card in a note gave 15-minute steps, while the chip beside it gave the roller's
            // 5-minute column. A value like 50m was not reachable from here at all.
            VStack(alignment: .leading, spacing: 8) {
                EstimatePickerPopoverContent(
                    value: Binding(
                        get: { task.estimatedMinutes },
                        set: { minutes in
                            commit { task.estimatedMinutes = max(0, min(minutes, 1440)) }
                        }
                    ),
                    onClose: { dismiss() }
                )

                if task.actualMinutes > 0 {
                    Text("Logged \(durationLabel(task.actualMinutes))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
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
            // The shared roller sizes itself; this only has to not squeeze it.
            return 240
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
        CadenceTaskComposerSupport.container(of: task)
    }

    private var availableSections: [String] {
        TaskContainerResolver(areas: areas, projects: projects)
            .availableSections(for: currentContainerSelection)
    }

    private var containerBinding: Binding<TaskContainerSelection> {
        Binding(
            get: { currentContainerSelection },
            set: { selection in
                commit {
                    let resolver = TaskContainerResolver(areas: areas, projects: projects)
                    resolver.applyContainer(selection, to: task)
                    task.sectionName = resolver.normalizedSectionName(task.sectionName, for: selection)
                }
            }
        )
    }

    private var sectionBinding: Binding<String> {
        Binding(
            get: { task.resolvedSectionName },
            set: { sectionName in
                commit { task.sectionName = sectionName }
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
                    commit { CadenceTaskDateEditing.clearScheduledTime(task, in: modelContext) }
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
            set: { startMin in
                commit {
                    // A time on no day is not a slot, so an untimed task materialises the day the
                    // popover is showing before it takes the minute — one edit, one reconcile.
                    if task.scheduledDate.isEmpty {
                        CadenceTaskDateEditing.setScheduledSlot(
                            dateKey: DateFormatters.dateKey(from: dateSelection),
                            startMin: startMin,
                            for: task,
                            in: modelContext
                        )
                    } else {
                        CadenceTaskDateEditing.setScheduledTime(startMin, for: task, in: modelContext)
                    }
                }
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
            guard setStatus(action.target(from: task.status)) else { return }
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

    private func setStatus(_ status: TaskStatus) -> Bool {
        commit {
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
        }
    }

    private func selectRecurrenceRule(_ rule: TaskRecurrenceRule) {
        guard task.recurrenceRule != rule else {
            dismiss()
            return
        }

        if task.isRecurrenceSeriesMember {
            pendingRecurrenceRule = rule
        } else {
            guard applyRecurrenceRule(rule, scope: .thisTask) else { return }
            dismiss()
        }
    }

    private func applyPendingRecurrenceRule(scope: CadenceTaskRecurrenceEditScope) {
        guard let pendingRecurrenceRule else { return }
        guard applyRecurrenceRule(pendingRecurrenceRule, scope: scope) else { return }
        self.pendingRecurrenceRule = nil
        dismiss()
    }

    /// `.thisAndFuture` writes the rule to every later occurrence in the series, so those tasks
    /// are handed to the commit as well — the same list the edit itself walks, asked for once.
    private func applyRecurrenceRule(_ rule: TaskRecurrenceRule, scope: CadenceTaskRecurrenceEditScope) -> Bool {
        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: task,
            allTasks: allTasks,
            scope: scope
        )
        return commit(alsoRestoring: targets) {
            TaskWorkflowService.applyRecurrenceRule(rule, to: task, allTasks: allTasks, scope: scope)
        }
    }

    /// The one write path out of this popover.
    ///
    /// T-366: this was `try? modelContext.save(); onChanged()`, and `onChanged()` is what repaints
    /// the note's rendered task card. A refused save therefore drew the card with values the store
    /// does not hold, and the repaint was the only thing telling the user it worked. Now the card
    /// is refreshed exactly when the change is in the store, and a refusal leaves the task as it
    /// was found with the popover open holding the reason.
    @discardableResult
    private func commit(alsoRestoring others: [AppTask] = [], _ apply: () -> Void) -> Bool {
        guard CadenceTaskFieldEditCommit.commit(
            task,
            alsoRestoring: others,
            in: modelContext,
            apply: apply
        ) else {
            failureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return false
        }
        failureNotice = nil
        onChanged()
        return true
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
