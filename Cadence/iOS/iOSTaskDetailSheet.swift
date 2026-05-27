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
    @State private var isNotesFocused = false

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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    iOSTaskEditorTitleCard(task: task)

                    iOSTaskEditorSection(title: "Task") {
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

                        iOSTaskEditorRow(label: "Estimate", systemImage: "clock.fill", color: Theme.blue) {
                            Stepper(value: $task.estimatedMinutes, in: 5...480, step: 5) {
                                Text(estimateLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                            }
                        }
                    }

                    iOSTaskEditorSection(title: "Organize") {
                        iOSTaskEditorRow(label: "List", systemImage: "tray.full.fill", color: Theme.blue) {
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

                    iOSTaskEditorSection(title: "Dates") {
                        iOSTaskEditorToggleRow(
                            label: "Do date",
                            systemImage: "sun.max.fill",
                            color: Theme.amber,
                            isOn: $hasScheduledDate
                        )
                        if hasScheduledDate {
                            DatePicker("Do", selection: $scheduledDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(Theme.amber)
                        }

                        iOSTaskEditorDivider()

                        iOSTaskEditorToggleRow(
                            label: "Due date",
                            systemImage: "flag.fill",
                            color: Theme.red,
                            isOn: $hasDueDate
                        )
                        if hasDueDate {
                            DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(Theme.red)
                        }
                    }

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

                    iOSTaskEditorSection(title: "Tags") {
                        iOSTaskTagEditorSection(
                            task: task,
                            allTags: tags,
                            newTagName: $newTagName
                        )
                    }

                    iOSTaskEditorSection(title: "Subtasks") {
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
                .padding(18)
            }
            .background(Theme.bg)
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isNotesFocused = false
                        applyDates()
                        try? modelContext.save()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isNotesFocused = false
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
                    CadenceTaskMutationSupport.delete(task, modelContext: modelContext)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the task and its subtasks.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func deleteSubtask(_ subtask: Subtask) {
        task.subtasks = (task.subtasks ?? []).filter { $0.id != subtask.id }
        modelContext.delete(subtask)
        try? modelContext.save()
    }

    private func toggleCompletion() {
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
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
