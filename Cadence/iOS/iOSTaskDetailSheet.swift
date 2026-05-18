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
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var newSubtaskTitle = ""
    @State private var newTagName = ""
    @State private var scheduledDate = Date()
    @State private var dueDate = Date()
    @State private var hasScheduledDate = false
    @State private var hasDueDate = false
    @State private var containerSelection = "inbox"
    @State private var showDeleteConfirmation = false

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

                iOSTaskTagEditorSection(
                    task: task,
                    allTags: tags,
                    newTagName: $newTagName
                )

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
                        showDeleteConfirmation = true
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
            .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    modelContext.deleteTaskForiOS(task)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the task and its subtasks.")
            }
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
        Section("Tags") {
            if selectedTags.isEmpty {
                Text("No tags")
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
                    .textInputAutocapitalization(.never)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
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
