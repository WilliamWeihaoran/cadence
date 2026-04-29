#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTaskRow: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    toggleCompletion()
                } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        priorityBadge

                        if !task.scheduledDate.isEmpty {
                            taskBadge(
                                systemImage: "sun.max.fill",
                                text: DateFormatters.relativeDate(from: task.scheduledDate),
                                color: task.scheduledDate == DateFormatters.todayKey() ? Theme.amber : Theme.dim
                            )
                        }

                        if !task.dueDate.isEmpty {
                            taskBadge(
                                systemImage: "flag.fill",
                                text: DateFormatters.relativeDate(from: task.dueDate),
                                color: isOverdue ? Theme.red : Theme.dim
                            )
                        }

                        if task.estimatedMinutes > 0 {
                            taskBadge(
                                systemImage: "clock",
                                text: estimateLabel,
                                color: Theme.dim
                            )
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.65))
                    .padding(.top, 5)
            }
            .padding(14)
            .background(Theme.surfaceElevated.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }

    private var priorityBadge: some View {
        taskBadge(
            systemImage: "circle.fill",
            text: task.priority.label,
            color: Theme.priorityColor(task.priority)
        )
    }

    private var isOverdue: Bool {
        !task.dueDate.isEmpty && task.dueDate < DateFormatters.todayKey()
    }

    private var estimateLabel: String {
        if task.estimatedMinutes < 60 { return "\(task.estimatedMinutes)m" }
        if task.estimatedMinutes % 60 == 0 { return "\(task.estimatedMinutes / 60)h" }
        return String(format: "%.1fh", Double(task.estimatedMinutes) / 60.0)
    }

    private func taskBadge(systemImage: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.11))
        .clipShape(Capsule())
    }

    private func toggleCompletion() {
        if task.isDone {
            task.status = .todo
            task.completedAt = nil
        } else {
            task.status = .done
            task.completedAt = Date()
        }
        try? modelContext.save()
    }
}

struct iOSTaskDetailSheet: View {
    @Bindable var task: AppTask
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var newSubtaskTitle = ""
    @State private var scheduledDate = Date()
    @State private var dueDate = Date()
    @State private var hasScheduledDate = false
    @State private var hasDueDate = false
    @State private var containerSelection = "inbox"

