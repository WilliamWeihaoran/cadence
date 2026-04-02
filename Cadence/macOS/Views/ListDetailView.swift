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
    @Environment(ListNavigationManager.self) private var listNavigationManager
    @AppStorage("listDetailDefaultPage") private var defaultPageRawValue = ListDetailPage.tasks.rawValue
    @State private var tab: ListDetailPage = .tasks
    @State private var showEdit = false
    @State private var keyMonitor: Any? = nil
    @State private var showArchivedKanbanColumns = false
    @State private var kanbanSortField: TaskSortField = .custom
    @State private var kanbanSortDirection: TaskSortDirection = .ascending

    private var kanbanUDKey: String {
        if let a = area { return "kanban_\(a.id.uuidString)" }
        if let p = project { return "kanban_\(p.id.uuidString)" }
        return "kanban_generic"
    }

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
                        Text(DateFormatters.shortDateString(from: project.dueDate)).font(.system(size: 11))
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
                    CadenceEnumPickerBadge(title: "Sort", selection: $kanbanSortField)
                    CadenceEnumPickerBadge(title: "Order", selection: $kanbanSortDirection)
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
                    kanbanBody
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
            applyPendingNavigationIfNeeded()
            installKeyMonitorIfNeeded()
            let ud = UserDefaults.standard
            if let raw = ud.string(forKey: "\(kanbanUDKey)_sortField"), let v = TaskSortField(rawValue: raw) { kanbanSortField = v }
            if let raw = ud.string(forKey: "\(kanbanUDKey)_sortDir"), let v = TaskSortDirection(rawValue: raw) { kanbanSortDirection = v }
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: tab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: tabDefaultsKey)
        }
        .onChange(of: listNavigationManager.request?.token) { _, _ in
            applyPendingNavigationIfNeeded()
        }
        .onChange(of: kanbanSortField) { _, v in UserDefaults.standard.set(v.rawValue, forKey: "\(kanbanUDKey)_sortField") }
        .onChange(of: kanbanSortDirection) { _, v in UserDefaults.standard.set(v.rawValue, forKey: "\(kanbanUDKey)_sortDir") }
    }

    private var allowsSectionEditing: Bool {
        area != nil || project != nil
    }

    @ViewBuilder
    private var kanbanBody: some View {
        ListSectionsKanbanView(
            tasks: tasks,
            universeTasks: tasks,
            area: area,
            project: project,
            showArchived: $showArchivedKanbanColumns,
            sortField: kanbanSortField,
            sortDirection: kanbanSortDirection
        )
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

    private func applyPendingNavigationIfNeeded() {
        guard let request = listNavigationManager.consumeIfMatches(
            areaID: area?.id,
            projectID: project?.id
        ) else { return }
        tab = request.page
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

#endif
