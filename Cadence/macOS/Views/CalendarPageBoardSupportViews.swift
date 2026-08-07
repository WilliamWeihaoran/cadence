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
        let tasksByDate = boardTasksByDate
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
                            tasks: tasksByDate[dateKey] ?? [],
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

#endif
