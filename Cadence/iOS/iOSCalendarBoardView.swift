#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarBoardPlanner: View {
    @Binding var anchorDate: Date
    @Binding var selectedDate: Date
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]
    let onAddItem: (String) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @State private var isUpdatingSelectedDateFromScroll = false
    /// The day column at the board's leading edge — both the scroll position it is *set* to and the
    /// one it reports back after a scroll. `scrollPosition(id:)` is what places a lazy board, and it
    /// replaced a `ScrollViewReader` + `onScrollGeometryChange` pair that could not.
    ///
    /// That pair had `onAppear` call `proxy.scrollTo(210)` on a 420-column `LazyHStack` whose
    /// columns had not been built yet, so the scroll silently did nothing; geometry then reported
    /// column 0 — the start of the leading buffer, `plannerLeadingDayCount` days behind the anchor —
    /// and that reading was written back into `selectedDate` and `anchorDate` as if the user had
    /// scrolled there. Every entry into Board landed roughly seven months in the past, and only the
    /// toolbar's Today button could get out. `scrollPosition(id:)` resolves the initial offset from
    /// the id itself, before the first render, so there is nothing to race.
    ///
    /// Seeded with the index the first window puts the anchor at, so the very first render is
    /// already correct rather than corrected — and re-asserted once the `LazyHStack` reports that
    /// it has laid out, because a seeded value is not a scroll position until there are columns for
    /// it to resolve against. Month's agenda paid for the missing half of that rule; see
    /// `CadenceLazyScrollAnchor`.
    @State private var scrolledDayIndex: Int? = CalendarBoardPlannerSupport.plannerLeadingDayCount
    /// Set by the first report that agrees with the placement. Until then this board believes
    /// nothing it is told about where it is scrolled — see the switch in `board(columnWidth:)`.
    @State private var didConfirmInitialColumn = false
    @State private var windowStartDate: Date?

    private let calendar = Calendar.current
    private let renderDays = CalendarBoardPlannerSupport.plannerRenderDayCount
    private let columnSpacing: CGFloat = 10

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// iPad keeps its fixed multi-column board. iPhone gets one column per screen with the next one
    /// peeking — see `CalendarBoardPlannerSupport.compactColumnWidth`.
    private func columnWidth(containerWidth: CGFloat) -> CGFloat {
        guard !isRegularWidth else { return iOSBoardColumnWidth }
        return CalendarBoardPlannerSupport.compactColumnWidth(
            containerWidth: containerWidth,
            leadingInset: horizontalPadding,
            columnSpacing: columnSpacing
        )
    }

    private var horizontalPadding: CGFloat {
        isRegularWidth ? 20 : 14
    }

    /// No `notBefore`: this board has no Overdue rail, so it keeps its full leading buffer and
    /// stays scrollable into the past. The floor is the macOS board's, where the rails cover it.
    private var activeWindowStartDate: Date {
        windowStartDate ?? CalendarBoardPlannerSupport.plannerWindowStart(for: anchorDate, calendar: calendar)
    }

    /// The column the board should be showing at its leading edge, in the window as it currently
    /// stands. Re-read every pass, so the one-shot assertion uses the anchor at first layout.
    private var anchorDayIndex: Int {
        CalendarBoardPlannerSupport.dayIndex(
            for: anchorDate,
            bufferStart: activeWindowStartDate,
            calendar: calendar,
            renderDays: renderDays
        )
    }

    /// Folds due-only work into its due day. Without an Unscheduled rail these day columns are the
    /// only place a card can appear, so bucketing strictly on the do date would hide it entirely.
    private var boardTasksByDate: [String: [AppTask]] {
        CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates(from: allTasks)
    }

    var body: some View {
        GeometryReader { geometry in
            board(columnWidth: columnWidth(containerWidth: geometry.size.width))
        }
    }

    private func board(columnWidth: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: columnSpacing) {
                ForEach(0..<renderDays, id: \.self) { dayIndex in
                    let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
                    let dateKey = DateFormatters.dateKey(from: date)
                    iOSCalendarBoardDayColumn(
                        date: date,
                        dateKey: dateKey,
                        tasks: boardTasksByDate[dateKey] ?? [],
                        bundles: bundlesByDate[dateKey] ?? [],
                        events: eventsByDate[dateKey] ?? [],
                        allTasks: allTasks,
                        allBundles: allBundles,
                        onAddTask: { onAddItem(dateKey) },
                        onDropTaskOnDay: { task in schedule(task, on: dateKey) },
                        onDropBundleOnDay: { bundle in move(bundle, on: dateKey) },
                        onDropTaskOnBundle: { task, bundle in add(task, to: bundle) }
                    )
                    .frame(width: columnWidth)
                    .id(dayIndex)
                }
            }
            // Directly on the lazy stack, so both the paging targets and the ids
            // `scrollPosition` resolves are the day columns themselves.
            .scrollTargetLayout()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .horizontal)
        // Compact pages a whole column at a time, so a day is never left half on screen with its
        // cards clipped mid-word. iPad scrolls freely across its multi-column board.
        .modifier(iOSBoardColumnPaging(isEnabled: !isRegularWidth))
        .scrollPosition(id: $scrolledDayIndex, anchor: .leading)
        .cadenceLazyScrollAnchor($scrolledDayIndex, target: anchorDayIndex, axis: .horizontal)
        .background(Theme.bg)
        .onAppear {
            alignWindow(to: anchorDate)
        }
        .onChange(of: anchorDate) { _, newDate in
            if isUpdatingSelectedDateFromScroll {
                isUpdatingSelectedDateFromScroll = false
                return
            }
            alignWindow(to: newDate, animated: true)
        }
        .onChange(of: scrolledDayIndex) { _, dayIndex in
            guard let dayIndex else { return }
            // `cadenceLazyScrollAnchor` above is only the *assertion* half of the rule; this is the
            // other half, and this board was taking one without the other. An unresolved report
            // reads as column 0 — `plannerLeadingDayCount` days behind the anchor — and
            // `adoptVisibleDay` writes `anchorDate`, which the Calendar page persists. So a report
            // still in flight from before the placement could save a day the user never chose and
            // have it survive relaunch. That is `ecaf80f` exactly, and worse for being written down.
            //
            // Not a fourth hand-rolled gate: `CadenceLazyScrollAnchor.report` is generic over the
            // position, and an `Int` column index is the shape the timed grid already passes it.
            switch CadenceLazyScrollAnchor.report(
                dayIndex,
                target: anchorDayIndex,
                hasConfirmedPlacement: didConfirmInitialColumn
            ) {
            case .ignore:
                return
            case .confirmsPlacement:
                didConfirmInitialColumn = true
            case .adopt:
                adoptVisibleDay(dayIndex)
            }
        }
    }

    /// Rebuilds the rendered window around `date` and puts that day at the leading edge.
    ///
    /// Setting `scrolledDayIndex` is both the request and, once SwiftUI honours it, the report — so
    /// the no-op guard matters: re-assigning the index the board is already on would otherwise
    /// bounce back through `adoptVisibleDay` on every anchor change.
    private func alignWindow(to date: Date, animated: Bool = false) {
        let startDate = CalendarBoardPlannerSupport.plannerWindowStart(for: date, calendar: calendar)
        let target = CalendarBoardPlannerSupport.dayIndex(
            for: date,
            bufferStart: startDate,
            calendar: calendar,
            renderDays: renderDays
        )
        windowStartDate = startDate
        guard scrolledDayIndex != target else { return }
        if animated {
            withAnimation(.snappy(duration: 0.22)) { scrolledDayIndex = target }
        } else {
            scrolledDayIndex = target
        }
    }

    private func recenterWindowIfNeeded(visibleDayIndex dayIndex: Int, visibleDate: Date) {
        guard let startDate = CalendarBoardPlannerSupport.recenteredWindowStart(
            visibleDayIndex: dayIndex,
            visibleDate: visibleDate,
            currentWindowStart: activeWindowStartDate,
            renderDays: renderDays,
            calendar: calendar
        ) else { return }

        let recenteredDayIndex = CalendarBoardPlannerSupport.dayIndex(
            for: visibleDate,
            bufferStart: startDate,
            calendar: calendar,
            renderDays: renderDays
        )

        windowStartDate = startDate
        scrolledDayIndex = recenteredDayIndex
    }

    private func adoptVisibleDay(_ dayIndex: Int) {
        let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
        if !calendar.isDate(date, inSameDayAs: selectedDate) {
            selectedDate = date
        }
        if !calendar.isDate(date, inSameDayAs: anchorDate) {
            isUpdatingSelectedDateFromScroll = true
            anchorDate = date
        }
        recenterWindowIfNeeded(visibleDayIndex: dayIndex, visibleDate: date)
    }

    private func schedule(_ task: AppTask, on dateKey: String) {
        CadenceTaskMutationSupport.moveTaskToDate(task, dateKey: dateKey, modelContext: modelContext)
    }

    private func move(_ bundle: TaskBundle, on dateKey: String) {
        CadenceTaskMutationSupport.moveBundle(bundle, to: dateKey, modelContext: modelContext)
    }

    private func add(_ task: AppTask, to bundle: TaskBundle) {
        CadenceTaskMutationSupport.addTask(task, to: bundle, modelContext: modelContext)
    }
}

