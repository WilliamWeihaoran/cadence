#if os(macOS)
import SwiftUI

/// A single list-level task group (one area / project / Inbox).
///
/// `contextIcon` / `contextColor` are **not** used by Today, which groups by list
/// only. They exist for `TasksListView` (and `TasksPanel`'s `.byDoDate` list
/// grouping), which still shows a small context glyph beside the list icon.
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

/// No `labelColor`. It only ever reached `CollapsibleTaskGroupHeader`'s count, which is neutral
/// now, so carrying it was a parameter that promised to colour a section and coloured nothing.
struct FrozenFlatTaskSection {
    let id: String
    let title: String
    let dropKey: String?
    let taskIDs: [UUID]
}

struct TasksPanelGroupSectionView: View {
    let group: TodayTaskGroup
    @Binding var dragOverTaskID: UUID?
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    var showsContextIcon: Bool = true
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

                if showsContextIcon, let ctxIcon = group.contextIcon, let ctxColor = group.contextColor {
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
                    .lineLimit(1)

                Spacer()

                // Neutral, like `CollapsibleTaskGroupHeader`'s: `Theme.muted` still reads as the
                // emphasised half of "3 / 7" without spending red on a number.
                if let overdueCount, overdueCount > 0 {
                    Text("\(overdueCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
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
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    let onDropOnSectionPayload: ((String) -> Bool)?
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        Section {
            CollapsibleTaskGroupHeader(
                title: label,
                isCollapsed: isCollapsed,
                overdueCount: overdueCount,
                regularCount: regularCount,
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

/// One of Today's intent groups — Overdue / Past Do / Due Today / Planned Today — and the day's
/// Completed group under them.
///
/// **The sections say why a task is in front of you, not where it lives.** macOS's Today grouped by
/// list (one flat tier of area/project groups in sidebar order) while both iOS Todays grouped by
/// intent, so the same day read as an inventory on one platform and as a plan on the other. The
/// intent vocabulary wins, and it wins from `CadenceTaskQuerySupport.todayGroups` — the function
/// iOS already called — rather than from a second macOS copy of the same four predicates, which is
/// what `todayDateSections` was: the same buckets under the names "Past Due" and "Do Today".
///
/// The disclosure chevron is kept, and is the one thing iOS's group header does not have. It is a
/// pointer affordance over persisted per-section state (`collapsedGroupIDs`), not a difference in
/// how the row is *drawn* — the heading itself is `CadenceTaskGroupHeading`, shared.
struct TasksPanelIntentSectionView: View {
    let title: String
    let accent: Color
    let tasks: [AppTask]
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let isCollapsed: Bool
    /// Dimmed as a whole rather than row by row, the way iOS dims its Completed group.
    var opacity: Double = 1
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    /// `nil` for a group defined by a day that has already gone by — there is nothing a drop could
    /// mean for "Overdue". `CadenceTaskDropSupport.dropKey(forGroup:)` decides, for both platforms.
    let onDropOnSectionPayload: ((String) -> Bool)?
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        Section {
            header
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
                    // `.standard`, not `.todayGrouped`: that style suppresses the do-date pill and
                    // the list chip because the *group header* used to name the list. Today groups
                    // by intent now, so the row is the only thing that can say where a task lives
                    // and when it was meant to be done — which is what iOS's Today row already
                    // said, chip for chip.
                    MacTaskRow(task: task, style: .standard, contexts: contexts, areas: areas, projects: projects)
                        .opacity(opacity)
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

    private var header: some View {
        TasksPanelIntentSectionHeader(
            title: title,
            accent: accent,
            count: tasks.count,
            isCollapsed: isCollapsed,
            onToggle: onToggle
        )
    }
}

/// Chevron, then `CadenceTaskGroupHeading`. One hover layer, at `CollapsibleTaskGroupHeader`'s
/// radius and fill — the same neutral wash the rows below take, and the only one on this row.
struct TasksPanelIntentSectionHeader: View {
    let title: String
    let accent: Color
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                CadenceTaskGroupHeading(title: title, tint: accent, count: count)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(shape.fill(TaskHoverVisuals.hoverFill(isHovered: isHovered)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }
}

struct TasksPanelCompletedSectionView: View {
    let tasks: [AppTask]
    let mode: TasksPanelMode
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let isCollapsed: Bool
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String

    var body: some View {
        Section {
            // On Today this is the day's finished work, headed and tinted like every other Today
            // group: `CadenceTodayPresentationSupport` owns both, and iOS reads the same two
            // constants. The `.byDoDate` logbook is a different thing — everything ever finished —
            // and keeps its neutral "Completed".
            Group {
                if mode == .todayOverview {
                    TasksPanelIntentSectionHeader(
                        title: CadenceTodayPresentationSupport.completedSectionTitle,
                        accent: CadenceTodayPresentationSupport.completedSectionAccent,
                        count: tasks.count,
                        isCollapsed: isCollapsed,
                        onToggle: onToggle
                    )
                } else {
                    CompletedSectionHeader(
                        count: tasks.count,
                        isCollapsed: isCollapsed,
                        onToggle: onToggle
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)

            if !isCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: .standard, contexts: contexts, areas: areas, projects: projects)
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

// `TasksPanelRolloverNoticeSectionView` was here. It is
// `Shared/Components/CadenceTodayRolloverBanner.swift` now, at `.panelBand` style — nothing in it
// was AppKit-shaped, and it being under `macOS/Views/` was one of the three reasons Today's
// rollover notice could not exist on iOS (T-195). `TasksPanel` builds the shared view directly;
// there is deliberately no macOS-named wrapper to reach for.

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
                    // Only write back when something was actually frozen. Writing an unchanged
                    // value into a `@State` binding still invalidates the owning panel, and this
                    // fires on every row boundary the pointer crosses.
                    guard freezeState.captureIfNeeded(
                        naturalTasks: naturalTasks,
                        sourcePrimarySnapshot: listGroupSnapshot,
                        sourceSecondarySnapshot: flatSectionSnapshot
                    ) else { return }
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
