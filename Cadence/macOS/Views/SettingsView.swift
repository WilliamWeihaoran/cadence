#if os(macOS)
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(AppleAccountManager.self) private var appleAccountManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("listDetailDefaultPage") private var listDetailDefaultPage = ListDetailPage.tasks.rawValue
    @AppStorage("sidebarHiddenTabs") private var sidebarHiddenTabsRaw = ""
    @AppStorage("sidebarTabOrder") private var sidebarTabOrderRaw = ""
    @AppStorage("sidebarTabColors") private var sidebarTabColorsRaw = ""
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var selectedCategory: SettingsCategory = .appearance
    @State private var pendingDeleteArea: Area?
    @State private var pendingDeleteProject: Project?
    @State private var pendingDeleteContext: Context?
    @State private var showCreateContext = false
    @State private var editingSidebarTab: SidebarStaticDestination?
    @State private var aiAPIKeyDraft = ""

    var body: some View {
        HStack(spacing: 0) {
            SettingsRail(selectedCategory: $selectedCategory)

            Divider()
                .background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailHeader
                    selectedSectionContent
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .cadenceSoftPageBounce()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete Area?",
            isPresented: Binding(
                get: { pendingDeleteArea != nil },
                set: { if !$0 { pendingDeleteArea = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Area", role: .destructive) {
                if let area = pendingDeleteArea { deleteArea(area) }
                pendingDeleteArea = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteArea = nil }
        } message: {
            Text("This permanently deletes the area and its tasks, projects, documents, and links.")
        }
        .confirmationDialog(
            "Delete Project?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { if !$0 { pendingDeleteProject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                if let project = pendingDeleteProject { deleteProject(project) }
                pendingDeleteProject = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteProject = nil }
        } message: {
            Text("This permanently deletes the project and its tasks, documents, and links.")
        }
        .confirmationDialog(
            "Delete Context?",
            isPresented: Binding(
                get: { pendingDeleteContext != nil },
                set: { if !$0 { pendingDeleteContext = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Context", role: .destructive) {
                if let context = pendingDeleteContext { deleteContext(context) }
                pendingDeleteContext = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteContext = nil }
        } message: {
            Text("This permanently deletes the context and all its areas, projects, tasks, goals, and habits.")
        }
        .sheet(isPresented: $showCreateContext) {
            CreateContextSheet()
        }
        .sheet(item: $editingSidebarTab) { destination in
            SidebarTabEditorSheet(
                destination: destination,
                tintHex: Binding(
                    get: { destination.resolvedColorHex(from: sidebarTabColorsRaw) },
                    set: { setTabColor(destination, hex: $0) }
                ),
                isVisible: Binding(
                    get: { !hiddenTabs.contains(destination) },
                    set: { newValue in
                        let isCurrentlyVisible = !hiddenTabs.contains(destination)
                        if newValue != isCurrentlyVisible {
                            toggleTab(destination)
                        }
                    }
                )
            )
        }
    }

    private var detailHeader: some View {
        SettingsDetailHeader(category: selectedCategory) {
            switch selectedCategory {
            case .calendar:
                SettingsStatusBadge(title: calendarManager.isAuthorized ? "Connected" : "Not connected", isActive: calendarManager.isAuthorized)
            case .account:
                SettingsStatusBadge(title: appleAccountManager.isSignedIn ? "Signed in" : "Signed out", isActive: appleAccountManager.isSignedIn)
            case .dataSafety:
                SettingsStatusBadge(title: "\(StoreBackupManager.listBackups().count) backups", isActive: !StoreBackupManager.listBackups().isEmpty)
            case .ai:
                SettingsStatusBadge(title: aiSettingsManager.hasAPIKey ? "Key saved" : "No key", isActive: aiSettingsManager.hasAPIKey)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedCategory {
        case .appearance:
            SettingsAppearanceSection(
                selectedTheme: themeManager.selectedTheme,
                onSelectTheme: { themeManager.selectedTheme = $0 }
            )
        case .account:
            SettingsAccountSection(appleAccountManager: appleAccountManager)
        case .dataSafety:
            SettingsDataSafetySection()
        case .navigation:
            SettingsNavigationSection(listDetailDefaultPage: $listDetailDefaultPage)
        case .sidebar:
            SettingsSidebarSection(
                orderedSidebarTabs: orderedSidebarTabs,
                hiddenTabs: hiddenTabs,
                sidebarTabColorsRaw: sidebarTabColorsRaw,
                onEdit: { editingSidebarTab = $0 },
                onDropBefore: moveSidebarTab(_:before:)
            )
        case .contexts:
            SettingsContextsSection(
                activeContexts: contexts.filter { !$0.isArchived },
                archivedContexts: contexts.filter(\.isArchived),
                onMoveContext: moveContext(_:before:),
                onArchiveContext: { $0.isArchived = true },
                onDeleteContext: { pendingDeleteContext = $0 },
                onRestoreContext: { $0.isArchived = false },
                onCreateContext: { showCreateContext = true }
            )
        case .lists:
            SettingsListsSection(
                completedAreas: areas.filter(\.isDone),
                archivedAreas: areas.filter(\.isArchived),
                completedProjects: projects.filter(\.isDone),
                archivedProjects: projects.filter(\.isArchived),
                onReopenArea: reopenArea(_:),
                onDeleteArea: { pendingDeleteArea = $0 },
                onReopenProject: reopenProject(_:),
                onDeleteProject: { pendingDeleteProject = $0 }
            )
        case .ai:
            SettingsAISection(
                aiSettingsManager: aiSettingsManager,
                aiAPIKeyDraft: $aiAPIKeyDraft
            )
        case .calendar:
            SettingsCalendarSection(
                calendarManager: calendarManager,
                areas: areas,
                projects: projects
            )
        }
    }

    private var hiddenTabs: Set<SidebarStaticDestination> {
        Set(sidebarHiddenTabsRaw.split(separator: ",").compactMap { SidebarStaticDestination(rawValue: String($0)) })
    }

    private var orderedSidebarTabs: [SidebarStaticDestination] {
        SidebarStaticDestination.orderedDestinations(from: sidebarTabOrderRaw)
    }

    private func toggleTab(_ destination: SidebarStaticDestination) {
        var set = hiddenTabs
        if set.contains(destination) {
            set.remove(destination)
        } else {
            set.insert(destination)
        }
        sidebarHiddenTabsRaw = set.map(\.rawValue).joined(separator: ",")
    }

    private func setTabColor(_ destination: SidebarStaticDestination, hex: String) {
        var colors = SidebarStaticDestination.colorHexMap(from: sidebarTabColorsRaw)
        colors[destination] = hex
        sidebarTabColorsRaw = SidebarStaticDestination.rawColorString(from: colors)
    }

    private func moveSidebarTab(_ dragged: SidebarStaticDestination, before target: SidebarStaticDestination) {
        var current = orderedSidebarTabs
        guard let fromIndex = current.firstIndex(of: dragged),
              let toIndex = current.firstIndex(of: target) else { return }
        let moved = current.remove(at: fromIndex)
        current.insert(moved, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        sidebarTabOrderRaw = SidebarStaticDestination.rawOrderString(from: current)
    }

    private func moveContext(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        var ordered = contexts
        guard let fromIndex = ordered.firstIndex(where: { $0.id == draggedID }),
              let toIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return }

        let moved = ordered.remove(at: fromIndex)
        let insertionIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
        ordered.insert(moved, at: insertionIndex)

        for (index, context) in ordered.enumerated() {
            context.order = index
        }

        try? modelContext.save()
    }

    private func reopenArea(_ area: Area) {
        area.status = .active
        try? modelContext.save()
    }

    private func reopenProject(_ project: Project) {
        project.status = .active
        try? modelContext.save()
    }

    private func deleteContext(_ context: Context) {
        modelContext.deleteContext(context)
        try? modelContext.save()
    }

    private func deleteArea(_ area: Area) {
        modelContext.deleteArea(area)
        try? modelContext.save()
    }

    private func deleteProject(_ project: Project) {
        modelContext.deleteProject(project)
        try? modelContext.save()
    }
}
#endif
