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

    private var archivedAreas: [Area] {
        areas.filter(\.isArchived)
    }

    private var archivedProjects: [Project] {
        projects.filter(\.isArchived)
    }

    var body: some View {
        List {
            activeAreaSection
            activeProjectSection
            archivedSection
            emptyStateSection
        }
        .navigationTitle("Lists")
        .toolbar { addToolbar }
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

    @ViewBuilder
    private var activeAreaSection: some View {
        if !activeAreas.isEmpty {
            Section("Areas") {
                ForEach(activeAreas) { area in
                    areaRow(area)
                }
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
            Section("Projects") {
                ForEach(activeProjects) { project in
                    projectRow(project)
                }
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
            Section("Archived") {
                ForEach(archivedAreas) { area in
                    archivedAreaRow(area)
                }

                ForEach(archivedProjects) { project in
                    archivedProjectRow(project)
                }
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
        }
    }

    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
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
