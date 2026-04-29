#if os(iOS)
import SwiftData
import SwiftUI

enum iOSListRoute: Hashable {
    case area(UUID)
    case project(UUID)
}

struct iOSListsView: View {
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

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
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
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
}

struct iOSListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    let area: Area?
    let project: Project?
    @State private var newTitle = ""

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

    private var activeTasks: [AppTask] {
        filteredTasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted { lhs, rhs in
                if lhs.resolvedSectionName != rhs.resolvedSectionName {
                    return sectionRank(lhs.resolvedSectionName) < sectionRank(rhs.resolvedSectionName)
                }
                return lhs.order < rhs.order
            }
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
            .padding(16)

            if activeTasks.isEmpty && completedTasks.isEmpty {
                iOSEmptyPanel(
                    systemImage: "checklist",
                    title: "No tasks here yet",
                    subtitle: "Add a task above or move one here from Inbox."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(sectionGroups, id: \.name) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.dim)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 4)

                                ForEach(group.tasks) { task in
                                    iOSTaskRow(task: task)
                                }
                            }
                        }

                        if !completedTasks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Completed")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.green)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 4)

                                ForEach(completedTasks.prefix(12)) { task in
                                    iOSTaskRow(task: task)
                                        .opacity(0.62)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
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
