#if os(iOS)
import SwiftUI

struct iOSListsRegularPane: View {
    let activeAreas: [Area]
    let activeProjects: [Project]
    let archivedAreas: [Area]
    let archivedProjects: [Project]
    @Binding var selectedRoute: iOSListRoute?
    @Binding var editorMode: iOSListEditorMode?
    let projectSubtitle: (Project) -> String
    let archiveArea: (Area) -> Void
    let archiveProject: (Project) -> Void
    let restoreArea: (Area) -> Void
    let restoreProject: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSListsPageHeader(areaCount: activeAreas.count, projectCount: activeProjects.count)

            iOSListCreateButtonsRow(editorMode: $editorMode)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            iOSListHairline()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if activeAreas.isEmpty && activeProjects.isEmpty {
                        iOSEmptyPanel(
                            systemImage: "folder",
                            title: "No active lists",
                            subtitle: "Create an area or project here, or restore one from Archived."
                        )
                        .frame(minHeight: 260)
                    } else {
                        areaSection
                        projectSection
                    }

                    archivedSection
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.surface)
    }

    @ViewBuilder
    private var areaSection: some View {
        if !activeAreas.isEmpty {
            iOSListSelectionSection(title: "Areas") {
                ForEach(activeAreas) { area in
                    iOSListSelectionRow(
                        title: area.name,
                        subtitle: area.context?.name,
                        icon: area.icon,
                        colorHex: area.colorHex,
                        count: CadenceTaskQuerySupport.openTaskCount(for: area),
                        isSelected: selectedRoute == .area(area.id)
                    ) {
                        selectedRoute = .area(area.id)
                    }
                    .contextMenu {
                        Button {
                            editorMode = .editArea(area)
                        } label: {
                            Label("Edit Area", systemImage: "square.and.pencil")
                        }

                        Button(role: .destructive) {
                            archiveArea(area)
                        } label: {
                            Label("Archive Area", systemImage: "archivebox")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var projectSection: some View {
        if !activeProjects.isEmpty {
            iOSListSelectionSection(title: "Projects") {
                ForEach(activeProjects) { project in
                    iOSListSelectionRow(
                        title: project.name,
                        subtitle: projectSubtitle(project),
                        icon: project.icon,
                        colorHex: project.colorHex,
                        count: CadenceTaskQuerySupport.openTaskCount(for: project),
                        isSelected: selectedRoute == .project(project.id)
                    ) {
                        selectedRoute = .project(project.id)
                    }
                    .contextMenu {
                        Button {
                            editorMode = .editProject(project)
                        } label: {
                            Label("Edit Project", systemImage: "square.and.pencil")
                        }

                        Button(role: .destructive) {
                            archiveProject(project)
                        } label: {
                            Label("Archive Project", systemImage: "archivebox")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if !archivedAreas.isEmpty || !archivedProjects.isEmpty {
            iOSListSelectionSection(title: "Archived") {
                ForEach(archivedAreas) { area in
                    iOSArchivedListSelectionRow(
                        title: area.name,
                        subtitle: area.context?.name,
                        icon: area.icon,
                        colorHex: area.colorHex
                    ) {
                        restoreArea(area)
                    }
                }

                ForEach(archivedProjects) { project in
                    iOSArchivedListSelectionRow(
                        title: project.name,
                        subtitle: projectSubtitle(project),
                        icon: project.icon,
                        colorHex: project.colorHex
                    ) {
                        restoreProject(project)
                    }
                }
            }
        }
    }
}

private struct iOSListSelectionSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrowLabel(text: title)
                .padding(.horizontal, 4)

            VStack(spacing: 2) {
                content()
            }
        }
    }
}

/// Flat and neutral, like `SidebarListRow`: **one** selection layer at **one** radius and nothing
/// else. Each row used to be an elevated `cadenceCard` in a wash of the list's own colour *plus* a
/// separate 3pt accent bar at a second radius — three layers saying "selected", on a pane where
/// every row was already a plate. `Theme.cardElevationShadow`'s own note records the same move on
/// macOS: rows are flat now, and elevation is for things that are genuinely card-shaped.
private struct iOSListSelectionRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            iOSListPickerRow(
                title: title,
                subtitle: subtitle,
                icon: icon,
                colorHex: colorHex,
                count: count
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(isSelected ? Theme.surfaceHighlight : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct iOSArchivedListSelectionRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let restore: () -> Void

    var body: some View {
        iOSArchivedListRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            colorHex: colorHex,
            restore: restore
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
#endif
