#if os(macOS)
import SwiftUI

struct TodayTaskGroup: Identifiable {
    let id: String
    let contextIcon: String?
    let contextColor: Color?
    let listIcon: String
    let listName: String
    let listColor: Color
    var tasks: [AppTask]
}

struct FrozenTodayTaskGroup {
    let id: String
    let contextIcon: String?
    let contextColor: Color?
    let listIcon: String
    let listName: String
    let listColor: Color
    let taskIDs: [UUID]
}

struct FrozenFlatTaskSection {
    let id: String
    let title: String
    let labelColor: Color
    let dropKey: String?
    let taskIDs: [UUID]
}

struct TasksPanelGroupSectionView: View {
    let group: TodayTaskGroup
    @Binding var dragOverTaskID: UUID?
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    let onDropOnGroupPayload: (String) -> Bool
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                if let ctxIcon = group.contextIcon, let ctxColor = group.contextColor {
                    Image(systemName: ctxIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ctxColor)
                        .frame(width: 22, height: 22)
                        .background(ctxColor.opacity(0.15))
                        .clipShape(Circle())
                }

                Image(systemName: group.listIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(group.listColor)

                Text(group.listName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)

                Spacer()

                if let overdueCount, overdueCount > 0 {
                    Text("\(overdueCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    Text("/")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                }

                Text("\(regularCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceElevated.opacity(0.75))
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.cadencePlain)
        .onTapGesture(count: 2, perform: onToggle)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 6)
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            return onDropOnGroupPayload(payload)
        }

        if !isCollapsed {
            ForEach(group.tasks) { task in
                MacTaskRow(task: task, style: .todayGrouped, contexts: contexts, areas: areas, projects: projects)
                    .draggable(taskDragPayload(task))
                    .dropDestination(for: String.self) { items, _ in
                        guard let payload = items.first else { return false }
                        return onDropOnTaskPayload(payload, task)
                    } isTargeted: { isOver in
                        if isOver { dragOverTaskID = task.id }
                        else if dragOverTaskID == task.id { dragOverTaskID = nil }
                    }
                    .overlay(alignment: .top) {
                        if dragOverTaskID == task.id {
                            Rectangle().fill(Theme.blue).frame(height: 2).padding(.leading, 20).transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                    .padding(.leading, 20)
                    .padding(.trailing, 8)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
    }
}

struct TasksPanelFlatSectionView: View {
    let label: String
    let tasks: [AppTask]
    let labelColor: Color
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    let onDropOnSectionPayload: ((String) -> Bool)?
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    private var groupID: String {
        "flat-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }

    var body: some View {
        Section {
            CollapsibleTaskGroupHeader(
                title: label,
                isCollapsed: isCollapsed,
                overdueCount: overdueCount,
                regularCount: regularCount,
                accent: labelColor,
                onToggle: onToggle
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 5)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .dropDestination(for: String.self) { items, _ in
                guard let onDropOnSectionPayload, let payload = items.first else { return false }
                return onDropOnSectionPayload(payload)
            }

            if !isCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: .standard, contexts: contexts, areas: areas, projects: projects)
                        .draggable(taskDragPayload(task))
                        .dropDestination(for: String.self) { items, _ in
                            guard let payload = items.first else { return false }
                            return onDropOnTaskPayload(payload, task)
                        } isTargeted: { isOver in
                            if isOver { dragOverTaskID = task.id }
                            else if dragOverTaskID == task.id { dragOverTaskID = nil }
                        }
                        .overlay(alignment: .top) {
                            if dragOverTaskID == task.id {
                                Rectangle().fill(Theme.blue).frame(height: 2).padding(.leading, 16).transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                        .padding(.leading, 16)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
        }
    }
}

struct TasksPanelCompletedSectionView: View {
    let tasks: [AppTask]
    let mode: TasksPanelMode
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let isCollapsed: Bool
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String

    var body: some View {
        Section {
            CompletedSectionHeader(
                count: tasks.count,
                isCollapsed: isCollapsed,
                onToggle: onToggle
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)

            if !isCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: mode == .todayOverview ? .todayGrouped : .standard, contexts: contexts, areas: areas, projects: projects)
                        .draggable(taskDragPayload(task))
                        .padding(.leading, 16)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
        }
    }
}

struct TasksPanelRolloverNoticeSectionView: View {
    let tasks: [AppTask]
    let onRollOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 22, height: 22)
                    .background(Theme.amber.opacity(0.16))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Leftover tasks are rolling over to today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Review these tasks, then confirm to move them into today's groups.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()

                Button("Roll Over", action: onRollOver)
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            VStack(spacing: 4) {
                ForEach(tasks) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: task.containerColor))
                            .frame(width: 6, height: 6)
                        Text(task.title.isEmpty ? "Untitled" : task.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer()
                        if !task.containerName.isEmpty {
                            Text(task.containerName)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.6)).frame(height: 0.5)
        }
    }
}

struct HoverFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenOrder: [AppTask]?
    @Binding var frozenListGroups: [FrozenTodayTaskGroup]?
    @Binding var frozenFlatSections: [FrozenFlatTaskSection]?
    let naturalTasks: [AppTask]
    let listGroupSnapshot: [FrozenTodayTaskGroup]
    let flatSectionSnapshot: [FrozenFlatTaskSection]
    @State private var isPointerInsideSurface = false
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if newID != nil {
                    var freezeState = TaskSurfaceFreezeState<FrozenTodayTaskGroup, FrozenFlatTaskSection>(
                        frozenOrder: frozenOrder,
                        primarySnapshot: frozenListGroups,
                        secondarySnapshot: frozenFlatSections
                    )
                    freezeState.captureIfNeeded(
                        naturalTasks: naturalTasks,
                        sourcePrimarySnapshot: listGroupSnapshot,
                        sourceSecondarySnapshot: flatSectionSnapshot
                    )
                    frozenOrder = freezeState.frozenOrder
                    frozenListGroups = freezeState.primarySnapshot
                    frozenFlatSections = freezeState.secondarySnapshot
                } else if !isPointerInsideSurface, frozenOrder != nil {
                    withAnimation(TaskSurfaceFreezeSupport.releaseAnimation) {
                        var freezeState = TaskSurfaceFreezeState<FrozenTodayTaskGroup, FrozenFlatTaskSection>(
                            frozenOrder: frozenOrder,
                            primarySnapshot: frozenListGroups,
                            secondarySnapshot: frozenFlatSections
                        )
                        freezeState.release()
                        frozenOrder = freezeState.frozenOrder
                        frozenListGroups = freezeState.primarySnapshot
                        frozenFlatSections = freezeState.secondarySnapshot
                    }
                }
            }
            .onHover { isPointerInsideSurface = $0 }
    }
}

#endif
