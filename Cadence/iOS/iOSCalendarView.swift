#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarView: View {
    /// Set when this is the Calendar tab's root. A pushed Calendar keeps its back chevron; a tab
    /// root has nothing behind it, and a chevron there would be a control that looks tappable and
    /// does nothing.
    var isCompactTabRoot = false
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @AppStorage("ios.calendar.viewMode") private var viewModeRaw = CadenceCalendarViewMode.week.rawValue
    @AppStorage("ios.calendar.presentation") private var presentationRaw = CadenceCalendarPresentation.timeline.rawValue
    @AppStorage("ios.calendar.zoomLevel") private var zoomLevel = 1
    /// Month's Agenda/Day toggle. Written from a tap on that control and from nowhere else — never
    /// from `paneWidth`, the size class, or anything else the window decides. See
    /// `CadenceCalendarMonthLayout`.
    @AppStorage("ios.calendar.monthDetail") private var monthDetailRaw = CadenceCalendarMonthLayout.defaultDetail.rawValue
    @AppStorage("ios.calendar.selectedDateKey") private var selectedDateKeyRaw = ""
    @AppStorage("ios.calendar.anchorDateKey") private var anchorDateKeyRaw = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var anchorDate = Calendar.current.startOfDay(for: Date())
    @State private var quickCreateSeed: iOSCalendarQuickCreateSeed?
    @State private var didRestorePersistedDates = false
    /// The width of this page, which on iPad is the window less the shell sidebar. See
    /// `hasInspector`.
    @State private var paneWidth: CGFloat = 0

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
        CadenceScheduleSupport.tasksByScheduledDate(allTasks, includeCompleted: false)
    }

    private var unscheduledTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.unscheduledTasksByDate(allTasks)
    }

    private var monthTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.monthTasksByDate(allTasks)
    }

    private var bundlesByDate: [String: [TaskBundle]] {
        CadenceScheduleSupport.bundlesByDate(allBundles, includeCompleted: false)
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

    /// Whether this pane can carry the day inspector beside the calendar. See
    /// `CadenceCalendarPaneLayout`: an 11" iPad in portrait cannot, and used to give the inspector
    /// 340 of its 632 points anyway.
    ///
    /// `paneWidth` starts at 0, so the first frame resolves to `false` and the calendar takes the
    /// whole pane until the measurement lands. That is the right way round: a pane that opens
    /// full-width and gains an inspector reads as the inspector arriving, where the reverse reads as
    /// content being taken away.
    private var hasInspector: Bool {
        !isCompact
            && CadenceCalendarPaneLayout.showsInspector(
                paneWidth: paneWidth,
                calendarMinimumWidth: calendarMinimumWidth
            )
    }

    /// What has to fit beside the inspector before there is one.
    ///
    /// Week is the mode that can answer this with a real number: an hour rail and seven day
    /// columns, none of which can be dropped, at the width a column needs to label a block with
    /// something more than an ellipsis. Every other mode keeps the inspector's own width as the
    /// stand-in it always used — the Board's columns page, so a narrower board is a shorter page
    /// rather than a lost column, and Month's grid flexes.
    private var calendarMinimumWidth: CGFloat {
        guard presentation == .timeline, viewMode == .week else {
            return CadenceCalendarPaneLayout.inspectorMinWidth
        }
        return CadenceCalendarWeekGridLayout.fullSizeWidth(isRegularWidth: true)
    }

    private var isMonthTimeline: Bool {
        presentation == .timeline && viewMode == .month
    }

    /// What Month shows beside or under its grid. This used to be `!hasInspector` — the window
    /// deciding which of the two mechanisms you were using, so rotating an 11" iPad swapped the
    /// agenda for the day inspector and back. It is a stored choice now; the width only decides
    /// where that choice is drawn.
    private var monthDetail: CadenceCalendarMonthDetail {
        CadenceCalendarMonthLayout.detail(storedRawValue: monthDetailRaw, isCompact: isCompact)
    }

    /// Beside the grid where the inspector already fits, under it where it does not.
    private var monthPlacement: CadenceCalendarMonthLayout.Placement {
        isCompact ? .below : CadenceCalendarMonthLayout.placement(paneWidth: paneWidth)
    }

    /// Only Week keeps the counts line on a phone. The Board's columns are meant to start directly
    /// under the mode control, and Month's agenda below lists the selected day item by item — a
    /// line above it counting the same items is the chrome this page just finished removing.
    ///
    /// Month now decides for itself, because both of its readings head themselves with a date: the
    /// agenda per day, the inspector once. See
    /// `CadenceCalendarMonthLayout.showsDaySummaryStrip(placement:detail:)`.
    private var showsContextStrip: Bool {
        if isMonthTimeline {
            return CadenceCalendarMonthLayout.showsDaySummaryStrip(
                placement: monthPlacement,
                detail: monthDetail
            )
        }
        return !isCompact || presentation == .timeline
    }

    var body: some View {
        VStack(spacing: 0) {
            iOSCalendarToolbar(
                title: titleLabel,
                onBack: isCompact && !isCompactTabRoot ? { dismiss() } : nil,
                viewMode: Binding(get: { viewMode }, set: setViewMode),
                presentation: Binding(get: { presentation }, set: setPresentation),
                zoomLevel: $zoomLevel,
                monthDetail: Binding(get: { monthDetail }, set: setMonthDetail),
                showsMonthDetailControl: CadenceCalendarMonthLayout.showsDetailControl(
                    isCompact: isCompact,
                    presentation: presentation,
                    viewMode: viewMode
                ),
                previous: { moveAnchor(by: -1) },
                next: { moveAnchor(by: 1) },
                today: jumpToToday
            )

            if showsContextStrip {
                iOSCalendarContextStrip(
                    selectedDate: selectedDate,
                    timedCount: selectedTimedTaskCount,
                    taskCount: selectedUniqueTaskCount,
                    eventCount: selectedEvents.count,
                    bundleCount: selectedBundles.count,
                    leadItem: selectedLeadItem
                )
            }

            if isMonthTimeline {
                // Month splits itself: it has two possible details and two possible placements, and
                // the pane-wide `hasInspector` branch below can express neither.
                monthContent
            } else if hasInspector {
                HStack(spacing: 0) {
                    calendarContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.surface)

                    Divider().background(Theme.borderSubtle)

                    dayInspector
                        .frame(
                            width: CadenceCalendarPaneLayout.inspectorWidth(
                                forPaneWidth: paneWidth,
                                calendarMinimumWidth: calendarMinimumWidth
                            )
                        )
                        .frame(maxHeight: .infinity)
                }
            } else {
                // Every mode fills the pane once there is no inspector taking a third of it.
                calendarContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Measured, not wrapped. A `GeometryReader` around this `VStack` reads the same width, but
        // it also becomes the layout container, and this stack holds scroll views that size
        // themselves from what is left over. Reading the width into state leaves the stack laying
        // itself out exactly as it did before.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            paneWidth = newWidth
        }
        .background(Theme.bg.ignoresSafeArea())
        .iOSHidesCompactNavigationBar()
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

    /// Month: the grid, and the chosen reading of a day either beside it or under it.
    ///
    /// Beside, the grid is the full-size one whose 104pt cells chip what each day holds; under, it
    /// is the compact grid sized so that **every** week of the month is on screen with the detail
    /// still visible below it. Both were already here — what is new is that either detail can go in
    /// either place, instead of the pane width choosing one pairing and hiding the other.
    @ViewBuilder
    private var monthContent: some View {
        switch monthPlacement {
        case .beside:
            HStack(spacing: 0) {
                iOSCalendarMonthGrid(
                    monthDate: anchorDate,
                    selectedDate: $selectedDate,
                    monthTasksByDate: monthTasksByDate,
                    bundlesByDate: bundlesByDate,
                    eventsByDate: visibleEventsByDate
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().background(Theme.borderSubtle)

                monthDetailPane
                    .frame(width: CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: paneWidth))
                    .frame(maxHeight: .infinity)
            }

        case .below:
            iOSCalendarMonthStack(
                monthDate: anchorDate,
                selectedDate: $selectedDate,
                monthTasksByDate: monthTasksByDate,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate,
                detailMinimumHeight: CadenceCalendarMonthLayout.detailMinimumHeight(for: monthDetail)
            ) {
                monthDetailPane
            }
        }
    }

    @ViewBuilder
    private var monthDetailPane: some View {
        switch monthDetail {
        case .agenda:
            iOSCalendarMonthAgendaList(
                monthDate: anchorDate,
                selectedDate: $selectedDate,
                monthTasksByDate: monthTasksByDate,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate
            )
        case .day:
            dayInspector
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

    /// The **only** writer of `ios.calendar.monthDetail`. A persisted navigation value written from
    /// anything other than a tap compounds across launches (`ecaf80f`), so nothing derived from
    /// `paneWidth` or the size class ever reaches this.
    private func setMonthDetail(_ newDetail: CadenceCalendarMonthDetail) {
        monthDetailRaw = newDetail.rawValue
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
