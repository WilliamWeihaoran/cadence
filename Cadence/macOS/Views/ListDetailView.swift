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

enum ListDetailPage: String, CaseIterable, Identifiable {
    case tasks     = "Tasks"
    case kanban    = "Kanban"
    case documents = "Documents"
    case links     = "Links"
    case completed = "Completed"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tasks:     return "checkmark.square"
        case .kanban:    return "square.grid.3x2"
        case .documents: return "doc.text"
        case .links:     return "link"
        case .completed: return "list.bullet.clipboard"
        }
    }
}

private struct ListDetailView: View {
    var area: Area?
    var project: Project?

    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @AppStorage("listDetailDefaultPage") private var defaultPageRawValue = ListDetailPage.tasks.rawValue
    @State private var tab: ListDetailPage = .tasks
    @State private var showEdit = false
    @State private var keyMonitor: Any? = nil
    @State private var showArchivedKanbanColumns = false

    private var name: String     { area?.name     ?? project?.name     ?? "" }
    private var colorHex: String { area?.colorHex ?? project?.colorHex ?? "#4a9eff" }
    private var icon: String     { area?.icon     ?? project?.icon     ?? "folder.fill" }
    private var tasks: [AppTask] { area?.tasks    ?? project?.tasks    ?? [] }
    private var editableHoverID: String {
        "list-detail-\(area?.id.uuidString ?? project?.id.uuidString ?? "unknown")"
    }
    private var tabDefaultsKey: String {
        if let area {
            return "listDetailTab.area.\(area.id.uuidString)"
        }
        if let project {
            return "listDetailTab.project.\(project.id.uuidString)"
        }
        return "listDetailTab.unknown"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: colorHex))
                Text(name)
                    .font(.system(size: 22, weight: .bold))
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
                .buttonStyle(.cadencePlain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredEditableManager.beginHovering(id: editableHoverID) {
                        showEdit = true
                    }
                } else {
                    hoveredEditableManager.endHovering(id: editableHoverID)
                }
            }

            // Tab bar
            HStack(spacing: 0) {
                ForEach(ListDetailPage.allCases, id: \.self) { t in
                    TabButton(tab: t, isSelected: tab == t) { tab = t }
                }
                Spacer()
                if tab == .kanban, allowsSectionEditing {
                    Button {
                        showArchivedKanbanColumns.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showArchivedKanbanColumns ? "archivebox.fill" : "archivebox")
                                .font(.system(size: 11, weight: .semibold))
                            Text(showArchivedKanbanColumns ? "Archived" : "Show Archived")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(showArchivedKanbanColumns ? Theme.blue : Theme.dim)
                        .frame(minHeight: 32)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(showArchivedKanbanColumns ? Theme.blue.opacity(0.16) : Theme.surfaceElevated.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.cadencePlain)
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface.opacity(0.82))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.borderSubtle.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)

            Divider().background(Theme.borderSubtle)

            Group {
                switch tab {
                case .tasks:
                    ListTasksView(tasks: tasks, area: area, project: project)
                case .kanban:
                    ListSectionsKanbanView(
                        tasks: tasks,
                        area: area,
                        project: project,
                        showArchived: $showArchivedKanbanColumns
                    )
                case .documents:
                    DocumentsView(area: area, project: project)
                case .links:
                    LinksView(area: area, project: project)
                case .completed:
                    ListLogView(tasks: tasks)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
        .background(Theme.bg)
        .sheet(isPresented: $showEdit) {
            if let area = area {
                EditAreaSheet(area: area)
            } else if let project = project {
                EditProjectSheet(project: project)
            }
        }
        .onAppear {
            restoreRememberedTab()
            installKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: tab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: tabDefaultsKey)
        }
    }

    private func shortDate(_ yyyy_mm_dd: String) -> String {
        DateFormatters.shortDateString(from: yyyy_mm_dd)
    }

    private var allowsSectionEditing: Bool {
        area != nil || project != nil
    }

    private func restoreRememberedTab() {
        guard let rawValue = UserDefaults.standard.string(forKey: tabDefaultsKey),
              let rememberedTab = ListDetailPage(rawValue: rawValue) else {
            if let defaultPage = ListDetailPage(rawValue: defaultPageRawValue) {
                tab = defaultPage
            }
            return
        }
        tab = rememberedTab
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), flags.contains(.shift) else { return event }
            switch event.keyCode {
            case 33: // [
                moveTab(by: -1)
                return nil
            case 30: // ]
                moveTab(by: 1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func moveTab(by delta: Int) {
        let tabs = ListDetailPage.allCases
        guard let currentIndex = tabs.firstIndex(of: tab), !tabs.isEmpty else { return }
        let nextIndex = (currentIndex + delta + tabs.count) % tabs.count
        tab = tabs[nextIndex]
    }
}

// MARK: - Tasks View (replaces Kanban)

private struct ListTasksView: View {
    let tasks: [AppTask]
    var area: Area?
    var project: Project?
    @Environment(\.modelContext) private var modelContext
    @State private var newTitle = ""
    @State private var selectedSectionName = TaskSectionDefaults.defaultName
    @FocusState private var addFocused: Bool

    private var activeTasks: [AppTask] { tasks.filter { !$0.isDone && !$0.isCancelled }.sorted { $0.order < $1.order } }
    private var doneTasks:   [AppTask] { tasks.filter {  $0.isDone }.sorted { $0.order < $1.order } }
    private var sectionNames: [String] { area?.sectionNames ?? project?.sectionNames ?? [TaskSectionDefaults.defaultName] }

    var body: some View {
        VStack(spacing: 0) {
            // Quick-add
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.blue).font(.system(size: 13))
                TextField("Add a task…", text: $newTitle)
                    .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Theme.text)
                    .focused($addFocused).onSubmit { addTask() }
                TaskSectionPickerBadge(selection: $selectedSectionName, sections: sectionNames)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Theme.surfaceElevated)
            Divider().background(Theme.borderSubtle)

            List {
                if activeTasks.isEmpty && doneTasks.isEmpty {
                    EmptyStateView(message: "No tasks", subtitle: "Add a task above", icon: "checkmark.circle")
                        .padding(.top, 40)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(activeTasks) { task in
                    MacTaskRow(task: task, style: .list)
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .draggable("listTask:\(task.id.uuidString)")
                        .dropDestination(for: String.self) { items, _ in
                            guard let payload = items.first,
                                  payload.hasPrefix("listTask:"),
                                  let droppedID = UUID(uuidString: String(payload.dropFirst(9))),
                                  droppedID != task.id else { return false }
                            reorderTask(droppedID: droppedID, targetID: task.id)
                            return true
                        }
                }

                if !doneTasks.isEmpty {
                    Text("DONE")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.green).kerning(0.8)
                        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init())
                    ForEach(doneTasks) { task in
                        MacTaskRow(task: task, style: .list)
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
        .background(Theme.bg)
        .onAppear {
            if !sectionNames.contains(where: { $0.caseInsensitiveCompare(selectedSectionName) == .orderedSame }) {
                selectedSectionName = sectionNames.first ?? TaskSectionDefaults.defaultName
            }
        }
    }

    private func addTask() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let task = AppTask(title: t)
        task.area = area
        task.project = project
        task.context = area?.context ?? project?.context
        task.sectionName = selectedSectionName
        task.order = tasks.count
        modelContext.insert(task)
        newTitle = ""
    }

    private func reorderTask(droppedID: UUID, targetID: UUID) {
        var sorted = activeTasks
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        for (i, t) in sorted.enumerated() { t.order = i }
    }
}

// MARK: - Log View

private struct ListLogView: View {
    let tasks: [AppTask]

    private var doneTasks: [AppTask] {
        tasks.filter { $0.isDone }.sorted { $0.title < $1.title }
    }

    var body: some View {
        ZStack {
            Theme.bg

            if doneTasks.isEmpty {
                EmptyStateView(message: "No completed tasks", subtitle: "Completed tasks will appear here", icon: "checkmark.circle")
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let tab: ListDetailPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon).font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
            .frame(minWidth: 78, minHeight: 34)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle().fill(Theme.blue).frame(height: 2)
                }
            }
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
