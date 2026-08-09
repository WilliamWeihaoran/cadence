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
    let onAddTask: () -> Void
    let onDropTaskOnDay: (AppTask) -> Void
    let onDropBundleOnDay: (TaskBundle) -> Void
    let onDropTaskOnBundle: (AppTask, TaskBundle) -> Void

    @State private var isDropTargeted = false
    @State private var targetedBundleID: UUID?
    @State private var recentlyBundledTaskID: UUID?
    @State private var recentlyBundledTaskDropExpiresAt = Date.distantPast
    @State private var isCompletedCollapsed = true
    @State private var isHovered = false

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

            // Same scroll container the kanban columns use, so "Add task" sits last in the
            // column here exactly as it does there.
            KanbanColumnScroll(isColumnHovered: isHovered, onAddTask: onAddTask) {
                content
                completedFooter
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .onHover { isHovered = $0 }
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
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityLabel("\(DateFormatters.longDate.string(from: date)), \(totalCount) scheduled item\(totalCount == 1 ? "" : "s")")
    }

    /// The shared board header. The only things that differ from a kanban or Planning column are
    /// the label text (weekday + date) and — for today only — the amber rule in place of the
    /// neutral hairline, which is the single sanctioned exception to the shared treatment.
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
                    rememberBundleTaskDrop(task)
                    onDropTaskOnBundle(task, bundle)
                },
                onDropTargetedChanged: { targeted in
                    updateTargetedBundle(bundle, targeted: targeted)
                }
            )
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

    private func handleDrop(_ items: [String]) -> Bool {
        guard let payload = items.first else { return false }
        if let bundleID = TaskDragPayload.bundleID(from: payload),
           let bundle = allBundlesLookup(bundleID) {
            onDropBundleOnDay(bundle)
            return true
        }
        if let taskID = TaskDragPayload.taskID(from: payload),
           let task = allTasks.first(where: { $0.id == taskID }) {
            if shouldSuppressDayDrop(for: taskID) {
                return true
            }
            onDropTaskOnDay(task)
            return true
        }
        return false
    }

    private func updateTargetedBundle(_ bundle: TaskBundle, targeted: Bool) {
        if targeted {
            targetedBundleID = bundle.id
        } else if targetedBundleID == bundle.id {
            targetedBundleID = nil
        }
    }

    private func rememberBundleTaskDrop(_ task: AppTask) {
        recentlyBundledTaskID = task.id
        recentlyBundledTaskDropExpiresAt = Date().addingTimeInterval(0.75)
    }

    private func shouldSuppressDayDrop(for taskID: UUID) -> Bool {
        if targetedBundleID != nil {
            return true
        }
        if recentlyBundledTaskID == taskID, Date() < recentlyBundledTaskDropExpiresAt {
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
