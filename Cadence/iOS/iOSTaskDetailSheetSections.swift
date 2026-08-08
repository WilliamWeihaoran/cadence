#if os(iOS)
import SwiftData
import SwiftUI

/// Consolidated "everything editable about this task" section — status, priority, repeat,
/// schedule, and placement in one flat card: one narrow column read top to bottom, rather than
/// a form-per-field spread of cards.
struct iOSTaskOverviewSection: View {
    @Bindable var task: AppTask
    let containerSelection: Binding<String>
    let activeAreas: [Area]
    let activeProjects: [Project]
    let availableSectionNames: [String]
    let availableGoals: [Goal]
    let recurrenceSelection: Binding<TaskRecurrenceRule>
    let hasScheduledDate: Binding<Bool>
    let scheduledDate: Binding<Date>
    let hasDueDate: Binding<Bool>
    let dueDate: Binding<Date>
    let hasScheduledStartMin: Bool
    let scheduledTimeEnabled: Binding<Bool>
    let scheduledStartSelection: Binding<Int>
    let scheduledTimeLabel: String

    @State private var showStatusPicker = false
    @State private var showPriorityPicker = false
    @State private var showRepeatPicker = false
    @State private var showContainerPicker = false
    @State private var showSectionPicker = false
    @State private var showMilestonePicker = false
    @State private var showTimePicker = false

    private var currentContainerTitle: String {
        if containerSelection.wrappedValue == "inbox" { return "Inbox" }
        if containerSelection.wrappedValue.hasPrefix("area:"),
           let id = UUID(uuidString: String(containerSelection.wrappedValue.dropFirst(5))),
           let area = activeAreas.first(where: { $0.id == id }) {
            return area.name.isEmpty ? "Untitled Area" : area.name
        }
        if containerSelection.wrappedValue.hasPrefix("project:"),
           let id = UUID(uuidString: String(containerSelection.wrappedValue.dropFirst(8))),
           let project = activeProjects.first(where: { $0.id == id }) {
            return project.name.isEmpty ? "Untitled Project" : project.name
        }
        return "Inbox"
    }

    private var selectedGoal: Goal? { task.goal }

    var body: some View {
        iOSTaskEditorSection(title: "Overview") {
            statusRow
            iOSTaskEditorDivider()
            priorityRow
            iOSTaskEditorDivider()
            repeatRow
            iOSTaskEditorDivider()

            dateToggleRow(label: "Do date", systemImage: "sun.max.fill", color: Theme.amber, isOn: hasScheduledDate, date: scheduledDate)
            if hasScheduledDate.wrappedValue {
                iOSTaskEditorDivider()
                scheduledTimeRow
            }
            iOSTaskEditorDivider()
            dateToggleRow(label: "Due date", systemImage: "flag.fill", color: Theme.red, isOn: hasDueDate, date: dueDate)
            iOSTaskEditorDivider()

            iOSTaskEditorRow(label: "Estimate", systemImage: "clock.fill", color: Theme.blue) {
                EstimatePickerControl(value: $task.estimatedMinutes)
            }
            iOSTaskEditorDivider()
            iOSTaskEditorRow(label: "Logged", systemImage: "timer", color: Theme.green) {
                EstimatePickerControl(value: $task.actualMinutes, pickerTitle: "LOGGED")
            }
            iOSTaskEditorDivider()

            containerRow
            iOSTaskEditorDivider()
            sectionRow
            iOSTaskEditorDivider()
            milestoneRow
        }
    }

    private var statusRow: some View {
        iOSTaskEditorRow(label: "Status", systemImage: task.status.systemImage, color: CadenceTaskPresentationSupport.statusColor(task.status)) {
            iOSChoiceValueButton(title: task.status.label, color: CadenceTaskPresentationSupport.statusColor(task.status)) {
                showStatusPicker = true
            }
            .popover(isPresented: $showStatusPicker) {
                iOSChoicePopoverList(
                    rows: TaskStatus.allCases.map { status in
                        iOSChoiceRow(value: status, title: status.label, color: CadenceTaskPresentationSupport.statusColor(status))
                    },
                    selection: $task.status,
                    isPresented: $showStatusPicker
                )
            }
        }
    }

