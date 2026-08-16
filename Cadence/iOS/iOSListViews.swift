#if os(iOS)
import SwiftData
import SwiftUI

enum iOSListRoute: Hashable {
    case area(UUID)
    case project(UUID)
}

struct iOSListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var editorMode: iOSListEditorMode?
    @State private var selectedRoute: iOSListRoute?

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var archivedAreas: [Area] {
        areas.filter(\.isArchived)
    }

    private var archivedProjects: [Project] {
        projects.filter(\.isArchived)
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var firstActiveRoute: iOSListRoute? {
        if let area = activeAreas.first {
            return .area(area.id)
        }
        if let project = activeProjects.first {
            return .project(project.id)
        }
        return nil
    }

    private var effectiveSelectedRoute: iOSListRoute? {
        guard let selectedRoute, containsActive(route: selectedRoute) else {
            return firstActiveRoute
        }
        return selectedRoute
    }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                regularSplitLayout
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Theme.bg)
        .sheet(item: $editorMode) { mode in
            iOSListEditorSheet(mode: mode)
        }
        .navigationDestination(for: iOSListRoute.self) { route in
            listDetail(for: route)
        }
        .onAppear(perform: selectDefaultListIfNeeded)
        .onChange(of: activeRouteKey) { _, _ in
            selectDefaultListIfNeeded()
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The nav bar above is hidden (see `.toolbar(.hidden…)` on the body), which is what
            // left iPhone with no way back other than the swipe gesture. The chevron lives here.
            iOSListsPageHeader(
                count: activeAreas.count + activeProjects.count,
                onBack: { dismiss() }
            )

            iOSListCreateButtonsRow(editorMode: $editorMode)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            iOSListHairline()

            compactList
        }
        .background(Theme.bg)
    }

    /// `.plain` with the palette showing through, not the default inset-grouped `List`: grouped
    /// style paints its own `secondarySystemGroupedBackground` plates and its own grey headers,
    /// which is a second, non-palette surface stacked on the page background.
    private var compactList: some View {
        List {
            activeAreaSection
            activeProjectSection
            archivedSection
            emptyStateSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
    }

    /// The same `CadenceRegularSplitLayout` proportion Goals, Habits and Focus use. It used to be
    /// `minWidth: 300, idealWidth: 340, maxWidth: 380` here — the only one of the four surfaces that
    /// declared a maximum at all, and the reason this page was the least starved of them. Measuring
    /// against the pane rather than declaring a range is what keeps an 11" iPad's 632pt from landing
    /// on a 315pt chooser beside a 316pt list.
    private var regularSplitLayout: some View {
        iOSFeatureSplitLayout {
            iOSListsRegularPane(
                activeAreas: activeAreas,
                activeProjects: activeProjects,
                archivedAreas: archivedAreas,
                archivedProjects: archivedProjects,
                selectedRoute: $selectedRoute,
                editorMode: $editorMode,
                projectSubtitle: projectSubtitle,
                archiveArea: archive,
                archiveProject: archive,
                restoreArea: restore,
                restoreProject: restore
            )
        } detail: {
            if let route = effectiveSelectedRoute {
                listDetail(for: route)
                    .id(route)
            } else {
                iOSEmptyPanel(
                    systemImage: "folder",
                    title: "Nothing to show yet",
                    subtitle: "Once you add an area or project, it'll open here."
                )
                .background(Theme.bg)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var activeAreaSection: some View {
        if !activeAreas.isEmpty {
            Section {
                ForEach(activeAreas) { area in
                    areaRow(area)
                }
            } header: {
                iOSListSectionHeader(title: "Areas")
            }
        }
    }

    private func areaRow(_ area: Area) -> some View {
        NavigationLink(value: iOSListRoute.area(area.id)) {
            iOSListPickerRow(
                title: area.name,
                subtitle: area.context?.name,
                icon: area.icon,
                colorHex: area.colorHex,
                count: CadenceTaskQuerySupport.openTaskCount(for: area)
            )
        }
        .iOSListRowChrome()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            archiveAreaButton(area)
        }
        .contextMenu {
            Button {
                editorMode = .editArea(area)
            } label: {
                Label("Edit Area", systemImage: "square.and.pencil")
            }

            archiveAreaButton(area, title: "Archive Area")
        }
    }

    @ViewBuilder
    private var activeProjectSection: some View {
        if !activeProjects.isEmpty {
            Section {
                ForEach(activeProjects) { project in
                    projectRow(project)
                }
            } header: {
                iOSListSectionHeader(title: "Projects")
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        NavigationLink(value: iOSListRoute.project(project.id)) {
            iOSListPickerRow(
                title: project.name,
                subtitle: projectSubtitle(project),
                icon: project.icon,
                colorHex: project.colorHex,
                count: CadenceTaskQuerySupport.openTaskCount(for: project)
            )
        }
        .iOSListRowChrome()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            archiveProjectButton(project)
        }
        .contextMenu {
            Button {
                editorMode = .editProject(project)
            } label: {
                Label("Edit Project", systemImage: "square.and.pencil")
            }

            archiveProjectButton(project, title: "Archive Project")
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if !archivedAreas.isEmpty || !archivedProjects.isEmpty {
            Section {
                ForEach(archivedAreas) { area in
                    archivedAreaRow(area)
                }

                ForEach(archivedProjects) { project in
                    archivedProjectRow(project)
                }
            } header: {
                iOSListSectionHeader(title: "Archived")
            }
        }
    }

    private func archivedAreaRow(_ area: Area) -> some View {
        iOSArchivedListRow(
            title: area.name,
            subtitle: area.context?.name,
            icon: area.icon,
            colorHex: area.colorHex
        ) {
            restore(area)
        }
        .iOSListRowChrome()
    }

    private func archivedProjectRow(_ project: Project) -> some View {
        iOSArchivedListRow(
            title: project.name,
            subtitle: projectSubtitle(project),
            icon: project.icon,
            colorHex: project.colorHex
        ) {
            restore(project)
        }
        .iOSListRowChrome()
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        if activeAreas.isEmpty && activeProjects.isEmpty {
            iOSEmptyPanel(
                systemImage: "folder",
                title: "No active lists",
                subtitle: "Create an area or project here, or restore one from Archived."
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func archiveAreaButton(_ area: Area, title: String = "Archive") -> some View {
        Button(role: .destructive) {
            archive(area)
        } label: {
            Label(title, systemImage: "archivebox")
        }
    }

    private func archiveProjectButton(_ project: Project, title: String = "Archive") -> some View {
        Button(role: .destructive) {
            archive(project)
        } label: {
            Label(title, systemImage: "archivebox")
        }
    }

    private func projectSubtitle(_ project: Project) -> String {
        [project.context?.name, project.area?.name].compactMap { $0 }.joined(separator: " / ")
    }

    @ViewBuilder
    private func listDetail(for route: iOSListRoute) -> some View {
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

    private var activeRouteKey: String {
        let areaIDs = activeAreas.map { "a:\($0.id.uuidString)" }
        let projectIDs = activeProjects.map { "p:\($0.id.uuidString)" }
        return (areaIDs + projectIDs).joined(separator: "|")
    }

    private func containsActive(route: iOSListRoute) -> Bool {
        switch route {
        case .area(let id):
            return activeAreas.contains { $0.id == id }
        case .project(let id):
            return activeProjects.contains { $0.id == id }
        }
    }

    private func selectDefaultListIfNeeded() {
        if let selectedRoute, containsActive(route: selectedRoute) {
            return
        }
        selectedRoute = firstActiveRoute
    }

    private func archive(_ area: Area) {
        area.status = .archived
        try? modelContext.save()
    }

    private func archive(_ project: Project) {
        project.status = .archived
        try? modelContext.save()
    }

    private func restore(_ area: Area) {
        area.status = .active
        try? modelContext.save()
    }

    private func restore(_ project: Project) {
        project.status = .active
        try? modelContext.save()
    }
}
#endif
