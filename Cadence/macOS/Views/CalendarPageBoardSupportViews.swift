#if os(macOS)
import EventKit
import SwiftData
import SwiftUI

/// The Calendar Board: day columns that scroll horizontally, flanked by two pinned rails.
///
/// The rails are what the retired Planning page turned into. Overdue and Unscheduled were two of
/// its five buckets; the other three (Today / This Week / Later) *are* day columns here, so they
/// needed no equivalent. Everything else Planning did — its bucketing, its drag-to-reschedule, its
/// drag-back-to-unscheduled, its "N unscheduled · N overdue" summary — lives on this surface now.
struct CalendarPageBoardView: View {
    private static let columnWidth = calendarBoardDayColumnWidth
    private static let columnSpacing = calendarBoardColumnSpacing
    private static let horizontalPadding = calendarBoardHorizontalPadding

    let anchorDate: Date
    @Binding var selectedDate: Date
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let bundlesByDate: [String: [TaskBundle]]

    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    /// Latches a `selectedDate` write this view made itself, so the `anchorDate` change it comes
    /// back as does not re-run `resetWindowAndScroll` and re-scroll the board a second time.
    @State private var isEchoingSelectedDate = false
    @State private var isProgrammaticScroll = false
    @State private var windowStartDate: Date?

    private let calendar = Calendar.current

    private var renderDays: Int {
        CalendarBoardPlannerSupport.plannerRenderDayCount
    }

    /// Floored at today: this board's Overdue rail already shows every past-dated card, so a past
    /// day column would show the same card twice.
    private var activeWindowStartDate: Date {
        windowStartDate ?? CalendarBoardPlannerSupport.plannerWindowStart(
            for: anchorDate,
            notBefore: Date(),
            calendar: calendar
        )
    }

    private var boardTasksByDate: [String: [AppTask]] {
        CalendarBoardPlannerSupport.tasksByBoardDate(from: allTasks)
    }

    private var railTasks: [CalendarBoardRail: [AppTask]] {
        CalendarBoardPlannerSupport.railTasks(from: allTasks, todayKey: DateFormatters.todayKey())
    }

    var body: some View {
        let rails = railTasks

        VStack(spacing: 0) {
            summary(rails)

            HStack(spacing: 0) {
                rail(.overdue, tasks: rails[.overdue] ?? [])
                dayColumns
                rail(.unscheduled, tasks: rails[.unscheduled] ?? [])
            }
        }
        .background(Theme.bg)
    }

