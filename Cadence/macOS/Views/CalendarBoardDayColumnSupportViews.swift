#if os(macOS)
import SwiftUI

struct CalendarBoardDayColumn: View {
    let dayIndex: Int
    let date: Date
    let dateKey: String
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let events: [CalendarBoardEventDisplayItem]
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    /// What the column's ghost row does. A day column always composes in place — it supplies the
    /// day — but the decision still comes from `CalendarBoardPlannerSupport.addAction(for:)` so the
    /// board's columns and rails answer it in one place.
    let add: KanbanColumnAddBehavior?
    let onDropTaskOnDay: (AppTask) -> Void
    let onDropBundleOnDay: (TaskBundle) -> Void
    let onDropTaskOnBundle: (AppTask, TaskBundle) -> Void

    @Environment(HoveredKanbanColumnManager.self) private var hoveredKanbanColumnManager
    @State private var isDropTargeted = false
    /// Where each bundle card sits, in this column's own coordinate space — the space
    /// `dropDestination` reports its release point in. See `bundleOwningBoardDrop`.
    @State private var bundleFrames: [UUID: CGRect] = [:]
    @State private var isCompletedCollapsed = true
    @State private var isHovered = false
    @State private var isComposing = false

    private var coordinateSpaceName: String { "calendarBoardDayColumn-\(dayIndex)" }

    /// Keyed by the day, not by `dayIndex`: the board slides its render window, so the same index
    /// is a different day after a recenter, and a hover registered under an index would answer
    /// Cmd+N for whichever day had drifted into that slot.
    private var columnHoverID: String { CalendarBoardDayColumn.hoverID(dateKey: dateKey) }

    static func hoverID(dateKey: String) -> String {
        "calendar-board-day-column-\(dateKey)"
    }

    private var isToday: Bool {
        dateKey == DateFormatters.todayKey()
    }

    private var activeTasks: [AppTask] {
        tasks.filter { !$0.isDone }
    }

    private var completedTasks: [AppTask] {
        tasks.filter { $0.isDone }
    }

    private var activeItems: [CalendarBoardColumnItem] {
        let eventItems = events.map { CalendarBoardColumnItem.event($0) }
        let bundleItems = bundles.map { CalendarBoardColumnItem.bundle($0) }
        let taskItems = activeTasks.map { CalendarBoardColumnItem.task($0) }
        return (eventItems + bundleItems + taskItems).sorted(by: sortColumnItems)
    }

