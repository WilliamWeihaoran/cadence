#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCalendarBoardPlanner: View {
    @Binding var anchorDate: Date
    @Binding var selectedDate: Date
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let bundlesByDate: [String: [TaskBundle]]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @State private var isUpdatingSelectedDateFromScroll = false
    @State private var isProgrammaticScroll = false
    @State private var windowStartDate: Date?

    private let calendar = Calendar.current
    private let renderDays = CalendarBoardPlannerSupport.plannerRenderDayCount
    private let columnSpacing: CGFloat = 10

    private var columnWidth: CGFloat {
        horizontalSizeClass == .regular ? 300 : 268
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 20 : 14
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
                LazyHStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(0..<renderDays, id: \.self) { dayIndex in
                        let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
                        let dateKey = DateFormatters.dateKey(from: date)
                        iOSCalendarBoardDayColumn(
                            dayIndex: dayIndex,
                            date: date,
                            dateKey: dateKey,
                            tasks: boardTasksByDate[dateKey] ?? [],
                            bundles: bundlesByDate[dateKey] ?? [],
                            allTasks: allTasks,
                            allBundles: allBundles,
                            onAddTask: { createTask(on: dateKey) },
                            onDropTaskOnDay: { task in schedule(task, on: dateKey) },
                            onDropBundleOnDay: { bundle in move(bundle, on: dateKey) },
                            onDropTaskOnBundle: { task, bundle in add(task, to: bundle) }
                        )
                        .frame(width: columnWidth)
                        .id(dayIndex)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
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
        let stride = columnWidth + columnSpacing
        let rawIndex = Int(((offsetX - horizontalPadding) / stride).rounded())
        return min(max(rawIndex, 0), renderDays - 1)
    }

    private func resetWindowAndScroll(_ proxy: ScrollViewProxy, to date: Date, animated: Bool) {
        let startDate = CalendarBoardPlannerSupport.plannerWindowStart(for: date, calendar: calendar)
        isProgrammaticScroll = true
        windowStartDate = startDate
        let target = CalendarBoardPlannerSupport.dayIndex(for: date, bufferStart: startDate, calendar: calendar, renderDays: renderDays)
        scroll(proxy, to: target, animated: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.28 : 0.08)) {
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
        scroll(proxy, to: recenteredDayIndex, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isProgrammaticScroll = false
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to dayIndex: Int, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.snappy(duration: 0.22)) {
                    proxy.scrollTo(min(max(dayIndex, 0), renderDays - 1), anchor: .leading)
                }
            } else {
                proxy.scrollTo(min(max(dayIndex, 0), renderDays - 1), anchor: .leading)
            }
        }
    }

    private func updateSelectedDate(for dayIndex: Int, proxy: ScrollViewProxy) {
        guard !isProgrammaticScroll else { return }
        let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
        if !calendar.isDate(date, inSameDayAs: selectedDate) {
            selectedDate = date
        }
        if !calendar.isDate(date, inSameDayAs: anchorDate) {
            isUpdatingSelectedDateFromScroll = true
            anchorDate = date
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
        task.bundle = nil
        task.bundleOrder = 0
        task.scheduledDate = dateKey
        if task.estimatedMinutes <= 0 {
            task.estimatedMinutes = 30
        }
        try? modelContext.save()
    }

    private func move(_ bundle: TaskBundle, on dateKey: String) {
        let oldDateKey = bundle.dateKey
        bundle.dateKey = dateKey
        for task in bundle.tasks ?? [] where task.scheduledDate == oldDateKey {
            task.scheduledDate = dateKey
        }
        try? modelContext.save()
    }

    private func add(_ task: AppTask, to bundle: TaskBundle) {
        let nextOrder = ((bundle.tasks ?? []).map(\.bundleOrder).max() ?? -1) + 1
        task.bundle = bundle
        task.bundleOrder = nextOrder
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        try? modelContext.save()
    }
}

private struct iOSCalendarBoardDayColumn: View {
    let dayIndex: Int
    let date: Date
    let dateKey: String
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let onAddTask: () -> Void
    let onDropTaskOnDay: (AppTask) -> Void
    let onDropBundleOnDay: (TaskBundle) -> Void
    let onDropTaskOnBundle: (AppTask, TaskBundle) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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