    private var priorityRow: some View {
        iOSTaskEditorRow(label: "Priority", systemImage: "flag.fill", color: Theme.priorityColor(task.priority)) {
            iOSChoiceValueButton(title: task.priority.label, color: Theme.priorityColor(task.priority)) {
                showPriorityPicker = true
            }
            .popover(isPresented: $showPriorityPicker) {
                iOSChoicePopoverList(
                    rows: TaskPriority.allCases.map { priority in
                        iOSChoiceRow(value: priority, title: priority.label, systemImage: "flag.fill", color: Theme.priorityColor(priority))
                    },
                    selection: $task.priority,
                    isPresented: $showPriorityPicker
                )
            }
        }
    }

    private var repeatRow: some View {
        iOSTaskEditorRow(label: "Repeat", systemImage: task.recurrenceRule.systemImage, color: Theme.purple) {
            iOSChoiceValueButton(title: task.recurrenceRule.label, color: Theme.purple) {
                showRepeatPicker = true
            }
            .popover(isPresented: $showRepeatPicker) {
                iOSChoicePopoverList(
                    rows: TaskRecurrenceRule.allCases.map { rule in
                        iOSChoiceRow(value: rule, title: rule.label, systemImage: rule.systemImage, color: Theme.purple)
                    },
                    selection: recurrenceSelection,
                    isPresented: $showRepeatPicker
                )
            }
        }
    }

    private var containerRow: some View {
        iOSTaskEditorRow(label: "List", systemImage: "tray.full.fill", color: Theme.blue) {
            iOSChoiceValueButton(title: currentContainerTitle, color: Theme.text) {
                showContainerPicker = true
            }
            .popover(isPresented: $showContainerPicker) {
                iOSContainerChoicePopover(
                    activeAreas: activeAreas,
                    activeProjects: activeProjects,
                    selection: containerSelection,
                    isPresented: $showContainerPicker
                )
            }
        }
    }

    private var sectionRow: some View {
        iOSTaskEditorRow(label: "Section", systemImage: "rectangle.split.3x1.fill", color: Theme.purple) {
            iOSChoiceValueButton(title: task.sectionName.isEmpty ? "Default" : task.sectionName, color: Theme.text) {
                showSectionPicker = true
            }
            .popover(isPresented: $showSectionPicker) {
                iOSChoicePopoverList(
                    rows: availableSectionNames.map { name in
                        iOSChoiceRow(value: name, title: name, color: Theme.purple)
                    },
                    selection: $task.sectionName,
                    isPresented: $showSectionPicker
                )
            }
            .disabled(containerSelection.wrappedValue == "inbox")
            .opacity(containerSelection.wrappedValue == "inbox" ? 0.45 : 1)
        }
    }

    private var milestoneRow: some View {
        iOSTaskEditorRow(
            label: "Milestone",
            systemImage: selectedGoal == nil ? "circle.dashed" : "flag.fill",
            color: selectedGoal.map { Color(hex: $0.colorHex) } ?? Theme.dim
        ) {
            iOSChoiceValueButton(
                title: selectedGoal.map { $0.title.isEmpty ? "Untitled Milestone" : $0.title } ?? "None",
                color: selectedGoal.map { Color(hex: $0.colorHex) } ?? Theme.dim
            ) {
                showMilestonePicker = true
            }
            .popover(isPresented: $showMilestonePicker) {
                iOSChoicePopoverList(
                    rows: [iOSChoiceRow<UUID?>(value: nil, title: "None", systemImage: "circle.dashed", color: Theme.dim)]
                        + availableGoals.map { goal in
                            iOSChoiceRow(value: Optional(goal.id), title: goal.title.isEmpty ? "Untitled Milestone" : goal.title, systemImage: "flag.fill", color: Color(hex: goal.colorHex))
                        },
                    selection: goalSelection,
                    isPresented: $showMilestonePicker
                )
            }
        }
    }

