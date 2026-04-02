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
                        ForEach(areas) { area in
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
                                draggingAreaID = area.id
                                return NSItemProvider(object: NSString(string: "area:\(area.id.uuidString)"))
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SidebarUUIDDropDelegate(
                                    targetID: area.id,
                                    draggingID: $draggingAreaID,
                                    onEnter: { id in dragOverAreaID = id },
                                    onExit: { id in if dragOverAreaID == id { dragOverAreaID = nil } },
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
                                draggingProjectID = project.id
                                return NSItemProvider(object: NSString(string: "project:\(project.id.uuidString)"))
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SidebarUUIDDropDelegate(
                                    targetID: project.id,
                                    draggingID: $draggingProjectID,
                                    onEnter: { id in dragOverProjectID = id },
                                    onExit: { id in if dragOverProjectID == id { dragOverProjectID = nil } },
                                    onReorder: reorderProject
                                )
                            )
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
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (i, a) in sorted.enumerated() { a.order = i }
        }
    }

    private func reorderProject(droppedID: UUID, targetID: UUID) {
        var sorted = projects
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            for (i, p) in sorted.enumerated() { p.order = i }
        }
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
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 15)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(backgroundFillShape)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
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
        RoundedRectangle(cornerRadius: 11, style: .continuous)
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
    let dueDateKey: String?
    let onSetDueDate: ((String) -> Void)?
    @Binding var selection: SidebarItem?
    let onEdit: () -> Void

    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @State private var isHovered = false
    @State private var showDueDatePicker = false
    @State private var dueDatePickerDate = Date()
    @State private var dueDateViewMonth = Date()

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
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer(minLength: 8)

                if let dueDateKey, !dueDateKey.isEmpty, onSetDueDate != nil {
                    dueDateBadge(dueDateKey)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selection == item ? Theme.blue.opacity(0.16) : (isHovered ? Theme.surfaceElevated.opacity(0.78) : Color.clear))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    @ViewBuilder
    private func dueDateBadge(_ key: String) -> some View {
        Button {
            openDueDatePicker(key)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.red)
                Text(DateFormatters.relativeDate(from: key))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(key < DateFormatters.todayKey() ? Theme.red : Theme.dim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.surfaceElevated.opacity(isHovered ? 0.9 : 0.7))
            .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showDueDatePicker) {
            CadenceQuickDatePopover(
                selection: Binding(
                    get: { dueDatePickerDate },
                    set: {
                        dueDatePickerDate = $0
                        onSetDueDate?(DateFormatters.dateKey(from: $0))
                    }
                ),
                viewMonth: $dueDateViewMonth,
                isOpen: $showDueDatePicker,
                showsClear: true,
                onClear: {
                    onSetDueDate?("")
                }
            )
        }
    }

    private func openDueDatePicker(_ key: String) {
        let resolved = DateFormatters.date(from: key) ?? Date()
        dueDatePickerDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        dueDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showDueDatePicker = true
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.65))
                    .frame(height: 1)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}


struct SidebarUUIDDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    let onEnter: (UUID) -> Void
    let onExit: (UUID) -> Void
    let onReorder: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        onEnter(targetID)
    }

    func dropExited(info: DropInfo) {
        onExit(targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        onExit(targetID)
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
