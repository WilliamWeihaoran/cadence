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
        VStack(alignment: .leading, spacing: 12) {
            header
            todayAccent
            addTaskButton
            content
            completedFooter
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
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

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormatters.dayOfWeek.string(from: date))
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(DateFormatters.shortDate.string(from: date))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isToday {
                Text("Today")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.amber.opacity(0.13))
                    .clipShape(Capsule())
            }

            Text("\(totalCount)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isToday ? Theme.amber : Theme.dim)
                .frame(minWidth: 26, minHeight: 24)
                .background((isToday ? Theme.amber : Theme.surfaceElevated).opacity(isToday ? 0.14 : 0.82))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var todayAccent: some View {
        if isToday {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Theme.amber.opacity(0.82), Theme.amber.opacity(0.44), Theme.amber.opacity(0.16)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .padding(.horizontal, 2)
                .shadow(color: Theme.amber.opacity(0.22), radius: 8, y: 2)
                .accessibilityHidden(true)
        }
    }

    private var addTaskButton: some View {
        Button(action: onAddTask) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add task")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Theme.surfaceElevated.opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.50), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
        .help("Add a task planned for \(DateFormatters.shortDate.string(from: date))")
    }

    @ViewBuilder
    private var content: some View {
        if !activeItems.isEmpty {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(activeItems) { item in
                        columnItemView(item)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var completedFooter: some View {
        if !completedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        isCompletedCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCompletedCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 12)
                        Text("Completed")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        Text("\(completedTasks.count)")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.surfaceElevated.opacity(0.72))
                            .clipShape(Capsule())
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Theme.surfaceElevated.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(0.35), lineWidth: 1)
                    }
                }
                .buttonStyle(.cadencePlain)

                if !isCompletedCollapsed {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(completedTasks.sorted { lhs, rhs in
                            CalendarBoardPlannerSupport.boardTaskSort(lhs, rhs)
                        }) { task in
                            KanbanCard(task: task, presentation: .calendarBoard)
                                .draggable(TaskDragPayload.string(for: task.id))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
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
            KanbanCard(task: task, presentation: .calendarBoard)
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
