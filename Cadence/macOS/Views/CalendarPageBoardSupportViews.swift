#if os(macOS)
import EventKit
import SwiftData
import SwiftUI

struct CalendarPageBoardView: View {
    private static let columnWidth: CGFloat = 306
    private static let columnSpacing: CGFloat = 14
    private static let horizontalPadding: CGFloat = 22

    let anchorDate: Date
    @Binding var selectedDate: Date
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let bundlesByDate: [String: [TaskBundle]]

    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @State private var isUpdatingSelectedDateFromScroll = false
    @State private var isProgrammaticScroll = false
    @State private var windowStartDate: Date?

    private let calendar = Calendar.current

    private var renderDays: Int {
        CalendarBoardPlannerSupport.plannerRenderDayCount
    }

    private var activeWindowStartDate: Date {
        windowStartDate ?? CalendarBoardPlannerSupport.plannerWindowStart(for: anchorDate, calendar: calendar)
    }

    private var boardTasksByDate: [String: [AppTask]] {
        CalendarBoardPlannerSupport.tasksByBoardDate(from: allTasks)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(0..<renderDays, id: \.self) { dayIndex in
                        let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
                        let dateKey = DateFormatters.dateKey(from: date)
                        CalendarBoardDayColumn(
                            dayIndex: dayIndex,
                            date: date,
                            dateKey: dateKey,
                            tasks: boardTasksByDate[dateKey] ?? [],
                            bundles: bundlesByDate[dateKey] ?? [],
                            events: calendarDisplayItems(for: date),
                            allTasks: allTasks,
                            allBundles: allBundles,
                            areas: areas,
                            projects: projects,
                            onAddTask: { createTask(on: dateKey) },
                            onDropTaskOnDay: { task in schedule(task, on: dateKey) },
                            onDropBundleOnDay: { bundle in move(bundle, on: dateKey) },
                            onDropTaskOnBundle: { task, bundle in
                                SchedulingActions.addTask(task, to: bundle)
                                try? modelContext.save()
                            }
                        )
                        .frame(width: Self.columnWidth)
                        .id(dayIndex)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .horizontal)
            .background(Theme.bg)
            .onScrollGeometryChange(for: Int.self) { geometry in
                visibleDayIndex(for: geometry.contentOffset.x)
            } action: { _, dayIndex in
                updateSelectedDate(for: dayIndex, proxy: proxy)
            }
            .onAppear {
                resetWindowAndScroll(proxy, to: anchorDate, animated: false)
            }
            .onChange(of: anchorDate) { _, newDate in
                if isUpdatingSelectedDateFromScroll {
                    isUpdatingSelectedDateFromScroll = false
                    return
                }
                resetWindowAndScroll(proxy, to: newDate, animated: true)
            }
        }
    }

    private func visibleDayIndex(for offsetX: CGFloat) -> Int {
        let stride = Self.columnWidth + Self.columnSpacing
        let rawIndex = Int(((offsetX - Self.horizontalPadding) / stride).rounded())
        return min(max(rawIndex, 0), renderDays - 1)
    }

    private func resetWindowAndScroll(_ proxy: ScrollViewProxy, to date: Date, animated: Bool) {
        let startDate = CalendarBoardPlannerSupport.plannerWindowStart(for: date, calendar: calendar)
        isProgrammaticScroll = true
        windowStartDate = startDate
        let target = CalendarBoardPlannerSupport.dayIndex(
            for: date,
            bufferStart: startDate,
            calendar: calendar,
            renderDays: renderDays
        )
        scroll(proxy, to: target, anchor: .leading, animated: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.26 : 0.08)) {
            isProgrammaticScroll = false
        }
    }

    private func recenterWindowIfNeeded(_ proxy: ScrollViewProxy, visibleDayIndex dayIndex: Int, visibleDate: Date) {
        guard !isProgrammaticScroll else { return }
        guard CalendarBoardPlannerSupport.shouldRecenter(dayIndex: dayIndex, renderDays: renderDays) else { return }

        let startDate = CalendarBoardPlannerSupport.plannerWindowStart(for: visibleDate, calendar: calendar)
        let recenteredDayIndex = CalendarBoardPlannerSupport.dayIndex(
            for: visibleDate,
            bufferStart: startDate,
            calendar: calendar,
            renderDays: renderDays
        )

        isProgrammaticScroll = true
        windowStartDate = startDate
        scroll(proxy, to: recenteredDayIndex, anchor: .leading, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isProgrammaticScroll = false
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to dayIndex: Int, anchor: UnitPoint, animated: Bool) {
        DispatchQueue.main.async {
            let clampedDayIndex = min(max(dayIndex, 0), renderDays - 1)
            if animated {
                withAnimation(.snappy(duration: 0.18)) {
                    proxy.scrollTo(clampedDayIndex, anchor: anchor)
                }
            } else {
                proxy.scrollTo(clampedDayIndex, anchor: anchor)
            }
        }
    }

    private func updateSelectedDate(for dayIndex: Int, proxy: ScrollViewProxy) {
        guard !isProgrammaticScroll else { return }
        let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
        if !calendar.isDate(date, inSameDayAs: selectedDate) {
            isUpdatingSelectedDateFromScroll = true
            selectedDate = date
        }
        recenterWindowIfNeeded(proxy, visibleDayIndex: dayIndex, visibleDate: date)
    }

    private func createTask(on dateKey: String) {
        let task = AppTask(title: "New Task")
        task.scheduledDate = dateKey
        task.scheduledStartMin = -1
        modelContext.insert(task)
        try? modelContext.save()
    }

    private func schedule(_ task: AppTask, on dateKey: String) {
        if task.bundle != nil {
            SchedulingActions.removeTaskFromBundle(task, keepOnBundleDate: false)
        }
        task.scheduledDate = dateKey
        if task.estimatedMinutes <= 0 {
            task.estimatedMinutes = 30
        }
        try? modelContext.save()
    }

    private func move(_ bundle: TaskBundle, on dateKey: String) {
        SchedulingActions.dropBundle(bundle, to: dateKey, startMin: bundle.startMin)
        try? modelContext.save()
    }

    @MainActor
    private func calendarDisplayItems(for date: Date) -> [CalendarBoardEventDisplayItem] {
        guard calendarManager.isAuthorized else { return [] }
        let _ = calendarManager.storeVersion
        let allDay = calendarManager.fetchAllDayEvents(for: date).map {
            CalendarBoardEventDisplayItem(allDay: $0, date: date, calendar: calendar)
        }
        let timed = CalendarEventItem
            .timedSegments(from: calendarManager.fetchEvents(for: date), for: date, calendar: calendar)
            .map(CalendarBoardEventDisplayItem.init(timed:))
        return (allDay + timed).sorted { $0.sortKey < $1.sortKey }
    }
}

private struct CalendarBoardDayColumn: View {
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
                        colors: [Theme.amber.opacity(0.82), Color.orange.opacity(0.44), Theme.amber.opacity(0.16)],
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
                            KanbanCard(task: task, presentation: .calendarBoard(dateKey: dateKey))
                                .suppressWindowBackgroundDrag()
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
            KanbanCard(task: task, presentation: .calendarBoard(dateKey: dateKey))
                .suppressWindowBackgroundDrag()
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
