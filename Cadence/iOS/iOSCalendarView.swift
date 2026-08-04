#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarView: View {
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @AppStorage("ios.calendar.viewMode") private var viewModeRaw = CadenceCalendarViewMode.week.rawValue
    @AppStorage("ios.calendar.presentation") private var presentationRaw = CadenceCalendarPresentation.timeline.rawValue
    @AppStorage("ios.calendar.zoomLevel") private var zoomLevel = 1
    @AppStorage("ios.calendar.selectedDateKey") private var selectedDateKeyRaw = ""
    @AppStorage("ios.calendar.anchorDateKey") private var anchorDateKeyRaw = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var anchorDate = Calendar.current.startOfDay(for: Date())
    @State private var quickCreateSeed: iOSCalendarQuickCreateSeed?
    @State private var didRestorePersistedDates = false

    private let calendar = Calendar.current

    private var viewMode: CadenceCalendarViewMode {
        get { CadenceCalendarViewMode(rawValue: viewModeRaw) ?? .week }
        set { viewModeRaw = newValue.rawValue }
    }

    private var presentation: CadenceCalendarPresentation {
        get { CadenceCalendarPresentation(rawValue: presentationRaw) ?? .timeline }
        set { presentationRaw = newValue.rawValue }
    }

    private var navigationMode: CadenceCalendarViewMode {
        viewMode
    }

    private var selectedKey: String {
        DateFormatters.dateKey(from: selectedDate)
    }

    private var scheduledTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.tasksByScheduledDate(allTasks)
    }

    private var unscheduledTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.unscheduledTasksByDate(allTasks)
    }

    private var monthTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.monthTasksByDate(allTasks)
    }

    private var bundlesByDate: [String: [TaskBundle]] {
        CadenceScheduleSupport.bundlesByDate(allBundles)
    }

    private var visibleDates: [Date] {
        CadenceScheduleSupport.dates(containing: anchorDate, mode: viewMode, calendar: calendar)
    }

    private var selectedTasks: [AppTask] {
        CadenceScheduleSupport.calendarDayTasks(on: selectedKey, from: allTasks)
    }

    private var selectedBundles: [TaskBundle] {
        CadenceScheduleSupport.items(on: selectedKey, in: bundlesByDate)
    }

    private var selectedEvents: [EKEvent] {
        calendarManager.fetchEvents(for: selectedDate)
    }

    private var visibleEventsByDate: [String: [EKEvent]] {
        eventsByDate(for: calendarEventDates)
    }

    private var calendarEventDates: [Date] {
        if presentation == .board {
            return boardEventDates
        }
        if viewMode == .month {
            return CadenceScheduleSupport.monthGridDays(for: anchorDate, calendar: calendar)
        }
        return visibleDates
    }

    private var boardEventDates: [Date] {
        (0..<CalendarBoardPlannerSupport.visibleDayCount).map { offset in
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: anchorDate) ?? anchorDate)
        }
    }

    private var selectedUnscheduledTasks: [AppTask] {
        CadenceScheduleSupport.items(on: selectedKey, in: unscheduledTasksByDate)
    }

    private var selectedDueOnlyTasks: [AppTask] {
        CadenceScheduleSupport.dueOnlyTasks(on: selectedKey, from: allTasks)
    }

    private var selectedUniqueTaskCount: Int {
        Set((selectedTasks + selectedUnscheduledTasks + selectedDueOnlyTasks).map(\.id)).count
    }

    private var selectedTimedTaskCount: Int {
        selectedTasks.filter { $0.scheduledDate == selectedKey && $0.scheduledStartMin >= 0 }.count
    }

    private var selectedTotalCount: Int {
        selectedUniqueTaskCount + selectedBundles.count + selectedEvents.count
    }

    private var activePresentationLabel: String {
        if presentation == .board {
            return "Board"
        }
        return viewMode.rawValue
    }

    private var selectedLeadItem: iOSCalendarLeadItem? {
        if let bundle = selectedBundles.first {
            return iOSCalendarLeadItem(
                title: bundle.displayTitle,
                detail: CadenceScheduleSupport.timeRangeLabel(startMinute: bundle.startMin, endMinute: bundle.endMin),
                systemImage: "tray.full.fill",
                tint: Theme.amber
            )
        }
        if let event = selectedEvents.first {
            return iOSCalendarLeadItem(
                title: iOSCalendarEventSupport.title(for: event),
                detail: iOSCalendarEventSupport.timeRangeLabel(for: event),
                systemImage: event.isAllDay ? "calendar" : "calendar.badge.clock",
                tint: iOSCalendarEventSupport.color(for: event.calendar)
            )
        }
        if let task = (selectedTasks + selectedUnscheduledTasks + selectedDueOnlyTasks).first {
            return iOSCalendarLeadItem(
                title: task.title.isEmpty ? "Untitled Task" : task.title,
                detail: task.containerName.isEmpty ? "Inbox" : task.containerName,
                systemImage: task.isDone ? "checkmark.circle.fill" : "circle.fill",
                tint: Color(hex: task.containerColor)
            )
        }
        return nil
    }

    private var titleLabel: String {
        if presentation == .board {
            return CalendarBoardPlannerSupport.title(for: anchorDate, calendar: calendar)
        }
        return CadenceScheduleSupport.calendarTitle(for: anchorDate, mode: navigationMode, calendar: calendar)
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var compactCalendarHeight: CGFloat {
        if presentation == .board { return 520 }
        return presentation == .timeline && viewMode != .month ? 430 : 420
    }

    private var compactInspectorMinHeight: CGFloat {
        selectedTotalCount == 0 ? 260 : 320
    }

    var body: some View {
        VStack(spacing: 0) {
            iOSCalendarToolbar(
                title: titleLabel,
                viewMode: Binding(get: { viewMode }, set: setViewMode),
                presentation: Binding(get: { presentation }, set: setPresentation),
                zoomLevel: $zoomLevel,
                previous: { moveAnchor(by: -1) },
                next: { moveAnchor(by: 1) },
                today: jumpToToday
            )

            iOSCalendarContextStrip(
                selectedDate: selectedDate,
                presentationLabel: activePresentationLabel,
                totalCount: selectedTotalCount,
                timedCount: selectedTimedTaskCount,
                taskCount: selectedUniqueTaskCount,
                eventCount: selectedEvents.count,
                bundleCount: selectedBundles.count,
                leadItem: selectedLeadItem
            )

            Divider().background(Theme.borderSubtle)

            if isCompact {
                ScrollView {
                    VStack(spacing: 10) {
                        dayInspector
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: compactInspectorMinHeight)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                            .shadow(color: Theme.cardElevationShadow, radius: 12, x: 0, y: 5)

                        calendarContent
                            .frame(maxWidth: .infinity)
                            .frame(height: compactCalendarHeight)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                            .shadow(color: Theme.cardElevationShadow, radius: 12, x: 0, y: 5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 128)
                }
                .scrollIndicators(.hidden)
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        calendarContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.surface)

                        Divider().background(Theme.borderSubtle)

                        dayInspector
                            .frame(width: regularInspectorWidth(for: proxy.size.width), height: proxy.size.height)
                    }
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear(perform: restorePersistedCalendarDates)
        .onChange(of: selectedDate) { _, newDate in
            persistSelectedDate(newDate)
        }
        .onChange(of: anchorDate) { _, newDate in
            persistAnchorDate(newDate)
        }
        .sheet(item: $quickCreateSeed) { seed in
            iOSCalendarQuickCreateSheet(dateKey: seed.dateKey, initialStartMinute: seed.startMinute)
        }
    }

    private func regularInspectorWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.30, 340), 430)
    }

    @ViewBuilder
    private var calendarContent: some View {
        if presentation == .board {
            iOSCalendarBoardPlanner(
                anchorDate: $anchorDate,
                selectedDate: $selectedDate,
                allTasks: allTasks,
                allBundles: allBundles,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate,
                onAddItem: openQuickCreate
            )
        } else if viewMode == .month {
            iOSCalendarMonthGrid(
                monthDate: anchorDate,
                selectedDate: $selectedDate,
                monthTasksByDate: monthTasksByDate,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate
            )
        } else {
            iOSCalendarTimelineGrid(
                dates: visibleDates,
                selectedDate: $selectedDate,
                scheduledTasksByDate: scheduledTasksByDate,
                unscheduledTasksByDate: unscheduledTasksByDate,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate,
                zoomLevel: zoomLevel,
                onCreateAt: openQuickCreate
            )
        }
    }

    private var dayInspector: some View {
        iOSCalendarDayInspector(
            date: selectedDate,
            tasks: selectedTasks,
            bundles: selectedBundles,
            events: selectedEvents,
            unscheduledTasks: selectedUnscheduledTasks,
            dueOnlyTasks: selectedDueOnlyTasks
        ) {
            openQuickCreate(on: selectedKey)
        }
    }

    private func eventsByDate(for dates: [Date]) -> [String: [EKEvent]] {
        _ = calendarManager.storeVersion
        guard calendarManager.isAuthorized else { return [:] }
        var grouped: [String: [EKEvent]] = [:]
        for date in dates {
            let key = DateFormatters.dateKey(from: date)
            grouped[key] = calendarManager.fetchEvents(for: date)
        }
        return grouped
    }

    private func openQuickCreate(on dateKey: String) {
        quickCreateSeed = iOSCalendarQuickCreateSeed(dateKey: dateKey)
    }

    private func openQuickCreate(on dateKey: String, startMinute: Int) {
        if let date = DateFormatters.date(from: dateKey) {
            selectedDate = calendar.startOfDay(for: date)
        }
        quickCreateSeed = iOSCalendarQuickCreateSeed(dateKey: dateKey, startMinute: startMinute)
    }

    private func setViewMode(_ newMode: CadenceCalendarViewMode) {
        presentationRaw = CadenceCalendarPresentation.timeline.rawValue
        viewModeRaw = newMode.rawValue
        if newMode == .month {
            anchorDate = selectedDate
        } else if !visibleDates.contains(where: { calendar.isDate($0, inSameDayAs: selectedDate) }) {
            anchorDate = selectedDate
        }
    }

    private func setPresentation(_ newPresentation: CadenceCalendarPresentation) {
        presentationRaw = newPresentation.rawValue
        if newPresentation == .board {
            anchorDate = selectedDate
        }
    }

    private func moveAnchor(by value: Int) {
        if presentation == .board {
            anchorDate = CalendarBoardPlannerSupport.dateByMovingWindow(anchorDate, by: value, calendar: calendar)
            selectedDate = anchorDate
            return
        }

        anchorDate = CadenceScheduleSupport.shiftedDate(anchorDate, mode: navigationMode, by: value, calendar: calendar)
        if navigationMode == .month,
           let first = CadenceScheduleSupport.monthGridDays(for: anchorDate, calendar: calendar).first(where: {
               calendar.isDate($0, equalTo: anchorDate, toGranularity: .month)
           }) {
            selectedDate = first
        }
    }

    private func jumpToToday() {
        let today = calendar.startOfDay(for: Date())
        selectedDate = today
        anchorDate = today
    }

    private func restorePersistedCalendarDates() {
        guard !didRestorePersistedDates else { return }
        didRestorePersistedDates = true

        if let restoredSelectedDate = DateFormatters.date(from: selectedDateKeyRaw) {
            selectedDate = calendar.startOfDay(for: restoredSelectedDate)
        }

        if let restoredAnchorDate = DateFormatters.date(from: anchorDateKeyRaw) {
            anchorDate = calendar.startOfDay(for: restoredAnchorDate)
        } else {
            anchorDate = selectedDate
        }
    }

    private func persistSelectedDate(_ date: Date) {
        selectedDateKeyRaw = DateFormatters.dateKey(from: calendar.startOfDay(for: date))
    }

    private func persistAnchorDate(_ date: Date) {
        anchorDateKeyRaw = DateFormatters.dateKey(from: calendar.startOfDay(for: date))
    }
}

private struct iOSCalendarQuickCreateSeed: Identifiable {
    let dateKey: String
    var startMinute: Int? = nil
    var id: String {
        if let startMinute {
            return "\(dateKey)-\(startMinute)"
        }
        return dateKey
    }
}

#endif