    private var totalCount: Int {
        activeItems.count + completedTasks.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // Same scroll container the kanban columns use, so "Add task" — and the composer that
            // replaces it — sits last in the column here exactly as it does there.
            KanbanColumnScroll(isColumnHovered: isHovered, add: add, isComposing: $isComposing) {
                content
                completedFooter
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        // Registering with `HoveredKanbanColumnManager` is what makes Cmd+N work here, the same way
        // it works over a kanban section column and an All Tasks list column. The day column used to
        // set only `isHovered`, so the shortcut documented as "open the inline composer in the
        // hovered column" silently did nothing on this board and the ghost row was the only way in.
        .onHover { hovering in
            isHovered = hovering
            if hovering, add.opensInlineComposer {
                hoveredKanbanColumnManager.beginHovering(id: columnHoverID) {
                    isComposing = true
                }
            } else {
                hoveredKanbanColumnManager.endHovering(id: columnHoverID)
            }
        }
        .background(laneBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.28))
                .frame(width: 1)
                .padding(.vertical, 3)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.72), style: StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                    .padding(2)
            }
        }
        .contentShape(Rectangle())
        // Named at exactly the layer `dropDestination` decorates, so a release point and a measured
        // card frame are in the same space by construction rather than by coincidence.
        .coordinateSpace(.named(coordinateSpaceName))
        .dropDestination(for: String.self) { items, location in
            handleDrop(items, at: location)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityLabel("\(DateFormatters.longDate.string(from: date)), \(totalCount) scheduled item\(totalCount == 1 ? "" : "s")")
    }

    /// The shared board header. The only things that differ from a kanban column or one of this
    /// board's rails are the label text (weekday + date) and — for today only — the amber rule in
    /// place of the neutral hairline, which is the single sanctioned exception to the treatment.
    private var header: some View {
        BoardColumnHeader(
            dotColor: isToday ? Theme.amber : Theme.dim,
            title: "\(DateFormatters.dayOfWeek.string(from: date)) · \(DateFormatters.shortDate.string(from: date))",
            count: activeItems.count,
            accentRule: isToday ? Theme.amber : nil
        )
    }

    @ViewBuilder
    private var content: some View {
        ForEach(activeItems) { item in
            columnItemView(item)
        }
    }

    @ViewBuilder
    private var completedFooter: some View {
        if !completedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                KanbanCompletedTasksToggle(count: completedTasks.count, isExpanded: !isCompletedCollapsed) {
                    withAnimation(.snappy(duration: 0.16)) {
                        isCompletedCollapsed.toggle()
                    }
                }

                if !isCompletedCollapsed {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(completedTasks.sorted { lhs, rhs in
                            CalendarBoardPlannerSupport.boardTaskSort(lhs, rhs)
                        }) { task in
                            KanbanCard(task: task, showsContainerChip: true)
                                .draggable(TaskDragPayload.string(for: task.id))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func columnItemView(_ item: CalendarBoardColumnItem) -> some View {
        switch item {
        case .event(let item):
            CalendarBoardEventCard(item: item)
        case .bundle(let bundle):
            CalendarBoardBundleCard(
                bundle: bundle,
                allTasks: allTasks,
                areas: areas,
                projects: projects,
                onDropTask: { task in
                    onDropTaskOnBundle(task, bundle)
                }
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(coordinateSpaceName))
            } action: { rect in
                bundleFrames[bundle.id] = rect
            }
        case .task(let task):
            KanbanCard(task: task, showsContainerChip: true)
                .draggable(TaskDragPayload.string(for: task.id))
        }
    }

    @ViewBuilder
    private var laneBackground: some View {
        if isToday || isDropTargeted {
            LinearGradient(
                colors: [
                    (isDropTargeted ? Theme.blue : Theme.amber).opacity(isDropTargeted ? 0.10 : 0.055),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.clear
        }
    }

    private func handleDrop(_ items: [String], at location: CGPoint) -> Bool {
        guard let payload = items.first else { return false }
        if let bundleID = TaskDragPayload.bundleID(from: payload),
           let bundle = allBundlesLookup(bundleID) {
            onDropBundleOnDay(bundle)
            return true
        }
        if let taskID = TaskDragPayload.taskID(from: payload),
           let task = allTasks.first(where: { $0.id == taskID }) {
            // Released on top of one of this column's bundle cards: that card's own drop handler
            // owns the gesture. Answering the day drop as well would re-file the task onto the day
            // and, through `removeTaskFromBundle`, undo the bundling that just happened.
            guard CalendarBoardPlannerSupport.bundleOwningBoardDrop(
                at: location,
                bundleIDs: bundles.map(\.id),
                bundleFrames: bundleFrames
            ) == nil else { return true }
            onDropTaskOnDay(task)
            return true
        }
        return false
    }

    private func sortColumnItems(_ lhs: CalendarBoardColumnItem, _ rhs: CalendarBoardColumnItem) -> Bool {
        let lhsKey = lhs.sortKey
        let rhsKey = rhs.sortKey
        if lhsKey != rhsKey { return lhsKey < rhsKey }
        switch (lhs, rhs) {
        case (.task(let lhsTask), .task(let rhsTask)):
            return CalendarBoardPlannerSupport.boardTaskSort(lhsTask, rhsTask)
        case (.bundle(let lhsBundle), .bundle(let rhsBundle)):
            if lhsBundle.createdAt != rhsBundle.createdAt {
                return lhsBundle.createdAt < rhsBundle.createdAt
            }
            return lhsBundle.id.uuidString < rhsBundle.id.uuidString
        case (.event(let lhsEvent), .event(let rhsEvent)):
            return lhsEvent.id < rhsEvent.id
        default:
            return lhs.id < rhs.id
        }
    }

    private func allBundlesLookup(_ id: UUID) -> TaskBundle? {
        allBundles.first(where: { $0.id == id }) ?? bundles.first(where: { $0.id == id })
    }
}

private enum CalendarBoardColumnItem: Identifiable {
    case event(CalendarBoardEventDisplayItem)
    case bundle(TaskBundle)
    case task(AppTask)

    var id: String {
        switch self {
        case .event(let item):
            return "event-\(item.id)"
        case .bundle(let bundle):
            return "bundle-\(bundle.id.uuidString)"
        case .task(let task):
            return "task-\(task.id.uuidString)"
        }
    }

    var sortKey: CalendarBoardSortKey {
        switch self {
        case .event(let item):
            return item.sortKey
        case .bundle(let bundle):
            return CalendarBoardPlannerSupport.sortKey(for: bundle, kindRank: 1)
        case .task(let task):
            return CalendarBoardPlannerSupport.sortKey(for: task, kindRank: 2)
        }
    }
}
#endif
