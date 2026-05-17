#if os(iOS)
import SwiftData
import SwiftUI

enum iOSListRoute: Hashable {
    case area(UUID)
    case project(UUID)
}

struct iOSListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var editorMode: iOSListEditorMode?

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    var body: some View {
        List {
            if !activeAreas.isEmpty {
                Section("Areas") {
                    ForEach(activeAreas) { area in
                        NavigationLink(value: iOSListRoute.area(area.id)) {
                            iOSListPickerRow(
                                title: area.name,
                                subtitle: area.context?.name,
                                icon: area.icon,
                                colorHex: area.colorHex,
                                count: activeTaskCount(for: area)
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                archive(area)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                        .contextMenu {
                            Button {
                                editorMode = .editArea(area)
                            } label: {
                                Label("Edit Area", systemImage: "square.and.pencil")
                            }

                            Button(role: .destructive) {
                                archive(area)
                            } label: {
                                Label("Archive Area", systemImage: "archivebox")
                            }
                        }
                    }
                }
            }

            if !activeProjects.isEmpty {
                Section("Projects") {
                    ForEach(activeProjects) { project in
                        NavigationLink(value: iOSListRoute.project(project.id)) {
                            iOSListPickerRow(
                                title: project.name,
                                subtitle: [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / "),
                                icon: project.icon,
                                colorHex: project.colorHex,
                                count: activeTaskCount(for: project)
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                archive(project)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                        .contextMenu {
                            Button {
                                editorMode = .editProject(project)
                            } label: {
                                Label("Edit Project", systemImage: "square.and.pencil")
                            }

                            Button(role: .destructive) {
                                archive(project)
                            } label: {
                                Label("Archive Project", systemImage: "archivebox")
                            }
                        }
                    }
                }
            }

            if activeAreas.isEmpty && activeProjects.isEmpty {
                iOSEmptyPanel(
                    systemImage: "folder",
                    title: "No active lists",
                    subtitle: "Areas and projects created on Mac will appear here."
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Lists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editorMode = .newArea
                    } label: {
                        Label("New Area", systemImage: "folder.badge.plus")
                    }

                    Button {
                        editorMode = .newProject
                    } label: {
                        Label("New Project", systemImage: "checklist")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .sheet(item: $editorMode) { mode in
            iOSListEditorSheet(mode: mode)
        }
        .navigationDestination(for: iOSListRoute.self) { route in
            switch route {
            case .area(let id):
                if let area = areas.first(where: { $0.id == id }) {
                    iOSListDetailView(area: area)
                } else {
                    iOSMissingListView()
                }
            case .project(let id):
                if let project = projects.first(where: { $0.id == id }) {
                    iOSListDetailView(project: project)
                } else {
                    iOSMissingListView()
                }
            }
        }
    }

    private func activeTaskCount(for area: Area) -> Int {
        (area.tasks ?? []).filter { !$0.isDone && !$0.isCancelled }.count
    }

    private func activeTaskCount(for project: Project) -> Int {
        (project.tasks ?? []).filter { !$0.isDone && !$0.isCancelled }.count
    }

    private func archive(_ area: Area) {
        area.status = .archived
        try? modelContext.save()
    }

    private func archive(_ project: Project) {
        project.status = .archived
        try? modelContext.save()
    }
}

struct iOSListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    let area: Area?
    let project: Project?
    @State private var newTitle = ""
    @State private var editorMode: iOSListEditorMode?

    init(area: Area) {
        self.area = area
        self.project = nil
    }

    init(project: Project) {
        self.area = nil
        self.project = project
    }

    private var title: String {
        area?.name ?? project?.name ?? "List"
    }

    private var subtitle: String {
        if let area {
            return area.context?.name ?? "Area"
        }
        if let project {
            return [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / ")
        }
        return ""
    }

    private var accent: Color {
        Color(hex: area?.colorHex ?? project?.colorHex ?? "#4a9eff")
    }

    @AppStorage("ios.listDetail.sortMode") private var sortModeRaw = iOSTaskSortMode.listOrder.rawValue
    @AppStorage("ios.listDetail.showCompleted") private var showCompleted = false

    private var sortMode: iOSTaskSortMode {
        get { iOSTaskSortMode(rawValue: sortModeRaw) ?? .listOrder }
        set { sortModeRaw = newValue.rawValue }
    }

    private var activeTasks: [AppTask] {
        filteredTasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted(by: sortTasks)
    }

    private var completedTasks: [AppTask] {
        filteredTasks
            .filter { $0.isDone }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private var filteredTasks: [AppTask] {
        if let area {
            return allTasks.filter { $0.area?.id == area.id }
        }
        if let project {
            return allTasks.filter { $0.project?.id == project.id }
        }
        return []
    }

    private var sectionNames: [String] {
        var names = area?.sectionNames ?? project?.sectionNames ?? [TaskSectionDefaults.defaultName]
        for task in activeTasks {
            let name = task.resolvedSectionName
            if !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        return names
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    taskColumn
                        .frame(minWidth: 390, idealWidth: 500, maxWidth: 600)

                    Divider().background(Theme.borderSubtle)

                    iOSListNotesPanel(area: area, project: project)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        taskColumn
                            .frame(minHeight: 420)

                        iOSListNotesPanel(area: area, project: project)
                            .frame(minHeight: 430)
                    }
                    .padding(14)
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let area {
                        editorMode = .editArea(area)
                    } else if let project {
                        editorMode = .editProject(project)
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            iOSListEditorSheet(mode: mode)
        }
    }

    private var taskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(
                eyebrow: subtitle.isEmpty ? (area == nil ? "Project" : "Area") : subtitle,
                title: title,
                count: activeTasks.count
            )

            Divider().background(Theme.borderSubtle)

            iOSTaskCaptureBar(
                placeholder: "Add a task to \(title)...",
                title: $newTitle,
                action: captureTask
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)

            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedTasks.count
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            if activeTasks.isEmpty && (!showCompleted || completedTasks.isEmpty) {
                iOSEmptyPanel(
                    systemImage: "checklist",
                    title: "No tasks here yet",
                    subtitle: "Add a task above or move one here from Inbox."
                )
            } else {
                List {
                    ForEach(sectionGroups, id: \.name) { group in
                        Section {
                            ForEach(group.tasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: group.name, color: Theme.dim)
                        }
                    }

                    if showCompleted && !completedTasks.isEmpty {
                        Section {
                            ForEach(completedTasks.prefix(12)) { task in
                                iOSTaskListRow(task: task, opacity: 0.62)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Completed", color: Theme.green)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
            }
        }
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
        }
    }

    private var sectionGroups: [(name: String, tasks: [AppTask])] {
        sectionNames.compactMap { section in
            let tasks = activeTasks.filter {
                $0.resolvedSectionName.caseInsensitiveCompare(section) == .orderedSame
            }
            return tasks.isEmpty ? nil : (section, tasks)
        }
    }

    private func captureTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let task = AppTask(title: trimmed)
        task.estimatedMinutes = 30
        task.sectionName = TaskSectionDefaults.defaultName
        task.order = nextTaskOrder()
        if let area {
            task.area = area
            task.project = nil
            task.context = area.context
        } else if let project {
            task.project = project
            task.area = nil
            task.context = project.context ?? project.area?.context
        }
        modelContext.insert(task)
        try? modelContext.save()
        newTitle = ""
    }

    private func nextTaskOrder() -> Int {
        (filteredTasks.map(\.order).max() ?? -1) + 1
    }

    private func sectionRank(_ name: String) -> Int {
        sectionNames.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame } ?? Int.max
    }

    private func sortTasks(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        switch sortMode {
        case .listOrder:
            if lhs.resolvedSectionName != rhs.resolvedSectionName {
                return sectionRank(lhs.resolvedSectionName) < sectionRank(rhs.resolvedSectionName)
            }
            return lhs.order < rhs.order
        case .priority:
            if lhs.priority != rhs.priority {
                return priorityRank(lhs.priority) > priorityRank(rhs.priority)
            }
            return lhs.order < rhs.order
        case .dueDate:
            if lhs.dueDate != rhs.dueDate {
                if lhs.dueDate.isEmpty { return false }
                if rhs.dueDate.isEmpty { return true }
                return lhs.dueDate < rhs.dueDate
            }
            return lhs.order < rhs.order
        case .newest:
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}

private enum iOSListEditorMode: Identifiable {
    case newArea
    case newProject
    case editArea(Area)
    case editProject(Project)

    var id: String {
        switch self {
        case .newArea: return "new-area"
        case .newProject: return "new-project"
        case .editArea(let area): return "area-\(area.id)"
        case .editProject(let project): return "project-\(project.id)"
        }
    }
}

private struct iOSListEditorSheet: View {
    let mode: iOSListEditorMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var name = ""
    @State private var details = ""
    @State private var icon = ""
    @State private var colorHex = ""
    @State private var selectedContextID = "none"
    @State private var selectedAreaID = "none"
    @State private var sectionText = TaskSectionDefaults.defaultName
    @State private var hideEmptyDueDates = true
    @State private var hasLoaded = false

    private var isProjectMode: Bool {
        switch mode {
        case .newProject, .editProject:
            return true
        case .newArea, .editArea:
            return false
        }
    }

    private var isEditing: Bool {
        switch mode {
        case .editArea, .editProject:
            return true
        case .newArea, .newProject:
            return false
        }
    }

    private var activeContexts: [Context] {
        contexts.filter { !$0.isArchived }
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSections: [String] {
        let values = sectionText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? [TaskSectionDefaults.defaultName] : values
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isProjectMode ? "Project" : "Area") {
                    TextField(isProjectMode ? "Project name" : "Area name", text: $name)
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Appearance") {
                    TextField("SF Symbol", text: $icon)
                        .textInputAutocapitalization(.never)
                    TextField("Color hex", text: $colorHex)
                        .textInputAutocapitalization(.never)
                }

                Section("Organize") {
                    Picker("Context", selection: $selectedContextID) {
                        Text("None").tag("none")
                        ForEach(activeContexts) { context in
                            Text(context.name.isEmpty ? "Untitled Context" : context.name)
                                .tag(context.id.uuidString)
                        }
                    }

                    if isProjectMode {
                        Picker("Area", selection: $selectedAreaID) {
                            Text("None").tag("none")
                            ForEach(activeAreas) { area in
                                Text(area.name.isEmpty ? "Untitled Area" : area.name)
                                    .tag(area.id.uuidString)
                            }
                        }
                    }
                }

                Section("Sections") {
                    TextEditor(text: $sectionText)
                        .frame(minHeight: 120)
                    Toggle("Hide empty due dates", isOn: $hideEmptyDueDates)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(isEditing ? "Edit List" : "New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        switch mode {
        case .newArea:
            name = ""
            details = ""
            icon = "folder.fill"
            colorHex = "#4a9eff"
        case .newProject:
            name = ""
            details = ""
            icon = "checklist"
            colorHex = "#4ecb71"
        case .editArea(let area):
            name = area.name
            details = area.desc
            icon = area.icon
            colorHex = area.colorHex
            selectedContextID = area.context?.id.uuidString ?? "none"
            sectionText = area.sectionNames.joined(separator: "\n")
            hideEmptyDueDates = area.hideDueDateIfEmpty
        case .editProject(let project):
            name = project.name
            details = project.desc
            icon = project.icon
            colorHex = project.colorHex
            selectedContextID = project.context?.id.uuidString ?? "none"
            selectedAreaID = project.area?.id.uuidString ?? "none"
            sectionText = project.sectionNames.joined(separator: "\n")
            hideEmptyDueDates = project.hideDueDateIfEmpty
        }
    }

    private func save() {
        switch mode {
        case .newArea:
            let area = Area(name: trimmedName, context: selectedContext, colorHex: normalizedColor, icon: normalizedIcon)
            area.desc = details
            area.order = nextAreaOrder()
            area.sectionNames = normalizedSections
            area.hideDueDateIfEmpty = hideEmptyDueDates
            modelContext.insert(area)
        case .newProject:
            let project = Project(name: trimmedName, context: selectedContext, area: selectedArea, colorHex: normalizedColor)
            project.desc = details
            project.icon = normalizedIcon
            project.order = nextProjectOrder()
            project.sectionNames = normalizedSections
            project.hideDueDateIfEmpty = hideEmptyDueDates
            modelContext.insert(project)
        case .editArea(let area):
            area.name = trimmedName
            area.desc = details
            area.icon = normalizedIcon
            area.colorHex = normalizedColor
            area.context = selectedContext
            area.sectionNames = normalizedSections
            area.hideDueDateIfEmpty = hideEmptyDueDates
        case .editProject(let project):
            project.name = trimmedName
            project.desc = details
            project.icon = normalizedIcon
            project.colorHex = normalizedColor
            project.context = selectedContext
            project.area = selectedArea
            project.sectionNames = normalizedSections
            project.hideDueDateIfEmpty = hideEmptyDueDates
        }

        try? modelContext.save()
        dismiss()
    }

    private var selectedContext: Context? {
        guard let id = UUID(uuidString: selectedContextID) else { return nil }
        return contexts.first { $0.id == id }
    }

    private var selectedArea: Area? {
        guard let id = UUID(uuidString: selectedAreaID) else { return nil }
        return areas.first { $0.id == id }
    }

    private var normalizedIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isProjectMode ? "checklist" : "folder.fill"
    }

    private var normalizedColor: String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else {
            return isProjectMode ? "#4ecb71" : "#4a9eff"
        }
        return trimmed
    }

    private func nextAreaOrder() -> Int {
        (areas.map(\.order).max() ?? -1) + 1
    }

    private func nextProjectOrder() -> Int {
        (projects.map(\.order).max() ?? -1) + 1
    }
}

private struct iOSListPickerRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled" : title)
                    .foregroundStyle(Theme.text)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
        }
    }
}

private struct iOSListNotesPanel: View {
    @Environment(\.modelContext) private var modelContext
    let area: Area?
    let project: Project?
    @State private var note: Note?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "List Notes", title: "Notes")
            Divider().background(Theme.borderSubtle)

            if let note {
                TextEditor(text: Binding(
                    get: { note.content },
                    set: { update(note, content: $0) }
                ))
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
                .padding(12)
            } else {
                ProgressView()
                    .tint(Theme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
        .onAppear(perform: loadOrCreateNote)
    }

    private func loadOrCreateNote() {
        let descriptor = FetchDescriptor<Note>()
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        if let area {
            if let existing = notes.first(where: { $0.kind == .list && $0.area?.id == area.id && $0.project == nil }) {
                note = existing
                return
            }
            let created = Note(kind: .list, title: area.name, area: area)
            modelContext.insert(created)
            try? modelContext.save()
            note = created
            return
        }

        if let project {
            if let existing = notes.first(where: { $0.kind == .list && $0.project?.id == project.id }) {
                note = existing
                return
            }
            let created = Note(kind: .list, title: project.name, project: project)
            modelContext.insert(created)
            try? modelContext.save()
            note = created
        }
    }

    private func update(_ note: Note, content: String) {
        note.content = content
        note.updatedAt = Date()
        try? modelContext.save()
    }
}
#endif
