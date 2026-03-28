#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Loaders

struct AreaDetailLoader: View {
    let id: UUID
    @Query private var areas: [Area]

    var body: some View {
        if let area = areas.first(where: { $0.id == id }) {
            ListDetailView(area: area, project: nil)
        }
    }
}

struct ProjectDetailLoader: View {
    let id: UUID
    @Query private var projects: [Project]

    var body: some View {
        if let project = projects.first(where: { $0.id == id }) {
            ListDetailView(area: nil, project: project)
        }
    }
}

// MARK: - Detail View

private struct ListDetailView: View {
    var area: Area?
    var project: Project?

    @State private var tab: Tab = .tasks
    @State private var showEdit = false

    private var name: String     { area?.name     ?? project?.name     ?? "" }
    private var colorHex: String { area?.colorHex ?? project?.colorHex ?? "#4a9eff" }
    private var icon: String     { area?.icon     ?? project?.icon     ?? "folder.fill" }
    private var tasks: [AppTask] { area?.tasks    ?? project?.tasks    ?? [] }

    enum Tab: String, CaseIterable {
        case tasks     = "Tasks"
        case log       = "Log"
        case documents = "Documents"
        case links     = "Links"

        var icon: String {
            switch self {
            case .tasks:     return "checkmark.square"
            case .log:       return "list.bullet.clipboard"
            case .documents: return "doc.text"
            case .links:     return "link"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: colorHex))
                Text(name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()

                // Due date badge (projects)
                if let project = project, !project.dueDate.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 10))
                        Text(shortDate(project.dueDate)).font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Edit button
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 28, height: 28)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { t in
                    TabButton(tab: t, isSelected: tab == t) { tab = t }
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            Divider().background(Theme.borderSubtle)

            switch tab {
            case .tasks:
                ListTasksView(tasks: tasks, area: area, project: project)
            case .log:
                ListLogView(tasks: tasks)
            case .documents:
                DocumentsView(area: area, project: project)
            case .links:
                LinksView(area: area, project: project)
            }
        }
        .background(Theme.bg)
        .navigationTitle(name)
        .sheet(isPresented: $showEdit) {
            if let area = area {
                EditAreaSheet(area: area)
            } else if let project = project {
                EditProjectSheet(project: project)
            }
        }
    }

    private func shortDate(_ yyyy_mm_dd: String) -> String {
        DateFormatters.shortDateString(from: yyyy_mm_dd)
    }
}

// MARK: - Tasks View (replaces Kanban)

private struct ListTasksView: View {
    let tasks: [AppTask]
    var area: Area?
    var project: Project?
    @Environment(\.modelContext) private var modelContext
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    private var activeTasks: [AppTask] { tasks.filter { !$0.isDone && !$0.isCancelled }.sorted { $0.order < $1.order } }
    private var doneTasks:   [AppTask] { tasks.filter {  $0.isDone }.sorted { $0.order < $1.order } }

    var body: some View {
        VStack(spacing: 0) {
            // Quick-add
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.blue).font(.system(size: 13))
                TextField("Add a task…", text: $newTitle)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.text)
                    .focused($addFocused).onSubmit { addTask() }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Theme.surfaceElevated)
            Divider().background(Theme.borderSubtle)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if activeTasks.isEmpty && doneTasks.isEmpty {
                        EmptyStateView(message: "No tasks", subtitle: "Add a task above", icon: "checkmark.circle")
                            .padding(.top, 40)
                    }
                    if !activeTasks.isEmpty {
                        ForEach(activeTasks) { task in MacTaskRow(task: task) }
                    }
                    if !doneTasks.isEmpty {
                        Text("DONE")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.green).kerning(0.8)
                            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                        ForEach(doneTasks) { task in MacTaskRow(task: task) }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(Theme.bg)
    }

    private func addTask() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let task = AppTask(title: t)
        task.area = area; task.project = project; task.order = tasks.count
        modelContext.insert(task)
        newTitle = ""
    }
}

// MARK: - Log View

private struct ListLogView: View {
    let tasks: [AppTask]

    private var doneTasks: [AppTask] {
        tasks.filter { $0.isDone }.sorted { $0.title < $1.title }
    }

    var body: some View {
        if doneTasks.isEmpty {
            EmptyStateView(message: "No completed tasks", subtitle: "Completed tasks will appear here", icon: "checkmark.circle")
                .padding(.top, 40)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(doneTasks.count) COMPLETED")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .kerning(0.8)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ForEach(doneTasks) { task in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.dim)
                                    .strikethrough(true, color: Theme.dim)
                                if !task.dueDate.isEmpty {
                                    Text(task.dueDate)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.dim.opacity(0.6))
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.borderSubtle.opacity(0.4)).frame(height: 0.5)
                        }
                    }
                }
            }
            .background(Theme.bg)
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let tab: ListDetailView.Tab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon).font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle().fill(Theme.blue).frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