    private var activeItems: [iOSCalendarBoardColumnItem] {
        let bundleItems = bundles.map { iOSCalendarBoardColumnItem.bundle($0) }
        let taskItems = activeTasks.map { iOSCalendarBoardColumnItem.task($0) }
        return (bundleItems + taskItems).sorted(by: sortColumnItems)
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
        } isTargeted: { isDropTargeted = $0 }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormatters.dayOfWeek.string(from: date))
                    .font(.system(size: horizontalSizeClass == .regular ? 21 : 19, weight: .bold))
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
        .buttonStyle(.plain)
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
                .buttonStyle(.plain)

                if !isCompletedCollapsed {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(completedTasks.sorted { lhs, rhs in
                            CalendarBoardPlannerSupport.boardTaskSort(lhs, rhs)
                        }) { task in
                            iOSCalendarBoardTaskCard(task: task, dateKey: dateKey)
                                .draggable(TaskDragPayload.string(for: task.id))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private func columnItemView(_ item: iOSCalendarBoardColumnItem) -> some View {
        switch item {
        case .bundle(let bundle):
            iOSCalendarBoardBundleCard(
                bundle: bundle,
                allTasks: allTasks,
                onDropTask: { task in
                    rememberBundleTaskDrop(task)
                    onDropTaskOnBundle(task, bundle)
                },
                onDropTargetedChanged: { targeted in
                    updateTargetedBundle(bundle, targeted: targeted)
                }
            )
        case .task(let task):
            iOSCalendarBoardTaskCard(task: task, dateKey: dateKey)
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
           let bundle = allBundles.first(where: { $0.id == bundleID }) {
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

    private func sortColumnItems(_ lhs: iOSCalendarBoardColumnItem, _ rhs: iOSCalendarBoardColumnItem) -> Bool {
        let lhsStart = lhs.sortStartMinute
        let rhsStart = rhs.sortStartMinute
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }
        if lhs.kindRank != rhs.kindRank {
            return lhs.kindRank < rhs.kindRank
        }
        switch (lhs, rhs) {
        case (.task(let lhsTask), .task(let rhsTask)):
            return CalendarBoardPlannerSupport.boardTaskSort(lhsTask, rhsTask)
        case (.bundle(let lhsBundle), .bundle(let rhsBundle)):
            if lhsBundle.createdAt != rhsBundle.createdAt {
                return lhsBundle.createdAt < rhsBundle.createdAt
            }
            return lhsBundle.id.uuidString < rhsBundle.id.uuidString
        default:
            return lhs.id < rhs.id
        }
    }
}

private enum iOSCalendarBoardColumnItem: Identifiable {
    case bundle(TaskBundle)
    case task(AppTask)

    var id: String {
        switch self {
        case .bundle(let bundle):
            return "bundle-\(bundle.id.uuidString)"
        case .task(let task):
            return "task-\(task.id.uuidString)"
        }
    }

    var kindRank: Int {
        switch self {
        case .bundle:
            return 0
        case .task:
            return 1
        }
    }

    var sortStartMinute: Int {
        switch self {
        case .bundle(let bundle):
            return bundle.startMin
        case .task(let task):
            return task.scheduledStartMin >= 0 ? task.scheduledStartMin : Int.max
        }
    }
}

private struct iOSCalendarBoardTaskCard: View {
    @Bindable var task: AppTask
    let dateKey: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showDetail = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.priorityColor(task.priority))
                .frame(width: 3.5)
                .padding(.leading, 10)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Button(action: toggleCompletion) {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: isRegularWidth ? 17 : 15, weight: .semibold))
                            .foregroundStyle(task.isDone ? Theme.green : Theme.dim.opacity(0.72))
                    }
                    .buttonStyle(.plain)

                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: isRegularWidth ? 14 : 13, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(metadataChips, id: \.id) { chip in
                        iOSCalendarBoardMetadataChip(item: chip)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
        }
        .background(Theme.surfaceElevated.opacity(0.72))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            showDetail = true
        }
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }

    private var metadataChips: [iOSCalendarBoardMetadataItem] {
        var chips: [iOSCalendarBoardMetadataItem] = []

        if task.scheduledStartMin >= 0 {
            chips.append(
                .init(
                    id: "time",
                    icon: "clock.fill",
                    title: TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin),
                    color: Theme.blue
                )
            )
        }

        if !task.dueDate.isEmpty {
            chips.append(
                .init(
                    id: "due",
                    icon: "flag.fill",
                    title: DateFormatters.relativeDate(from: task.dueDate),
                    color: task.dueDate < DateFormatters.todayKey() && !task.isDone ? Theme.red : Theme.dim
                )
            )
        }

        chips.append(
            .init(
                id: "list",
                icon: task.project?.icon ?? task.area?.icon ?? "tray.fill",
                title: task.containerName.isEmpty ? "Inbox" : task.containerName,
                color: Color(hex: task.containerColor)
            )
        )

        return chips
    }

    private func toggleCompletion() {
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
    }
}

private struct iOSCalendarBoardBundleCard: View {
    let bundle: TaskBundle
    let allTasks: [AppTask]
    let onDropTask: (AppTask) -> Void
    var onDropTargetedChanged: (Bool) -> Void = { _ in }

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text(bundle.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        iOSCalendarBoardMetadataChip(
                            item: .init(
                                id: "time",
                                icon: "clock",
                                title: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                                color: Theme.amber
                            )
                        )
                        iOSCalendarBoardMetadataChip(
                            item: .init(
                                id: "tasks",
                                icon: "checklist",
                                title: "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")",
                                color: Theme.dim
                            )
                        )
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(0.78))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.amber.opacity(isTargeted ? 0.18 : 0.07))
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.amber.opacity(isTargeted ? 0.74 : 0.24), lineWidth: isTargeted ? 1.25 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .draggable(TaskDragPayload.bundleString(for: bundle.id))
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first,
                  let taskID = TaskDragPayload.taskID(from: payload),
                  let task = allTasks.first(where: { $0.id == taskID }) else { return false }
            onDropTask(task)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
            onDropTargetedChanged(targeted)
        }
    }
}

private struct iOSCalendarBoardMetadataItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let color: Color
}

private struct iOSCalendarBoardMetadataChip: View {
    let item: iOSCalendarBoardMetadataItem

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(item.color)
                .frame(width: 10)
            Text(item.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#endif
