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
    case planning  = "Planning"
    case documents = "Notes"
    case links     = "Links"
    case completed = "Completed"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tasks:     return "checkmark.square"
        case .kanban:    return "square.grid.3x2"
        case .planning:  return "calendar"
        case .documents: return "doc.text"
        case .links:     return "link"
        case .completed: return "list.bullet.clipboard"
        }
    }
}

private struct ListDetailView: View {
    var area: Area?
    var project: Project?

    @Environment(ListNavigationManager.self) private var listNavigationManager
    @AppStorage("listDetailDefaultPage") private var defaultPageRawValue = ListDetailPage.tasks.rawValue
    @State private var tab: ListDetailPage = .tasks
    @State private var showEdit = false
    @State private var keyMonitor: Any? = nil
    @State private var showArchivedKanbanColumns = false
    @State private var kanbanSortField: TaskSortField = .custom
    @State private var kanbanSortDirection: TaskSortDirection = .ascending
    @State private var taskGroupingMode: TaskGroupingMode = .byDate
    @State private var taskSortField: TaskSortField = .custom
    @State private var taskSortDirection: TaskSortDirection = .ascending
    @State private var highlightedKanbanSectionName: String?
    @State private var requestedEventNoteID: UUID?

    private var kanbanUDKey: String {
        if let a = area { return "kanban_\(a.id.uuidString)" }
        if let p = project { return "kanban_\(p.id.uuidString)" }
        return "kanban_generic"
    }

    private var taskUDKeyPrefix: String {
        if let a = area { return "list_\(a.id.uuidString)" }
        if let p = project { return "list_\(p.id.uuidString)" }
        return "list_generic"
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
        ListDetailChromeView(
            area: area,
            project: project,
            tab: $tab,
            showEdit: $showEdit,
            showArchivedKanbanColumns: $showArchivedKanbanColumns,
            kanbanSortField: $kanbanSortField,
            kanbanSortDirection: $kanbanSortDirection,
            taskSortField: $taskSortField,
            taskSortDirection: $taskSortDirection,
            taskGroupingMode: $taskGroupingMode,
            highlightedKanbanSectionName: highlightedKanbanSectionName,
            requestedEventNoteID: $requestedEventNoteID
        )
            .modifier(ListDetailLifecycleModifier(
                navigationToken: listNavigationManager.request?.token,
                onAppearAction: {
                    restoreRememberedTab()
                    applyPendingNavigationIfNeeded()
                    installKeyMonitorIfNeeded()
                    restoreTaskAndKanbanControls()
                },
                onDisappearAction: removeKeyMonitor,
                onNavigationChange: applyPendingNavigationIfNeeded
            ))
            .modifier(ListDetailTabAndKanbanPersistenceModifier(
                tab: $tab,
                kanbanSortField: $kanbanSortField,
                kanbanSortDirection: $kanbanSortDirection,
                tabDefaultsKey: tabDefaultsKey,
                kanbanUDKey: kanbanUDKey
            ))
            .modifier(ListDetailTaskPreferencePersistenceModifier(
                taskSortField: $taskSortField,
                taskSortDirection: $taskSortDirection,
                taskGroupingMode: $taskGroupingMode,
                taskUDKeyPrefix: taskUDKeyPrefix
            ))
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
        highlightedKanbanSectionName = request.page == .kanban ? request.sectionName : nil
        requestedEventNoteID = request.page == .documents ? request.eventNoteID : nil
    }