    /// The Planning page's "N unscheduled · N overdue" line, kept because it is the one thing the
    /// rails cannot say on their own: each header counts its own pile, this reads both at a glance.
    /// Indented to the toolbar's page padding, not the board's, so it lines up under "Calendar".
    private func summary(_ rails: [CalendarBoardRail: [AppTask]]) -> some View {
        Text(CalendarBoardPlannerSupport.railSummaryLine(rails))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CadenceDesktopMetrics.pageHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    private func rail(_ rail: CalendarBoardRail, tasks: [AppTask]) -> some View {
        // Only the Unscheduled rail takes drops or offers an add row; the Overdue rail gets `nil`
        // for both because a card cannot be dragged — or created — *into* being late.
        CalendarBoardRailColumn(
            rail: rail,
            tasks: tasks,
            add: addBehavior(for: .rail(rail)),
            onDrop: { items in rail == .unscheduled ? unschedule(items) : false }
        )
    }

    private var dayColumns: some View {
        let tasksByDate = boardTasksByDate
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(0..<renderDays, id: \.self) { dayIndex in
                        let date = CalendarBoardPlannerSupport.date(at: dayIndex, bufferStart: activeWindowStartDate, calendar: calendar)
                        let dateKey = DateFormatters.dateKey(from: date)
                        CalendarBoardDayColumn(
                            dayIndex: dayIndex,
                            date: date,
                            dateKey: dateKey,
                            tasks: tasksByDate[dateKey] ?? [],
                            bundles: bundlesByDate[dateKey] ?? [],
                            events: calendarDisplayItems(for: date),
                            allTasks: allTasks,
                            allBundles: allBundles,
                            areas: areas,
                            projects: projects,
                            add: addBehavior(for: .day(dateKey)),
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
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .horizontal)
            .frame(maxWidth: .infinity)
            .onScrollGeometryChange(for: Int.self) { geometry in
                visibleDayIndex(for: geometry.contentOffset.x)
            } action: { _, dayIndex in
                updateSelectedDate(for: dayIndex, proxy: proxy)
            }
            .onAppear {
                resetWindowAndScroll(proxy, to: anchorDate, animated: false)
            }
            .onChange(of: anchorDate) { _, newDate in
                if isEchoingSelectedDate {
                    isEchoingSelectedDate = false
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
        // A remembered anchor can point into the past (the timeline and month views browse
        // freely), but the board no longer renders past days — so clamp, and write the clamp back
        // so the toolbar title agrees with the column the board actually lands on. `selectedDate`
        // is the same state this view reads as `anchorDate`, so latch the write: unlatched it
        // returns as an anchor change and scrolls the board a second time, animated, on appear.
        let clampedDate = CalendarBoardPlannerSupport.clampedBoardDate(date, calendar: calendar)
        if !calendar.isDate(clampedDate, inSameDayAs: selectedDate) {
            isEchoingSelectedDate = true
            selectedDate = clampedDate
        }

        let startDate = CalendarBoardPlannerSupport.plannerWindowStart(
            for: clampedDate,
            notBefore: Date(),
            calendar: calendar
        )
        isProgrammaticScroll = true
        windowStartDate = startDate
        let target = CalendarBoardPlannerSupport.dayIndex(
            for: clampedDate,
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
        // The window rests against its leading edge here — today is column 0 — so proximity alone
        // would fire on nearly every column crossing in the first six weeks and yank the board
        // mid-scroll. Only recenter when the window would genuinely move.
        guard let startDate = CalendarBoardPlannerSupport.recenteredWindowStart(
            visibleDayIndex: dayIndex,
            visibleDate: visibleDate,
            currentWindowStart: activeWindowStartDate,
            renderDays: renderDays,
            notBefore: Date(),
            calendar: calendar
        ) else { return }

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
            isEchoingSelectedDate = true
            selectedDate = date
        }
        recenterWindowIfNeeded(proxy, visibleDayIndex: dayIndex, visibleDate: date)
    }

    /// A day column's "+" composes inline — the column supplies the do date, so the inline composer
    /// only has to ask for a name. The Unscheduled rail has no date to supply, so it opens the
    /// create sheet instead; that is what the Planning page's add row did before this board
    /// absorbed it.
    ///
    /// `insertInline` used to mean *insert*: it built an `AppTask` titled "New Task" and saved it,
    /// with no prompt at all, so a mis-click left an untitled card in the column. It now opens the
    /// composer over the same date, and creation runs through `TaskCreationService` like every
    /// other create path in the app.
    private func addBehavior(for target: CalendarBoardDropTarget) -> KanbanColumnAddBehavior? {
        switch CalendarBoardPlannerSupport.addAction(for: target) {
        case .none:
            return nil
        case .presentCreateSheet:
            return .presentSheet { taskCreationManager.present() }
        case .insertInline(let dateKey):
            // Whole-day columns: this board has no per-column time range, so the composer seeds no
            // timeline slot. `InlineTaskComposerSurface.day` carries one for a board that does.
            return .compose(.day(dateKey: dateKey, startMin: -1))
        }
    }

    /// The Unscheduled rail's drop. Clears the do date *and* the timeline slot together — an
    /// earlier version of this drag wrote only one of the two, which left the card bucketed
    /// exactly where it started and made the drop look like it had done nothing.
    private func unschedule(_ items: [String]) -> Bool {
        guard let action = CalendarBoardPlannerSupport.dropAction(for: .rail(.unscheduled)),
              let payload = items.first,
              let taskID = TaskDragPayload.taskID(from: payload),
              let task = allTasks.first(where: { $0.id == taskID }) else { return false }

        if task.bundle != nil {
            SchedulingActions.removeTaskFromBundle(task, keepOnBundleDate: false)
        }
        withAnimation(kanbanCardReorderAnimation) {
            CalendarBoardPlannerSupport.apply(action, to: task)
        }
        try? modelContext.save()
        return true
    }

    /// A day column's drop. Goes through the same `apply` the Unscheduled rail uses, so both
    /// directions of the drag write the one field the board buckets on.
    private func schedule(_ task: AppTask, on dateKey: String) {
        guard let action = CalendarBoardPlannerSupport.dropAction(for: .day(dateKey)) else { return }
        if task.bundle != nil {
            SchedulingActions.removeTaskFromBundle(task, keepOnBundleDate: false)
        }
        CalendarBoardPlannerSupport.apply(action, to: task)
        if task.estimatedMinutes <= 0 {
            task.estimatedMinutes = AppTask.defaultTimelineDurationMinutes
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

#endif