    private var goalSelection: Binding<UUID?> {
        Binding(
            get: { task.goal?.id },
            set: { goalID in
                let goal = goalID.flatMap { id in availableGoals.first { $0.id == id } }
                task.goal = goal
            }
        )
    }

    @ViewBuilder
    private func dateToggleRow(label: String, systemImage: String, color: Color, isOn: Binding<Bool>, date: Binding<Date>) -> some View {
        iOSTaskEditorToggleRow(label: label, systemImage: systemImage, color: color, isOn: isOn)
        if isOn.wrappedValue {
            CadenceDatePicker(selection: date)
        }
    }

    private var scheduledTimeRow: some View {
        iOSTaskEditorRow(label: "Time", systemImage: "clock.fill", color: Theme.blue) {
            Toggle("Time", isOn: scheduledTimeEnabled)
                .labelsHidden()
                .tint(Theme.blue)

            iOSChoiceValueButton(title: scheduledTimeLabel, color: hasScheduledStartMin ? Theme.text : Theme.dim) {
                showTimePicker = true
            }
            .disabled(!hasScheduledStartMin)
            .opacity(hasScheduledStartMin ? 1 : 0.45)
            .popover(isPresented: $showTimePicker) {
                iOSChoicePopoverList(
                    rows: stride(from: 0, to: 1440, by: 15).map { minute in
                        iOSChoiceRow(value: minute, title: TimeFormatters.timeString(from: minute), color: Theme.blue)
                    },
                    selection: scheduledStartSelection,
                    isPresented: $showTimePicker
                )
            }
        }
    }
}

struct iOSTaskNotesSection: View {
    let notesText: Binding<String>
    let isFocused: Binding<Bool>
    let notesEditorModeBinding: Binding<iOSMarkdownEditorMode>
    let minHeight: CGFloat
    let referenceNotes: [Note]
    let referenceTasks: [AppTask]
    let onOpenReference: (MarkdownReferenceDisplayTarget) -> Void
    @Bindable var task: AppTask
    let allTags: [Tag]
    @Binding var newTagName: String

    var body: some View {
        iOSTaskEditorSection(title: "Notes") {
            iOSTaskTagEditorSection(
                task: task,
                allTags: allTags,
                newTagName: $newTagName
            )

            HStack {
                Spacer()
                iOSMarkdownModePicker(mode: notesEditorModeBinding)
            }

            iOSMarkdownEditingSurface(
                text: notesText,
                isFocused: isFocused,
                mode: notesEditorModeBinding,
                placeholder: "Add notes...",
                referenceNotes: referenceNotes,
                referenceTasks: referenceTasks,
                onOpenReference: onOpenReference
            )
                .frame(minHeight: minHeight)
                .cadenceCard(background: Theme.surfaceElevated.opacity(0.35), cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
        }
    }
}

struct iOSTaskSubtasksSection: View {
    let subtasks: [Subtask]
    let newSubtaskTitle: Binding<String>
    let canAddSubtask: Bool
    let onAdd: () -> Void
    let onDelete: (Subtask) -> Void

    var body: some View {
        iOSTaskEditorSection(title: "Subtasks") {
            subtaskList
            subtaskComposer
        }
    }

    @ViewBuilder
    private var subtaskList: some View {
        if subtasks.isEmpty {
            Text("No subtasks")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 7) {
                ForEach(subtasks) { subtask in
                    iOSSubtaskRow(subtask: subtask) {
                        onDelete(subtask)
                    }
                }
            }
        }
    }

    private var subtaskComposer: some View {
        HStack(spacing: 8) {
            TextField("Add subtask", text: newSubtaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .cadenceCard(background: Theme.surfaceElevated.opacity(0.55), cornerRadius: Theme.radiusControl, shadowRadius: 8, shadowY: 3)
                .onSubmit(onAdd)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 36, height: 36)
                    .background(canAddSubtask ? Theme.blue : Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canAddSubtask)
        }
    }
}
#endif