    private func restoreTaskAndKanbanControls() {
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: "\(kanbanUDKey)_sortField"), let v = TaskSortField(rawValue: raw) {
            kanbanSortField = v
        }
        if let raw = ud.string(forKey: "\(kanbanUDKey)_sortDir"), let v = TaskSortDirection(rawValue: raw) {
            kanbanSortDirection = v
        }
        if let raw = ud.string(forKey: "\(taskUDKeyPrefix)_sortField"), let v = TaskSortField(rawValue: raw) {
            taskSortField = v
        }
        if let raw = ud.string(forKey: "\(taskUDKeyPrefix)_sortDir"), let v = TaskSortDirection(rawValue: raw) {
            taskSortDirection = v
        }
        if let raw = ud.string(forKey: "\(taskUDKeyPrefix)_grouping"), let v = TaskGroupingMode(rawValue: raw) {
            taskGroupingMode = v
        }
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

private struct ListDetailChromeView: View {
    var area: Area?
    var project: Project?
    @Binding var tab: ListDetailPage
    @Binding var showEdit: Bool
    @Binding var showArchivedKanbanColumns: Bool
    @Binding var kanbanSortField: TaskSortField
    @Binding var kanbanSortDirection: TaskSortDirection
    @Binding var taskSortField: TaskSortField
    @Binding var taskSortDirection: TaskSortDirection
    @Binding var taskGroupingMode: TaskGroupingMode
    let highlightedKanbanSectionName: String?
    @Binding var requestedEventNoteID: UUID?

    @Environment(HoveredEditableManager.self) private var hoveredEditableManager

    private var name: String { area?.name ?? project?.name ?? "" }
    private var colorHex: String { area?.colorHex ?? project?.colorHex ?? "#4a9eff" }
    private var icon: String { area?.icon ?? project?.icon ?? "folder.fill" }
    private var tasks: [AppTask] { area?.tasks ?? project?.tasks ?? [] }
    private var allowsSectionEditing: Bool { area != nil || project != nil }
    private var editableHoverID: String {
        "list-detail-\(area?.id.uuidString ?? project?.id.uuidString ?? "unknown")"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ListDetailTabBarView(
                tab: $tab,
                showArchivedKanbanColumns: $showArchivedKanbanColumns,
                kanbanSortField: $kanbanSortField,
                kanbanSortDirection: $kanbanSortDirection,
                taskSortField: $taskSortField,
                taskSortDirection: $taskSortDirection,
                taskGroupingMode: $taskGroupingMode,
                allowsSectionEditing: allowsSectionEditing
            )

            Divider().background(Theme.borderSubtle)

            pageBody
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
            editSheetContent
        }
    }

    private var header: some View {
        DesktopPageHeader(
            title: name,
            systemImage: icon,
            tint: Color(hex: colorHex)
        ) {
            HStack(spacing: 8) {
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

                CadenceIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "Edit \(name)",
                    tint: Color(hex: colorHex),
                    action: { showEdit = true }
                )
            }
        }
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
    }

    @ViewBuilder
    private var editSheetContent: some View {
        if let area {
            EditAreaSheet(area: area)
        } else if let project {
            EditProjectSheet(project: project)
        }
    }

    private var pageBody: AnyView {
        switch tab {
        case .tasks:
            return AnyView(ListTasksView(
                tasks: tasks,
                area: area,
                project: project,
                sortField: taskSortField,
                sortDirection: taskSortDirection,
                groupingMode: taskGroupingMode
            ))
        case .kanban:
            return AnyView(ListSectionsKanbanView(
                tasks: tasks,
                universeTasks: tasks,
                area: area,
                project: project,
                showArchived: $showArchivedKanbanColumns,
                sortField: kanbanSortField,
                sortDirection: kanbanSortDirection,
                highlightedSectionName: highlightedKanbanSectionName
            ))
        case .planning:
            return AnyView(ListPlanningView(tasks: tasks, area: area, project: project))
        case .documents:
            return AnyView(ListNotesView(area: area, project: project, requestedEventNoteID: $requestedEventNoteID))
        case .links:
            return AnyView(LinksView(area: area, project: project))
        case .completed:
            return AnyView(ListLogView(tasks: tasks))
        }
    }
}

