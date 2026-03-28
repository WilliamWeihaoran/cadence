#if os(macOS)
import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]

    @State private var showCreateContext = false
    @State private var contextForNewList: Context? = nil

    var body: some View {
        List(selection: $selection) {
            // Focus & Today
            Section {
                SidebarRow(icon: "sun.max.fill",   label: "Today",    color: Theme.amber)
                    .tag(SidebarItem.today)
                SidebarRow(icon: "checklist",      label: "All Tasks", color: Theme.blue)
                    .tag(SidebarItem.allTasks)
                SidebarRow(icon: "timer",          label: "Focus",    color: Theme.red)
                    .tag(SidebarItem.focus)
                SidebarRow(icon: "tray.fill",      label: "Inbox",    color: Theme.blue)
                    .tag(SidebarItem.inbox)
                SidebarRow(icon: "calendar",       label: "Calendar", color: Theme.purple)
                    .tag(SidebarItem.calendar)
            }

            // Organize
            Section("ORGANIZE") {
                ForEach(contexts) { context in
                    ContextSection(
                        context: context,
                        selection: $selection,
                        onAddList: { contextForNewList = context }
                    )
                }
            }

            // Track
            Section("TRACK") {
                SidebarRow(icon: "target",      label: "Goals",  color: Theme.green)
                    .tag(SidebarItem.goals)
                SidebarRow(icon: "flame.fill",  label: "Habits", color: Theme.amber)
                    .tag(SidebarItem.habits)
            }

            // Notes
            Section("NOTES") {
                SidebarRow(icon: "doc.text", label: "Notes", color: Theme.purple)
                    .tag(SidebarItem.notes)
            }

            // New Context
            Section {
                Button {
                    showCreateContext = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle").font(.system(size: 12))
                        Text("New Context").font(.system(size: 12))
                    }
                    .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .background(Theme.surface)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showCreateContext) {
            CreateContextSheet()
        }
        .sheet(item: $contextForNewList) { ctx in
            CreateListSheet(context: ctx)
        }
    }
}

// MARK: - Context Section

private struct ContextSection: View {
    @Bindable var context: Context
    @Binding var selection: SidebarItem?
    let onAddList: () -> Void
    @State private var areaForEdit: Area? = nil
    @State private var projectForEdit: Project? = nil

    private var areas: [Area]    { (context.areas    ?? []).sorted { $0.order < $1.order } }
    private var projects: [Project] { (context.projects ?? []).sorted { $0.order < $1.order } }

    var body: some View {
        Section {
            ForEach(areas) { area in
                SidebarListRow(
                    icon: area.icon,
                    label: area.name,
                    color: Color(hex: area.colorHex),
                    kind: .area,
                    onEdit: { areaForEdit = area }
                )
                    .tag(SidebarItem.area(area.id))
            }
            .onMove { indices, newOffset in moveAreas(from: indices, to: newOffset) }

            ForEach(projects) { project in
                SidebarListRow(
                    icon: project.icon,
                    label: project.name,
                    color: Color(hex: project.colorHex),
                    kind: .project,
                    onEdit: { projectForEdit = project }
                )
                    .tag(SidebarItem.project(project.id))
            }
            .onMove { indices, newOffset in moveProjects(from: indices, to: newOffset) }

        } header: {
            HStack(spacing: 6) {
                Image(systemName: context.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: context.colorHex))
                Text(context.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                Spacer()
                Button(action: onAddList) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $areaForEdit) { area in
            EditAreaSheet(area: area)
        }
        .sheet(item: $projectForEdit) { project in
            EditProjectSheet(project: project)
        }
    }

    private func moveAreas(from indices: IndexSet, to newOffset: Int) {
        var sorted = areas
        sorted.move(fromOffsets: indices, toOffset: newOffset)
        for (i, area) in sorted.enumerated() { area.order = i }
    }

    private func moveProjects(from indices: IndexSet, to newOffset: Int) {
        var sorted = projects
        sorted.move(fromOffsets: indices, toOffset: newOffset)
        for (i, project) in sorted.enumerated() { project.order = i }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        Label {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 13))
        }
    }
}

private struct SidebarListRow: View {
    enum Kind {
        case area
        case project

        var label: String {
            switch self {
            case .area: return "Area"
            case .project: return "Project"
            }
        }

        var tint: Color {
            switch self {
            case .area: return Theme.blue
            case .project: return Theme.amber
            }
        }
    }

    let icon: String
    let label: String
    let color: Color
    let kind: Kind
    let onEdit: () -> Void

    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @State private var isHovered = false

    private var hoverID: String {
        "sidebar-\(kind.label)-\(label)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 13))
            }

            Spacer(minLength: 8)

            Text(kind.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(kind.tint.opacity(isHovered ? 1 : 0.88))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(kind.tint.opacity(isHovered ? 0.18 : 0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredEditableManager.beginHovering(id: hoverID, onEdit: onEdit)
            } else {
                hoveredEditableManager.endHovering(id: hoverID)
            }
        }
    }
}
#endif
