#if os(iOS)
import SwiftData
import SwiftUI

enum iOSTaskSortMode: String, CaseIterable, Identifiable {
    case listOrder = "listOrder"
    case priority = "priority"
    case dueDate = "dueDate"
    case newest = "newest"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listOrder: return "List Order"
        case .priority: return "Priority"
        case .dueDate: return "Due Date"
        case .newest: return "Newest"
        }
    }
}

extension iOSTaskSortMode {
    var cadenceSortMode: CadenceTaskSortMode {
        switch self {
        case .listOrder: return .listOrder
        case .priority: return .priority
        case .dueDate: return .dueDate
        case .newest: return .newest
        }
    }
}

struct iOSTaskRow: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @State private var showDetail = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Button {
                    toggleCompletion()
                } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.green : Theme.dim.opacity(0.68))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
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

                    if !task.sortedTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(task.sortedTags.prefix(4)) { tag in
                                    iOSTagChip(tag: tag)
                                }

                                if task.sortedTags.count > 4 {
                                    Text("+\(task.sortedTags.count - 4)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.dim)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(Theme.surfaceElevated)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.65))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(Theme.surfaceElevated.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleCompletion()
            } label: {
                Label(task.isDone ? "Todo" : "Done",
                      systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
            }
            .tint(task.isDone ? Theme.blue : Theme.green)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                scheduleToday()
            } label: {
                Label("Today", systemImage: "sun.max.fill")
            }
            .tint(Theme.amber)

            Button {
                scheduleTomorrow()
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }
            .tint(Theme.blue)

            if !task.scheduledDate.isEmpty {
                Button {
                    clearScheduledDate()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .tint(Theme.dim)
            }
        }
        .contextMenu {
            Button {
                showDetail = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }

            Button {
                toggleCompletion()
            } label: {
                Label(task.isDone ? "Mark Todo" : "Mark Done",
                      systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
            }

            Button {
                scheduleToday()
            } label: {
                Label("Schedule Today", systemImage: "sun.max.fill")
            }

            Button {
                scheduleTomorrow()
            } label: {
                Label("Schedule Tomorrow", systemImage: "calendar")
            }

            if !task.scheduledDate.isEmpty {
                Button {
                    clearScheduledDate()
                } label: {
                    Label("Clear Do Date", systemImage: "xmark.circle")
                }
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
        .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteTask)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the task and its subtasks.")
        }
        .onAppear(perform: handlePendingDeepLink)
        .onChange(of: deepLinkManager.pendingTaskID) { _, _ in
            handlePendingDeepLink()
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
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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

    private func scheduleToday() {
        task.scheduledDate = DateFormatters.todayKey()
        try? modelContext.save()
    }

    private func scheduleTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
        try? modelContext.save()
    }

    private func clearScheduledDate() {
        task.scheduledDate = ""
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    private func deleteTask() {
        modelContext.deleteTaskForiOS(task)
    }

    private func handlePendingDeepLink() {
        guard deepLinkManager.pendingTaskID == task.id else { return }
        showDetail = true
        deepLinkManager.clearPendingTask(task.id)
    }
}

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

struct iOSTaskListRow: View {
    @Bindable var task: AppTask
    var opacity: Double = 1

    var body: some View {
        iOSTaskRow(task: task)
            .opacity(opacity)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct iOSTaskSectionHeader: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .kerning(0.8)
            .textCase(.uppercase)
            .padding(.top, 6)
    }
}

struct iOSTaskViewOptionsBar: View {
    @Binding var sortMode: iOSTaskSortMode
    @Binding var showCompleted: Bool
    var completedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort", selection: $sortMode) {
                    ForEach(iOSTaskSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Theme.blue.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showCompleted.toggle()
            } label: {
                Text(completedCount > 0 ? "Completed \(completedCount)" : "Completed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showCompleted ? Theme.text : Theme.dim)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(showCompleted ? Theme.surfaceElevated : Theme.surfaceElevated.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(completedCount == 0)
            .opacity(completedCount == 0 ? 0.45 : 1)
        }
        .tint(Theme.blue)
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

private struct iOSTagChip: View {
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

struct iOSTaskCaptureBar: View {
    let placeholder: String
    @Binding var title: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(action)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                }

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
    }
}

let iOSPanelHeaderHeight: CGFloat = 86

struct iOSPanelHeader: View {
    let eyebrow: String
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.blue.opacity(0.13))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 8)
    }
}

struct iOSEmptyPanel: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

extension ModelContext {
    func deleteTaskForiOS(_ task: AppTask) {
        let subtasks = task.subtasks ?? []
        task.subtasks = []
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }

        for subtask in subtasks {
            delete(subtask)
        }

        delete(task)
        try? save()
    }
}
#endif