private struct ListDetailLifecycleModifier: ViewModifier {
    let navigationToken: UUID?
    let onAppearAction: () -> Void
    let onDisappearAction: () -> Void
    let onNavigationChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppearAction)
            .onDisappear(perform: onDisappearAction)
            .onChange(of: navigationToken) { _, _ in
                onNavigationChange()
            }
    }
}

private struct ListDetailTabAndKanbanPersistenceModifier: ViewModifier {
    @Binding var tab: ListDetailPage
    @Binding var kanbanSortField: TaskSortField
    @Binding var kanbanSortDirection: TaskSortDirection

    let tabDefaultsKey: String
    let kanbanUDKey: String

    func body(content: Content) -> some View {
        content
            .onChange(of: tab) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: tabDefaultsKey)
            }
            .onChange(of: kanbanSortField) { _, value in
                UserDefaults.standard.set(value.rawValue, forKey: "\(kanbanUDKey)_sortField")
            }
            .onChange(of: kanbanSortDirection) { _, value in
                UserDefaults.standard.set(value.rawValue, forKey: "\(kanbanUDKey)_sortDir")
            }
    }
}

private struct ListDetailTaskPreferencePersistenceModifier: ViewModifier {
    @Binding var taskSortField: TaskSortField
    @Binding var taskSortDirection: TaskSortDirection
    @Binding var taskGroupingMode: TaskGroupingMode

    let taskUDKeyPrefix: String

    func body(content: Content) -> some View {
        content
            .onChange(of: taskSortField) { _, value in
                UserDefaults.standard.set(value.rawValue, forKey: "\(taskUDKeyPrefix)_sortField")
            }
            .onChange(of: taskSortDirection) { _, value in
                UserDefaults.standard.set(value.rawValue, forKey: "\(taskUDKeyPrefix)_sortDir")
            }
            .onChange(of: taskGroupingMode) { _, value in
                UserDefaults.standard.set(value.rawValue, forKey: "\(taskUDKeyPrefix)_grouping")
            }
    }
}

private struct ListDetailTabBarView: View {
    @Binding var tab: ListDetailPage
    @Binding var showArchivedKanbanColumns: Bool
    @Binding var kanbanSortField: TaskSortField
    @Binding var kanbanSortDirection: TaskSortDirection
    @Binding var taskSortField: TaskSortField
    @Binding var taskSortDirection: TaskSortDirection
    @Binding var taskGroupingMode: TaskGroupingMode
    let allowsSectionEditing: Bool

    var body: some View {
        HStack(spacing: 12) {
            tabCluster
            Spacer(minLength: 16)
            trailingControls
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
    }

    private var tabCluster: some View {
        HStack(spacing: 4) {
            ForEach(ListDetailPage.allCases, id: \.self) { page in
                TabButton(tab: page, isSelected: tab == page) {
                    tab = page
                }
            }
        }
        .padding(4)
        .background(Theme.surfaceElevated.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var trailingControls: some View {
        if tab == .tasks {
            HStack(spacing: 6) {
                CadenceEnumPickerBadge(title: "Sort", selection: $taskSortField)
                CadenceEnumPickerBadge(title: "Order", selection: $taskSortDirection)
                CadenceEnumPickerBadge(title: "Group", selection: $taskGroupingMode)
            }
            .padding(.trailing, 4)
        } else if tab == .kanban, allowsSectionEditing {
            HStack(spacing: 6) {
                CadenceEnumPickerBadge(title: "Sort", selection: $kanbanSortField)
                CadenceEnumPickerBadge(title: "Order", selection: $kanbanSortDirection)
                archivedColumnsButton
            }
            .padding(.trailing, 4)
        }
    }

    private var archivedColumnsButton: some View {
        Button {
            showArchivedKanbanColumns.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showArchivedKanbanColumns ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(showArchivedKanbanColumns ? "Archived" : "Show Archived")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(showArchivedKanbanColumns ? Theme.blue : Theme.dim)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(showArchivedKanbanColumns ? Theme.blue.opacity(0.16) : Theme.surfaceElevated.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
    }
}

#endif
