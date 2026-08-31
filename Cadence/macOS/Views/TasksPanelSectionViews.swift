#if os(macOS)
import SwiftUI

/// A single list-level task group (one area / project / Inbox).
///
/// `contextIcon` / `contextColor` are **not** used by Today, which groups by list
/// only. They exist for `TasksListView`, which still shows a small context glyph beside the list
/// icon. `TasksPanel`'s `.byDoDate` list grouping was the other reader and is gone (T-487).
struct TodayTaskGroup: Identifiable {
    let id: String
    let contextIcon: String?
    let contextColor: Color?
    let listIcon: String
    let listName: String
    let listColor: Color
    var tasks: [AppTask]
}

// `FrozenTodayTaskGroup`, `FrozenFlatTaskSection`, `TasksPanelGroupSectionView` and
// `TasksPanelFlatSectionView` were here — the list-grouped and flat section rows, and the two
// snapshot types the hover freeze rehydrated them from. All four existed only for `TasksPanel`'s
// `.byDoDate` mode, which nothing could reach, and all four went with it (T-487). Today's sections
// are `TasksPanelIntentSectionView` below; `TasksListView` and `ListDetailComponents` draw their
// own and never used these.

/// How far Today's rows are indented from the pane's leading edge.
///
/// **Deliberately not `TaskListDisplayMetrics.taskLeadingInset` (52).** That inset clears a list
/// detail's own leading furniture; Today's rows sit directly under a panel header and are indented
/// to match it. The **trailing** gutter has no such story — both surfaces need the hover fill and
/// its 1pt border to stop short of the divider — so Today reads
/// `TaskListDisplayMetrics.taskTrailingInset` rather than restating 12. It had no trailing padding
/// at all until T-593, which is why Today alone drew rows flush to the divider.
private let todayRowLeadingInset: CGFloat = 16

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
    /// The panel's surface answer, narrowed by the group's own — see `TasksPanel.options` and
    /// `CadenceTodayTaskGroup.showsContainerChip`.
    let showsContainer: Bool
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
                    // `.standard`, not `.todayGrouped`: that style suppresses the do-date pill as
                    // well as the list chip, and the do date is a thing Today's rows still have to
                    // say — a list group holds work due today and work merely planned for it, and
                    // the row is the only thing that tells them apart. The **list** chip is
                    // withheld by `showsContainer` instead (`CadenceTodayTaskGroup`
                    // .showsContainerChip), which is off inside a list group and on inside Overdue,
                    // so the one duplication `.todayGrouped` existed to avoid is still avoided
                    // without losing the date.
                    MacTaskRow(task: task, style: .standard, showsContainer: showsContainer, contexts: contexts, areas: areas, projects: projects)
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
                                Rectangle()
                                    .fill(Theme.blue)
                                    .frame(height: 2)
                                    .padding(.leading, todayRowLeadingInset)
                                    .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                        .padding(.leading, todayRowLeadingInset)
                        .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
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
    /// The panel's surface answer — see `TasksPanel.options`.
    let showsContainer: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let isCollapsed: Bool
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String

    var body: some View {
        Section {
            // The day's finished work, headed and tinted like every other Today group:
            // `CadenceTodayPresentationSupport` owns both, and iOS reads the same two constants.
            //
            // There was an `else` here drawing `CompletedSectionHeader`'s neutral "Completed" for
            // the `.byDoDate` logbook — everything ever finished, a different thing from the day's
            // work. It went with the mode, and so did that header (T-487).
            TasksPanelIntentSectionHeader(
                title: CadenceTodayPresentationSupport.completedSectionTitle,
                accent: CadenceTodayPresentationSupport.completedSectionAccent,
                count: tasks.count,
                isCollapsed: isCollapsed,
                onToggle: onToggle
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)

            if !isCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: .standard, showsContainer: showsContainer, contexts: contexts, areas: areas, projects: projects)
                        .draggable(taskDragPayload(task))
                        .padding(.leading, todayRowLeadingInset)
                        .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
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

/// **Only the row order.** This carried two more bindings and two more snapshot arguments — the
/// frozen list groups and the frozen flat sections — and both were `.byDoDate`'s. Today's call
/// site already passed `[]` for each, so `TaskSurfaceFreezeCoordinator.capture` (which only writes
/// a snapshot when its source is non-empty) provably left both `nil` on every frame this observer
/// has ever run. They went with the mode (T-487); the row-order freeze, which is the part Today
/// uses, is untouched and still goes through the shared coordinator rather than a local copy.
struct HoverFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenOrder: [AppTask]?
    let naturalTasks: [AppTask]
    @State private var isPointerInsideSurface = false
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if newID != nil {
                    var freezeState = TaskSurfaceFreezeState<Never, Never>(
                        frozenOrder: frozenOrder,
                        primarySnapshot: nil,
                        secondarySnapshot: nil
                    )
                    // Only write back when something was actually frozen. Writing an unchanged
                    // value into a `@State` binding still invalidates the owning panel, and this
                    // fires on every row boundary the pointer crosses.
                    guard freezeState.captureIfNeeded(
                        naturalTasks: naturalTasks,
                        sourcePrimarySnapshot: [],
                        sourceSecondarySnapshot: []
                    ) else { return }
                    frozenOrder = freezeState.frozenOrder
                } else if !isPointerInsideSurface, frozenOrder != nil {
                    withAnimation(TaskSurfaceFreezeSupport.releaseAnimation) {
                        var freezeState = TaskSurfaceFreezeState<Never, Never>(
                            frozenOrder: frozenOrder,
                            primarySnapshot: nil,
                            secondarySnapshot: nil
                        )
                        freezeState.release()
                        frozenOrder = freezeState.frozenOrder
                    }
                }
            }
            .onHover { isPointerInsideSurface = $0 }
    }
}

#endif
