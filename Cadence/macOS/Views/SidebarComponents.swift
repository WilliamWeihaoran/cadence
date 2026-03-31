#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ContextSection: View {
    @Bindable var context: Context
    @Binding var selection: SidebarItem?
    let onAddList: () -> Void
    @State private var areaForEdit: Area? = nil
    @State private var projectForEdit: Project? = nil
    @State private var draggingAreaID: UUID? = nil
    @State private var draggingProjectID: UUID? = nil

    private var areas: [Area] { (context.areas ?? []).sorted { $0.order < $1.order } }
    private var projects: [Project] { (context.projects ?? []).sorted { $0.order < $1.order } }

    var body: some View {
        Section {
            ForEach(areas) { area in
                SidebarListRow(
                    item: .area(area.id),
                    icon: area.icon,
                    label: area.name,
                    color: Color(hex: area.colorHex),
                    kind: .area,
                    selection: $selection,
                    onEdit: { areaForEdit = area }
                )
                .onDrag {
                    draggingAreaID = area.id
                    return NSItemProvider(object: NSString(string: "area:\(area.id.uuidString)"))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: SidebarUUIDDropDelegate(
                        targetID: area.id,
                        draggingID: $draggingAreaID,
                        onReorder: reorderArea
                    )
                )
            }

            ForEach(projects) { project in
                SidebarListRow(
                    item: .project(project.id),
                    icon: project.icon,
                    label: project.name,
                    color: Color(hex: project.colorHex),
                    kind: .project,
                    selection: $selection,
                    onEdit: { projectForEdit = project }
                )
                .onDrag {
                    draggingProjectID = project.id
                    return NSItemProvider(object: NSString(string: "project:\(project.id.uuidString)"))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: SidebarUUIDDropDelegate(
                        targetID: project.id,
                        draggingID: $draggingProjectID,
                        onReorder: reorderProject
                    )
                )
            }
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
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .sheet(item: $areaForEdit) { area in
            EditAreaSheet(area: area)
        }
        .sheet(item: $projectForEdit) { project in
            EditProjectSheet(project: project)
        }
    }

    private func reorderArea(droppedID: UUID, targetID: UUID) {
        var sorted = areas
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        for (i, a) in sorted.enumerated() { a.order = i }
    }

    private func reorderProject(droppedID: UUID, targetID: UUID) {
        var sorted = projects
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        for (i, p) in sorted.enumerated() { p.order = i }
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    let icon: String
    let label: String
    let color: Color
    @Binding var selection: SidebarItem?
    @State private var isHovered = false

    var body: some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundFillShape)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: selection == item ? 1 : 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var borderColor: Color {
        selection == item ? Theme.blue.opacity(0.34) : Theme.borderSubtle.opacity(isHovered ? 0.75 : 0.4)
    }

    private var backgroundFill: Color {
        if selection == item {
            return Theme.blue.opacity(0.22)
        }
        if isHovered {
            return Theme.surfaceElevated.opacity(0.9)
        }
        return Theme.surfaceElevated.opacity(0.45)
    }
}

private extension SidebarRow {
    @ViewBuilder
    var backgroundFillShape: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(backgroundFill)
    }
}

struct SidebarListRow: View {
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

    let item: SidebarItem
    let icon: String
    let label: String
    let color: Color
    let kind: Kind
    @Binding var selection: SidebarItem?
    let onEdit: () -> Void

    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @State private var isHovered = false

    private var hoverID: String {
        "sidebar-\(kind.label)-\(label)"
    }

    var body: some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                Label {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.system(size: 13, weight: .semibold))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selection == item ? Theme.blue.opacity(0.18) : (isHovered ? Theme.surfaceElevated.opacity(0.85) : Color.clear))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selection == item ? Theme.blue.opacity(0.3) : Theme.borderSubtle.opacity(isHovered ? 0.75 : 0), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
                .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }
}

struct SidebarStaticDropDelegate: DropDelegate {
    let target: SidebarStaticDestination
    @Binding var dragging: SidebarStaticDestination?
    let current: [SidebarStaticDestination]
    let save: ([SidebarStaticDestination]) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let dragging, dragging != target,
              let fromIndex = current.firstIndex(of: dragging),
              let toIndex = current.firstIndex(of: target) else {
            self.dragging = nil
            return false
        }

        var updated = current
        let moved = updated.remove(at: fromIndex)
        updated.insert(moved, at: fromIndex < toIndex ? toIndex - 1 : toIndex)
        save(updated)
        self.dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct SidebarUUIDDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    let onReorder: (UUID, UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingID, draggingID != targetID else {
            self.draggingID = nil
            return false
        }
        onReorder(draggingID, targetID)
        self.draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
#endif