/// `.scrollTargetBehavior` has no erased form, so the compact/regular choice needs a modifier
/// rather than a ternary at the call site.
private struct iOSBoardColumnPaging: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.scrollTargetBehavior(.viewAligned)
        } else {
            content
        }
    }
}

private struct iOSCalendarBoardDayColumn: View {
    let date: Date
    let dateKey: String
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let events: [EKEvent]
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
        let eventItems = iOSCalendarBoardEventItem.items(from: events, for: date).map { iOSCalendarBoardColumnItem.event($0) }
        let bundleItems = bundles.map { iOSCalendarBoardColumnItem.bundle($0) }
        let taskItems = activeTasks.map { iOSCalendarBoardColumnItem.task($0) }
        return (eventItems + bundleItems + taskItems).sorted(by: sortColumnItems)
    }

    private var totalCount: Int {
        activeItems.count + completedTasks.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
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
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.72), style: StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                    .padding(2)
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items)
        } isTargeted: { isDropTargeted = $0 }
    }

    /// The same header treatment every board column gets, day columns included: dot, uppercased
    /// label, count, closing hairline — amber for today, which is the one sanctioned exception, the
    /// same one macOS's `BoardColumnHeader` makes.
    ///
    /// This replaced three overlapping affordances that all said "today": a "Today" pill, an
    /// amber-tinted count badge, and a separate glowing gradient capsule under the header.
    private var header: some View {
        iOSBoardColumnHeader(
            dotColor: isToday ? Theme.amber : Theme.dim,
            title: "\(DateFormatters.dayOfWeek.string(from: date)) · \(DateFormatters.shortDate.string(from: date))",
            count: totalCount,
            accentRule: isToday ? Theme.amber : nil
        )
    }

    private var addTaskButton: some View {
        iOSCalendarAddItemRow(
            accessibilityLabel: "Add task on \(DateFormatters.longDate.string(from: date))",
            action: onAddTask
        )
    }

    @ViewBuilder
    private var content: some View {
        if activeItems.isEmpty {
            // One line, next to the ghost add row that is already there. The day inspector's
            // version of this — icon tile, heading, a three-line explanation of what a planned
            // task, a time block and an Apple Calendar event are, and a button repeating the ghost
            // row — took roughly 40% of the phone screen to report that a day is empty.
            if completedTasks.isEmpty {
                iOSInlineEmpty(text: "Nothing scheduled")
            }
        } else {
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
                    .frame(height: 44)
                    .background(Theme.surfaceElevated.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                }
                .buttonStyle(.iosPressable)

                if !isCompletedCollapsed {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(completedTasks.sorted { lhs, rhs in
                            CalendarBoardPlannerSupport.boardTaskSort(lhs, rhs)
                        }) { task in
                            iOSBoardTaskCard(task: task)
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
        case .event(let item):
            iOSCalendarBoardEventCard(item: item)
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
            iOSBoardTaskCard(task: task)
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
}

#endif