    private var sortedSubtasks: [Subtask] {
        (task.subtasks ?? []).sorted { $0.order < $1.order }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var availableSectionNames: [String] {
        if let areaID = selectedAreaID,
           let area = areas.first(where: { $0.id == areaID }) {
            return area.sectionNames
        }
        if let projectID = selectedProjectID,
           let project = projects.first(where: { $0.id == projectID }) {
            return project.sectionNames
        }
        return [TaskSectionDefaults.defaultName]
    }

    private var selectedAreaID: UUID? {
        guard containerSelection.hasPrefix("area:") else { return nil }
        return UUID(uuidString: String(containerSelection.dropFirst(5)))
    }

    private var selectedProjectID: UUID? {
        guard containerSelection.hasPrefix("project:") else { return nil }
        return UUID(uuidString: String(containerSelection.dropFirst(8)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $task.title, axis: .vertical)
                        .lineLimit(1...3)

                    Picker("Priority", selection: $task.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }

                    Stepper(value: $task.estimatedMinutes, in: 5...480, step: 5) {
                        Text("Estimate: \(estimateLabel)")
                    }
                }

                Section("Organize") {
                    Picker("List", selection: $containerSelection) {
                        Text("Inbox").tag("inbox")

                        if !activeAreas.isEmpty {
                            Section("Areas") {
                                ForEach(activeAreas) { area in
                                    Text(area.name.isEmpty ? "Untitled Area" : area.name)
                                        .tag("area:\(area.id.uuidString)")
                                }
                            }
                        }

                        if !activeProjects.isEmpty {
                            Section("Projects") {
                                ForEach(activeProjects) { project in
                                    Text(project.name.isEmpty ? "Untitled Project" : project.name)
                                        .tag("project:\(project.id.uuidString)")
                                }
                            }
                        }
                    }

                    Picker("Section", selection: $task.sectionName) {
                        ForEach(availableSectionNames, id: \.self) { section in
                            Text(section).tag(section)
                        }
                    }
                    .disabled(containerSelection == "inbox")
                }

                Section("Dates") {
                    Toggle("Do date", isOn: $hasScheduledDate)
                    if hasScheduledDate {
                        DatePicker("Do", selection: $scheduledDate, displayedComponents: .date)
                    }

                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $task.notes)
                        .frame(minHeight: 140)
                }

                Section("Subtasks") {
                    ForEach(sortedSubtasks) { subtask in
                        iOSSubtaskRow(subtask: subtask)
                    }
                    .onDelete(perform: deleteSubtasks)

                    HStack {
                        TextField("Add subtask", text: $newSubtaskTitle)
                            .onSubmit(addSubtask)
                        Button("Add", action: addSubtask)
                            .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    Button {
                        toggleCompletion()
                    } label: {
                        Label(task.isDone ? "Mark Todo" : "Mark Done",
                              systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
                    }

                    Button(role: .destructive) {
                        modelContext.delete(task)
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        applyDates()
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .tint(Theme.blue)
            .onAppear {
                loadDates()
                loadContainerSelection()
            }
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
        }
        .preferredColorScheme(.dark)
    }

    private var estimateLabel: String {
        if task.estimatedMinutes < 60 { return "\(task.estimatedMinutes)m" }
        if task.estimatedMinutes % 60 == 0 { return "\(task.estimatedMinutes / 60)h" }
        return String(format: "%.1fh", Double(task.estimatedMinutes) / 60.0)
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
        task.scheduledDate = hasScheduledDate ? DateFormatters.dateKey(from: scheduledDate) : ""
        task.dueDate = hasDueDate ? DateFormatters.dateKey(from: dueDate) : ""
        try? modelContext.save()
    }

    private func applyContainerSelection() {
        if containerSelection == "inbox" {
            task.area = nil
            task.project = nil
            task.context = nil
            task.sectionName = TaskSectionDefaults.defaultName
            task.order = nextOrderForCurrentContainer()
            try? modelContext.save()
            return
        }

        if let areaID = selectedAreaID,
           let area = areas.first(where: { $0.id == areaID }) {
            task.area = area
            task.project = nil
            task.context = area.context
            normalizeSectionForCurrentContainer()
            task.order = nextOrderForCurrentContainer()
            try? modelContext.save()
            return
        }

        if let projectID = selectedProjectID,
           let project = projects.first(where: { $0.id == projectID }) {
            task.project = project
            task.area = nil
            task.context = project.context ?? project.area?.context
            normalizeSectionForCurrentContainer()
            task.order = nextOrderForCurrentContainer()
            try? modelContext.save()
        }
    }

    private func normalizeSectionForCurrentContainer() {
        let names = availableSectionNames
        if !names.contains(where: { $0.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame }) {
            task.sectionName = names.first ?? TaskSectionDefaults.defaultName
        }
    }

    private func nextOrderForCurrentContainer() -> Int {
        let relatedTasks: [AppTask]
        if let areaID = selectedAreaID {
            relatedTasks = (areas.first(where: { $0.id == areaID })?.tasks ?? []).filter { $0.id != task.id }
        } else if let projectID = selectedProjectID {
            relatedTasks = (projects.first(where: { $0.id == projectID })?.tasks ?? []).filter { $0.id != task.id }
        } else {
            relatedTasks = allTasks.filter { $0.id != task.id && $0.area == nil && $0.project == nil }
        }
        return (relatedTasks.map(\.order).max() ?? -1) + 1
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

    private func deleteSubtasks(at offsets: IndexSet) {
        for index in offsets {
            let subtask = sortedSubtasks[index]
            task.subtasks = (task.subtasks ?? []).filter { $0.id != subtask.id }
            modelContext.delete(subtask)
        }
        try? modelContext.save()
    }

    private func toggleCompletion() {
        if task.isDone {
            task.status = .todo
            task.completedAt = nil
        } else {
            task.status = .done
            task.completedAt = Date()
        }
        try? modelContext.save()
    }
}

private struct iOSSubtaskRow: View {
    @Bindable var subtask: Subtask

    var body: some View {
        Button {
            subtask.isDone.toggle()
        } label: {
            HStack {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isDone ? Theme.green : Theme.dim)
                Text(subtask.title)
                    .foregroundStyle(subtask.isDone ? Theme.dim : Theme.text)
                    .strikethrough(subtask.isDone, color: Theme.dim)
            }
        }
        .buttonStyle(.plain)
    }
}

struct iOSTaskCaptureBar: View {
    let placeholder: String
    @Binding var title: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(action)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                }

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
    }
}

struct iOSPanelHeader: View {
    let eyebrow: String
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.blue.opacity(0.13))
                    .clipShape(Capsule())
            }
        }
        .padding(20)
    }
}

struct iOSEmptyPanel: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
#endif
