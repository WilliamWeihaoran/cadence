#if os(macOS)
import SwiftUI
import SwiftData

struct TaskEmbedFieldEditRequest: Identifiable, Hashable {
    let id = UUID()
    let taskID: UUID
    let field: MarkdownTaskEmbedField
}

struct TaskEmbedFieldEditorPopover: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @Bindable var task: AppTask
    let initialField: MarkdownTaskEmbedField
    var onChanged: () -> Void = {}

    @State private var field: MarkdownTaskEmbedField
    @FocusState private var titleFocused: Bool

    init(task: AppTask, initialField: MarkdownTaskEmbedField, onChanged: @escaping () -> Void = {}) {
        self.task = task
        self.initialField = initialField
        self.onChanged = onChanged
        _field = State(initialValue: initialField)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabBar
            Divider().background(Theme.borderSubtle)
            editor
        }
        .padding(12)
        .frame(width: 300)
        .background(Theme.surfaceElevated)
        .onAppear {
            field = initialField
            if initialField == .title {
                DispatchQueue.main.async { titleFocused = true }
            }
        }
        .onChange(of: field) { _, newField in
            if newField == .title {
                DispatchQueue.main.async { titleFocused = true }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(fieldTabs, id: \.self) { tab in
                TaskEmbedFieldTabButton(
                    label: tab.shortLabel,
                    isSelected: field == tab
                ) {
                    field = tab
                }
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch field {
        case .title:
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Title")
                TextField("Task title", text: Binding(
                    get: { task.title },
                    set: {
                        task.title = $0
                        persist()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
            }
        case .status:
            optionGrid(title: "Status") {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    optionButton(status.label, isSelected: task.status == status) {
                        setStatus(status)
                    }
                }
            }
        case .priority:
            optionGrid(title: "Priority") {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    optionButton(priority.label, isSelected: task.priority == priority, color: Theme.priorityColor(priority)) {
                        task.priority = priority
                        persist()
                    }
                }
            }
        case .container:
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Container")
                ContainerPickerBadge(
                    selection: containerBinding,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    compact: true
                )
                sectionPicker
            }
        case .section:
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Section")
                sectionPicker
            }
        case .scheduledDate:
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Do date")
                DatePicker("Date", selection: scheduledDateBinding, displayedComponents: [.date])
                    .labelsHidden()
                Toggle("Set start time", isOn: scheduledTimeEnabledBinding)
                    .toggleStyle(.checkbox)
                if task.scheduledStartMin >= 0 {
                    DatePicker("Time", selection: scheduledTimeBinding, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                }
                clearButton("Clear do date") {
                    task.scheduledDate = ""
                    task.scheduledStartMin = -1
                    persist()
                }
            }
        case .dueDate:
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Due date")
                DatePicker("Due date", selection: dueDateBinding, displayedComponents: [.date])
                    .labelsHidden()
                clearButton("Clear due date") {
                    task.dueDate = ""
                    persist()
                }
            }
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
            optionGrid(title: "Repeat") {
                ForEach(TaskRecurrenceRule.allCases, id: \.self) { rule in
                    optionButton(rule.label, isSelected: task.recurrenceRule == rule) {
                        task.recurrenceRule = rule
                        persist()
                    }
                }
            }
        }
    }

    private var fieldTabs: [MarkdownTaskEmbedField] {
        [.title, .status, .priority, .container, .scheduledDate, .dueDate, .estimate, .recurrence]
    }

    @ViewBuilder
    private var sectionPicker: some View {
        let sections = availableSections
        if sections.count <= 1 {
            Text(task.resolvedSectionName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
        } else {
            Picker("Section", selection: Binding(
                get: { task.resolvedSectionName },
                set: {
                    task.sectionName = $0
                    persist()
                }
            )) {
                ForEach(sections, id: \.self) { section in
                    Text(section).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var availableSections: [String] {
        TaskContainerResolver(areas: areas, projects: projects).availableSections(for: currentContainerSelection)
    }

    private var currentContainerSelection: TaskContainerSelection {
        if let area = task.area { return .area(area.id) }
        if let project = task.project { return .project(project.id) }
        return .inbox
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

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: task.dueDate) ?? Date() },
            set: {
                task.dueDate = DateFormatters.dateKey(from: $0)
                persist()
            }
        )
    }

    private var scheduledDateBinding: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: task.scheduledDate) ?? Date() },
            set: {
                task.scheduledDate = DateFormatters.dateKey(from: $0)
                persist()
            }
        )
    }

    private var scheduledTimeEnabledBinding: Binding<Bool> {
        Binding(
            get: { task.scheduledStartMin >= 0 },
            set: { enabled in
                if enabled {
                    if task.scheduledDate.isEmpty {
                        task.scheduledDate = DateFormatters.todayKey()
                    }
                    task.scheduledStartMin = task.scheduledStartMin >= 0 ? task.scheduledStartMin : 9 * 60
                } else {
                    task.scheduledStartMin = -1
                }
                persist()
            }
        )
    }

    private var scheduledTimeBinding: Binding<Date> {
        Binding(
            get: { date(from: task.scheduledDate, minute: max(task.scheduledStartMin, 9 * 60)) },
            set: {
                task.scheduledStartMin = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
                if task.scheduledDate.isEmpty {
                    task.scheduledDate = DateFormatters.dateKey(from: $0)
                }
                persist()
            }
        )
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
            task.completedAt = nil
            task.status = .cancelled
        }
        persist()
    }

    private func persist() {
        try? modelContext.save()
        onChanged()
    }

    private func date(from key: String, minute: Int) -> Date {
        let base = DateFormatters.date(from: key) ?? Date()
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: max(0, min(minute / 60, 23)),
            minute: max(0, min(minute % 60, 59)),
            second: 0,
            of: base
        ) ?? base
    }

    private func durationLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "-" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return String(format: "%.1fh", Double(minutes) / 60.0)
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.dim)
    }

    private func optionGrid<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title)
            VStack(spacing: 4) { content() }
        }
    }

    private func optionButton(_ label: String, isSelected: Bool, color: Color = Theme.blue, action: @escaping () -> Void) -> some View {
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
    }

    private func clearButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.dim)
            .buttonStyle(.cadencePlain)
    }
}

private extension TaskStatus {
    var label: String {
        switch self {
        case .todo:
            return "Todo"
        case .inProgress:
            return "In progress"
        case .done:
            return "Done"
        case .cancelled:
            return "Cancelled"
        }
    }
}

private extension MarkdownTaskEmbedField {
    var shortLabel: String {
        switch self {
        case .title:
            return "Title"
        case .status:
            return "Status"
        case .priority:
            return "Priority"
        case .container:
            return "Place"
        case .section:
            return "Section"
        case .scheduledDate:
            return "Do"
        case .dueDate:
            return "Due"
        case .estimate:
            return "Estimate"
        case .recurrence:
            return "Repeat"
        }
    }
}

private struct TaskEmbedFieldTabButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isSelected ? Theme.blue.opacity(0.13) : Theme.surface.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
