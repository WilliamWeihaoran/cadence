#if os(iOS)
import SwiftData
import SwiftUI

enum iOSListDetailPage: String, CaseIterable, Identifiable {
    case tasks = "Tasks"
    case kanban = "Kanban"
    case planning = "Planning"
    case notes = "Notes"
    case links = "Links"
    case completed = "Completed"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .tasks: return "checkmark.square"
        case .kanban: return "square.grid.3x2"
        case .planning: return "calendar"
        case .notes: return "note.text"
        case .links: return "link"
        case .completed: return "checkmark.circle.fill"
        }
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
    @State private var page: iOSListDetailPage = .tasks

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

    @AppStorage("ios.listDetail.sortMode") private var sortModeRaw = CadenceTaskSortMode.listOrder.rawValue
    @AppStorage("ios.listDetail.showCompleted") private var showCompleted = false

    private var sortMode: CadenceTaskSortMode {
        get { CadenceTaskSortMode(rawValue: sortModeRaw) ?? .listOrder }
        set { sortModeRaw = newValue.rawValue }
    }

    private var activeTasks: [AppTask] {
        CadenceTaskQuerySupport.activeTasks(
            from: filteredTasks,
            sortMode: sortMode,
            sectionNames: configuredSectionNames
        )
    }

    private var completedTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTasks(from: filteredTasks)
    }

    private var filteredTasks: [AppTask] {
        CadenceTaskQuerySupport.tasks(for: area, project: project, in: allTasks)
    }

    private var configuredSectionNames: [String] {
        area?.sectionNames ?? project?.sectionNames ?? [TaskSectionDefaults.defaultName]
    }

    private var sectionNames: [String] {
        var names = configuredSectionNames
        for task in activeTasks {
            let name = task.resolvedSectionName
            if !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        return names
    }

    var body: some View {
        VStack(spacing: 0) {
            iOSListDetailPagePicker(page: $page)
                .padding(.horizontal, horizontalSizeClass == .regular ? 18 : 12)
                .padding(.top, horizontalSizeClass == .regular ? 12 : 8)
                .padding(.bottom, 10)

            Divider().background(Theme.borderSubtle)

            pageBody
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

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case .tasks:
            taskColumn
        case .kanban:
            iOSListKanbanPanel(
                title: title,
                tasks: activeTasks,
                sectionNames: sectionNames,
                accent: accent
            )
        case .planning:
            iOSListPlanningPanel(tasks: activeTasks)
        case .notes:
            iOSListNotesPanel(area: area, project: project)
        case .links:
            iOSListLinksPanel(area: area, project: project)
        case .completed:
            iOSListCompletedPanel(tasks: completedTasks)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sectionGroups: [(name: String, tasks: [AppTask])] {
        CadenceTaskQuerySupport.sectionGroups(from: activeTasks, sectionNames: sectionNames)
            .map { ($0.title, $0.tasks) }
    }

    private func captureTask() {
        guard (try? CadenceTaskMutationSupport.insertTask(
            title: newTitle,
            allTasks: filteredTasks,
            modelContext: modelContext,
            configure: { task in
                CadenceTaskMutationSupport.assignContainer(
                    task,
                    area: area,
                    project: project,
                    sectionName: TaskSectionDefaults.defaultName,
                    allTasks: filteredTasks,
                    updateOrder: false
                )
            }
        )) != nil else { return }
        newTitle = ""
    }

}
#endif
