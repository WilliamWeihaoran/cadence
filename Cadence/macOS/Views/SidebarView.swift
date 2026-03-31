#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let sidebarStaticDragPrefix = "sidebar-static::"

private enum SidebarStaticDestination: String, CaseIterable, Identifiable {
    case today
    case allTasks
    case focus
    case inbox
    case calendar
    case goals
    case habits

    var id: String { rawValue }

    var item: SidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .allTasks: return "checklist"
        case .focus: return "timer"
        case .inbox: return "tray.fill"
        case .calendar: return "calendar"
        case .goals: return "target"
        case .habits: return "flame.fill"
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .allTasks: return "All Tasks"
        case .focus: return "Focus"
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .goals: return "Goals"
        case .habits: return "Habits"
        }
    }

    var color: Color {
        switch self {
        case .today: return Theme.amber
        case .allTasks: return Theme.blue
        case .focus: return Theme.red
        case .inbox: return Theme.blue
        case .calendar: return Theme.purple
        case .goals: return Theme.green
        case .habits: return Theme.amber
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(sort: \Context.order) private var contexts: [Context]
    @AppStorage("sidebarCoreOrder") private var sidebarCoreOrderRaw = ""
    @AppStorage("sidebarTrackOrder") private var sidebarTrackOrderRaw = ""

    @State private var showCreateContext = false
    @State private var contextForNewList: Context? = nil
    @State private var draggingStaticDestination: SidebarStaticDestination? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surfaceElevated)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "checklist.checked")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cadence")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Workspace")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coreDestinations) { destination in
                        SidebarRow(item: destination.item, icon: destination.icon, label: destination.label, color: destination.color, selection: $selection)
                            .onDrag {
                                draggingStaticDestination = destination
                                return NSItemProvider(object: NSString(string: "\(sidebarStaticDragPrefix)\(destination.rawValue)"))
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SidebarStaticDropDelegate(
                                    target: destination,
                                    dragging: $draggingStaticDestination,
                                    current: coreDestinations,
                                    save: saveCoreDestinations
                                )
                            )
                    }
                }

                SidebarSection(title: "ORGANIZE") {
                    ForEach(contexts) { context in
                        ContextSection(
                            context: context,
                            selection: $selection,
                            onAddList: { contextForNewList = context }
                        )
                    }
                }

                SidebarSection(title: "TRACK") {
                    ForEach(trackDestinations) { destination in
                        SidebarRow(item: destination.item, icon: destination.icon, label: destination.label, color: destination.color, selection: $selection)
                            .onDrag {
                                draggingStaticDestination = destination
                                return NSItemProvider(object: NSString(string: "\(sidebarStaticDragPrefix)\(destination.rawValue)"))
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SidebarStaticDropDelegate(
                                    target: destination,
                                    dragging: $draggingStaticDestination,
                                    current: trackDestinations,
                                    save: saveTrackDestinations
                                )
                            )
                    }
                }

                SidebarSection(title: "NOTES") {
                    SidebarRow(item: .notes, icon: "doc.text", label: "Notes", color: Theme.purple, selection: $selection)
                }

                Button {
                    showCreateContext = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("New Context")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.surfaceElevated.opacity(0.68))
                    )
                }
                .buttonStyle(.cadencePlain)

                Spacer(minLength: 8)

                SidebarRow(item: .settings, icon: "gearshape.fill", label: "Settings", color: Theme.dim, selection: $selection)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface)
        .sheet(isPresented: $showCreateContext) {
            CreateContextSheet()
        }
        .sheet(item: $contextForNewList) { ctx in
            CreateListSheet(context: ctx)
        }
    }

    private var coreDestinations: [SidebarStaticDestination] {
        resolveDestinations(
            rawValue: sidebarCoreOrderRaw,
            defaults: [.today, .allTasks, .focus, .inbox, .calendar]
        )
    }

    private var trackDestinations: [SidebarStaticDestination] {
        resolveDestinations(
            rawValue: sidebarTrackOrderRaw,
            defaults: [.goals, .habits]
        )
    }

    private func resolveDestinations(rawValue: String, defaults: [SidebarStaticDestination]) -> [SidebarStaticDestination] {
        let stored = rawValue
            .split(separator: ",")
            .compactMap { SidebarStaticDestination(rawValue: String($0)) }

        let filtered = stored.filter(defaults.contains)
        let missing = defaults.filter { !filtered.contains($0) }
        let resolved = filtered + missing
        return resolved.isEmpty ? defaults : resolved
    }

    private func reorderStatic(
        moving: SidebarStaticDestination,
        before target: SidebarStaticDestination,
        in source: [SidebarStaticDestination],
        save: ([SidebarStaticDestination]) -> Void
    ) {
        guard let fromIndex = source.firstIndex(of: moving),
              let toIndex = source.firstIndex(of: target) else { return }
        var updated = source
        let item = updated.remove(at: fromIndex)
        updated.insert(item, at: fromIndex < toIndex ? toIndex - 1 : toIndex)
        save(updated)
    }

    private func saveCoreDestinations(_ destinations: [SidebarStaticDestination]) {
        sidebarCoreOrderRaw = destinations.map(\.rawValue).joined(separator: ",")
    }

    private func saveTrackDestinations(_ destinations: [SidebarStaticDestination]) {
        sidebarTrackOrderRaw = destinations.map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Context Section

private struct ContextSection: View {
    @Bindable var context: Context
    @Binding var selection: SidebarItem?
    let onAddList: () -> Void
    @State private var areaForEdit: Area? = nil
    @State private var projectForEdit: Project? = nil
    @State private var draggingAreaID: UUID? = nil
    @State private var draggingProjectID: UUID? = nil

    private var areas: [Area]    { (context.areas    ?? []).sorted { $0.order < $1.order } }
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

// MARK: - Sidebar Row

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

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
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

private struct SidebarSection<Content: View>: View {
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

private struct SidebarStaticDropDelegate: DropDelegate {
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

private struct SidebarUUIDDropDelegate: DropDelegate {
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
