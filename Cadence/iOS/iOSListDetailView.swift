#if os(iOS)
import SwiftData
import SwiftUI

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
        CadenceTaskQuerySupport.completedTasks(from: filteredTasks)
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
                return CadenceTaskQuerySupport.priorityRank(lhs.priority) > CadenceTaskQuerySupport.priorityRank(rhs.priority)
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
}
#endif
