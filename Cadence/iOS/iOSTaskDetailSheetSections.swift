#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTaskPropertiesSection: View {
    @Bindable var task: AppTask
    let recurrenceSelection: Binding<TaskRecurrenceRule>
    let estimateLabel: String
    let actualTimeLabel: String

    var body: some View {
        iOSTaskEditorSection(title: "Task") {
            iOSTaskEditorRow(label: "Status", systemImage: task.status.systemImage, color: CadenceTaskPresentationSupport.statusColor(task.status)) {
                Picker("Status", selection: $task.status) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                .labelsHidden()
                .tint(CadenceTaskPresentationSupport.statusColor(task.status))
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
}

struct iOSTaskOrganizeSection: View {
    @Bindable var task: AppTask
    let containerSelection: Binding<String>
    let activeAreas: [Area]
    let activeProjects: [Project]
    let availableSectionNames: [String]

    var body: some View {
        iOSTaskEditorSection(title: "Organize") {
            iOSTaskEditorRow(label: "List", systemImage: "tray.full.fill", color: Theme.blue) {
                Picker("List", selection: containerSelection) {
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
                .disabled(containerSelection.wrappedValue == "inbox")
                .opacity(containerSelection.wrappedValue == "inbox" ? 0.45 : 1)
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
}

struct iOSTaskMilestoneSection: View {
    let selectedGoal: Goal?
    let availableGoals: [Goal]
    let goalSelection: Binding<UUID?>
    let onRemoveGoal: () -> Void

    var body: some View {
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

                    Button(action: onRemoveGoal) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove milestone")
                }
            } else if availableGoals.isEmpty {
                Text("Create a milestone first, then attach tasks here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct iOSTaskDatesSection: View {
    let hasScheduledDate: Binding<Bool>
    let scheduledDate: Binding<Date>
    let hasDueDate: Binding<Bool>
    let dueDate: Binding<Date>
    let hasScheduledStartMin: Bool
    let scheduledTimeEnabled: Binding<Bool>
    let scheduledStartSelection: Binding<Int>
    let scheduledTimeLabel: String

    var body: some View {
        iOSTaskEditorSection(title: "Dates") {
            dateToggleRow(
                label: "Do date",
                systemImage: "sun.max.fill",
                color: Theme.amber,
                isOn: hasScheduledDate,
                date: scheduledDate,
                pickerLabel: "Do"
            )

            if hasScheduledDate.wrappedValue {
                iOSTaskEditorDivider()
                scheduledTimeRow
            }

            iOSTaskEditorDivider()

            dateToggleRow(
                label: "Due date",
                systemImage: "flag.fill",
                color: Theme.red,
                isOn: hasDueDate,
                date: dueDate,
                pickerLabel: "Due"
            )
        }
    }

    @ViewBuilder
    private func dateToggleRow(
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

    private var scheduledTimeRow: some View {
        iOSTaskEditorRow(label: "Time", systemImage: "clock.fill", color: Theme.blue) {
            Toggle("Time", isOn: scheduledTimeEnabled)
                .labelsHidden()
                .tint(Theme.blue)

            Stepper(value: scheduledStartSelection, in: 0...1425, step: 15) {
                Text(scheduledTimeLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasScheduledStartMin ? Theme.text : Theme.dim)
                    .monospacedDigit()
            }
            .labelsHidden()
            .disabled(!hasScheduledStartMin)
            .opacity(hasScheduledStartMin ? 1 : 0.45)
            .frame(width: 92)
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

    var body: some View {
        iOSTaskEditorSection(title: "Notes") {
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
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canAddSubtask ? Theme.blue : Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canAddSubtask)
        }
    }
}

struct iOSTaskActionsSection: View {
    let isDone: Bool
    let onToggleCompletion: () -> Void
    let onDeleteRequested: () -> Void

    var body: some View {
        iOSTaskEditorSection(title: "Actions") {
            Button(action: onToggleCompletion) {
                Label(isDone ? "Mark Todo" : "Mark Done",
                      systemImage: isDone ? "circle" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isDone ? Theme.blue : Theme.green)

            iOSTaskEditorDivider()

            Button(role: .destructive, action: onDeleteRequested) {
                Label("Delete Task", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.red)
        }
    }
}
#endif
