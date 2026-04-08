#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Non-SwiftUI storage for the currently-dragged sidebar row ID.
// Using a plain class instead of @State/@Binding so it's never nil'd by
// SwiftUI view updates between onDrag and performDrop.
private final class SidebarDragContext {
    static let shared = SidebarDragContext()
    var draggedAreaID: UUID?
    var draggedProjectID: UUID?
    private init() {}
}

struct ContextSection: View {
    @Bindable var context: Context
    @Binding var selection: SidebarItem?
    let onAddList: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var areaForEdit: Area? = nil
    @State private var projectForEdit: Project? = nil
    @State private var dragOverAreaID: UUID? = nil
    @State private var dragOverProjectID: UUID? = nil

    private var areas: [Area] { (context.areas ?? []).filter(\.isActive).sorted { $0.order < $1.order } }
    private var projects: [Project] { (context.projects ?? []).filter(\.isActive).sorted { $0.order < $1.order } }
    private var hasLists: Bool { !areas.isEmpty || !projects.isEmpty }

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
                        if let firstArea = areas.first {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 4)
                                .onDrop(of: [UTType.text], delegate: SidebarAreaDropDelegate(
                                    targetID: firstArea.id,
                                    dragOverID: $dragOverAreaID,
                                    onDrop: reorderArea
                                ))
                        } else if let firstProject = projects.first {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 4)
                                .onDrop(of: [UTType.text], delegate: SidebarProjectDropDelegate(
                                    targetID: firstProject.id,
                                    dragOverID: $dragOverProjectID,
                                    onDrop: reorderProject
                                ))
                        }

                        ForEach(areas) { area in
                            areaRow(area)
                        }

                        ForEach(projects) { project in
                            projectRow(project)
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

    private func reorderArea(droppedID: UUID, targetID: UUID) {
        var sorted = areas
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        // Treat the row we drop on as the destination row itself. This avoids the
        // "no-op" feeling when dragging onto the next item down in the list.
        sorted.insert(element, at: min(toIndex, sorted.count))
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (i, a) in sorted.enumerated() { a.order = i }
        }
        try? modelContext.save()
    }

    private func reorderProject(droppedID: UUID, targetID: UUID) {
        var sorted = projects
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        // Treat the row we drop on as the destination row itself. This avoids the
        // "no-op" feeling when dragging onto the next item down in the list.
        sorted.insert(element, at: min(toIndex, sorted.count))
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (i, p) in sorted.enumerated() { p.order = i }
        }
        try? modelContext.save()
    }

    private func areaRow(_ area: Area) -> some View {
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
            if dragOverAreaID == area.id {
                Rectangle().fill(Theme.blue).frame(height: 2).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: dragOverAreaID)
        .onDrag {
            SidebarDragContext.shared.draggedAreaID = area.id
            return NSItemProvider(object: "area:\(area.id.uuidString)" as NSString)
        }
        .onDrop(of: [UTType.text], delegate: SidebarAreaDropDelegate(
            targetID: area.id,
            dragOverID: $dragOverAreaID,
            onDrop: reorderArea
        ))
    }

    private func projectRow(_ project: Project) -> some View {
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
            if dragOverProjectID == project.id {
                Rectangle().fill(Theme.blue).frame(height: 2).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: dragOverProjectID)
        .onDrag {
            SidebarDragContext.shared.draggedProjectID = project.id
            return NSItemProvider(object: "project:\(project.id.uuidString)" as NSString)
        }
        .onDrop(of: [UTType.text], delegate: SidebarProjectDropDelegate(
            targetID: project.id,
            dragOverID: $dragOverProjectID,
            onDrop: reorderProject
        ))
    }
}

// MARK: - Drop Delegates

private struct SidebarAreaDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var dragOverID: UUID?
    let onDrop: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) { dragOverID = targetID }

    func dropExited(info: DropInfo) {
        if dragOverID == targetID { dragOverID = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragOverID == targetID { dragOverID = nil }
        guard let droppedID = SidebarDragContext.shared.draggedAreaID,
              droppedID != targetID else { return false }
        SidebarDragContext.shared.draggedAreaID = nil
        onDrop(droppedID, targetID)
        return true
    }
}

private struct SidebarProjectDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var dragOverID: UUID?
    let onDrop: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) { dragOverID = targetID }

    func dropExited(info: DropInfo) {
        if dragOverID == targetID { dragOverID = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragOverID == targetID { dragOverID = nil }
        guard let droppedID = SidebarDragContext.shared.draggedProjectID,
              droppedID != targetID else { return false }
        SidebarDragContext.shared.draggedProjectID = nil
        onDrop(droppedID, targetID)
        return true
    }
}
#endif
