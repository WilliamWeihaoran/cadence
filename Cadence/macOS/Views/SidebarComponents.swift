#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Non-SwiftUI storage for the currently-dragged sidebar row ID.
// Using a plain class instead of @State/@Binding so it's never nil'd by
// SwiftUI view updates between onDrag and performDrop.
private final class SidebarDragContext {
    static let shared = SidebarDragContext()
    var draggedListItem: SidebarListDragItem?
    private init() {}
}

private enum SidebarListKind: String {
    case area
    case project
}

private struct SidebarListDragItem: Equatable {
    let kind: SidebarListKind
    let id: UUID

    var providerText: NSString {
        "\(kind.rawValue):\(id.uuidString)" as NSString
    }
}

private enum SidebarListEntry: Identifiable {
    case area(Area)
    case project(Project)

    var id: String {
        switch self {
        case .area(let area): return "area-\(area.id.uuidString)"
        case .project(let project): return "project-\(project.id.uuidString)"
        }
    }

    var order: Int {
        switch self {
        case .area(let area): return area.order
        case .project(let project): return project.order
        }
    }

    var kindRank: Int {
        switch self {
        case .area: return 0
        case .project: return 1
        }
    }

    var label: String {
        switch self {
        case .area(let area): return area.name
        case .project(let project): return project.name
        }
    }

    var dragItem: SidebarListDragItem {
        switch self {
        case .area(let area): return SidebarListDragItem(kind: .area, id: area.id)
        case .project(let project): return SidebarListDragItem(kind: .project, id: project.id)
        }
    }

    func matches(_ item: SidebarListDragItem) -> Bool {
        dragItem == item
    }

    func setOrder(_ value: Int) {
        switch self {
        case .area(let area): area.order = value
        case .project(let project): project.order = value
        }
    }
}

struct ContextSection: View {
    @Bindable var context: Context
    @Binding var selection: SidebarItem?
    let onAddList: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var areaForEdit: Area? = nil
    @State private var projectForEdit: Project? = nil
    @State private var dragOverListItem: SidebarListDragItem? = nil

    private var areas: [Area] { (context.areas ?? []).filter(\.isActive).sorted { $0.order < $1.order } }
    private var projects: [Project] { (context.projects ?? []).filter(\.isActive).sorted { $0.order < $1.order } }
    private var hasLists: Bool { !areas.isEmpty || !projects.isEmpty }
    private var listEntries: [SidebarListEntry] {
        let areaEntries = areas.map(SidebarListEntry.area)
        let projectEntries = projects.map(SidebarListEntry.project)
        let entries = areaEntries + projectEntries
        let hasGlobalOrder = Set(entries.map(\.order)).count == entries.count
        guard hasGlobalOrder else { return areaEntries + projectEntries }
        return entries.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            .padding(.horizontal, 2)

            if hasLists {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color(hex: context.colorHex).opacity(0.22))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 3) {
                        // Top drop zone — lets the user drag any item to the first position
                        if let firstItem = listEntries.first?.dragItem {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 4)
                                .onDrop(of: [UTType.text], delegate: SidebarListDropDelegate(
                                    target: firstItem,
                                    dragOverItem: $dragOverListItem,
                                    onDrop: reorderList
                                ))
                        }

                        ForEach(listEntries) { entry in
                            switch entry {
                            case .area(let area):
                                areaRow(area, target: entry.dragItem)
                            case .project(let project):
                                projectRow(project, target: entry.dragItem)
                            }
                        }
                    }
                }
                .padding(.leading, 8)
            } else {
                Button(action: onAddList) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add first list")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.surfaceElevated.opacity(0.55))
                    )
                }
                .buttonStyle(.cadencePlain)
                .padding(.leading, 8)
            }
        }
        .sheet(item: $areaForEdit) { area in
            EditAreaSheet(area: area)
        }
        .sheet(item: $projectForEdit) { project in
            EditProjectSheet(project: project)
        }
    }

    private func reorderList(dropped: SidebarListDragItem, target: SidebarListDragItem) {
        var sorted = listEntries
        guard let fromIndex = sorted.firstIndex(where: { $0.matches(dropped) }),
              let toIndex = sorted.firstIndex(where: { $0.matches(target) }) else { return }
        let element = sorted.remove(at: fromIndex)
        // Treat the row we drop on as the destination row itself. This avoids the
        // "no-op" feeling when dragging onto the next item down in the list.
        sorted.insert(element, at: min(toIndex, sorted.count))
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (i, entry) in sorted.enumerated() { entry.setOrder(i) }
        }
        try? modelContext.save()
    }

    private func areaRow(_ area: Area, target: SidebarListDragItem) -> some View {
        SidebarListRow(
            item: .area(area.id),
            icon: area.icon,
            label: area.name,
            color: Color(hex: area.colorHex),
            kind: .area,
            dueDateKey: nil,
            onSetDueDate: nil,
            selection: $selection,
            onEdit: { areaForEdit = area }
        )
        .overlay(alignment: .top) {
            if dragOverListItem == target {
                Rectangle().fill(Theme.blue).frame(height: 2).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: dragOverListItem)
        .onDrag {
            SidebarDragContext.shared.draggedListItem = target
            return NSItemProvider(object: target.providerText)
        }
        .onDrop(of: [UTType.text], delegate: SidebarListDropDelegate(
            target: target,
            dragOverItem: $dragOverListItem,
            onDrop: reorderList
        ))
    }

    private func projectRow(_ project: Project, target: SidebarListDragItem) -> some View {
        SidebarListRow(
            item: .project(project.id),
            icon: project.icon,
            label: project.name,
            color: Color(hex: project.colorHex),
            kind: .project,
            dueDateKey: project.dueDate,
            onSetDueDate: { newKey in
                project.dueDate = newKey
            },
            selection: $selection,
            onEdit: { projectForEdit = project }
        )
        .overlay(alignment: .top) {
            if dragOverListItem == target {
                Rectangle().fill(Theme.blue).frame(height: 2).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: dragOverListItem)
        .onDrag {
            SidebarDragContext.shared.draggedListItem = target
            return NSItemProvider(object: target.providerText)
        }
        .onDrop(of: [UTType.text], delegate: SidebarListDropDelegate(
            target: target,
            dragOverItem: $dragOverListItem,
            onDrop: reorderList
        ))
    }
}

// MARK: - Drop Delegates

private struct SidebarListDropDelegate: DropDelegate {
    let target: SidebarListDragItem
    @Binding var dragOverItem: SidebarListDragItem?
    let onDrop: (SidebarListDragItem, SidebarListDragItem) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) { dragOverItem = target }

    func dropExited(info: DropInfo) {
        if dragOverItem == target { dragOverItem = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragOverItem == target { dragOverItem = nil }
        guard let dropped = SidebarDragContext.shared.draggedListItem,
              dropped != target else { return false }
        SidebarDragContext.shared.draggedListItem = nil
        onDrop(dropped, target)
        return true
    }
}
#endif
