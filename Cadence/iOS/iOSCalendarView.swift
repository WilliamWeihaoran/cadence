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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var anchorDate = Calendar.current.startOfDay(for: Date())
    @State private var quickCreateSeed: iOSCalendarQuickCreateSeed?

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
        if presentation == .board { return 620 }
        return presentation == .timeline && viewMode != .month ? 620 : 470
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

            Divider().background(Theme.borderSubtle)

            if isCompact {
                ScrollView {
                    VStack(spacing: 0) {
                        calendarContent
                            .frame(maxWidth: .infinity)
                            .frame(height: compactCalendarHeight)

                        Divider().background(Theme.borderSubtle)

                        dayInspector
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 390)
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                HStack(spacing: 0) {
                    calendarContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider().background(Theme.borderSubtle)

                    dayInspector
                        .frame(width: 360)
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $quickCreateSeed) { seed in
            iOSCalendarQuickCreateSheet(dateKey: seed.dateKey)
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
                zoomLevel: zoomLevel
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
}

private struct iOSCalendarQuickCreateSeed: Identifiable {
    let dateKey: String
    var id: String { dateKey }
}

private struct iOSCalendarToolbar: View {
    let title: String
    @Binding var viewMode: CadenceCalendarViewMode
    @Binding var presentation: CadenceCalendarPresentation
    @Binding var zoomLevel: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        titleBlock
                        Spacer(minLength: 10)
                        navigationControls
                    }

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            modePicker
                            zoomControls
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        titleBlock
                        Spacer(minLength: 10)
                        navigationControls
                    }

                    HStack(spacing: 12) {
                        modePicker
                            .frame(maxWidth: 420)
                        Spacer(minLength: 10)
                        zoomControls
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, horizontalSizeClass == .regular ? 12 : 10)
        .background(Theme.surface)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Calendar")
                .font(.system(size: horizontalSizeClass == .regular ? 10 : 9, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)
            Text(title)
                .font(.system(size: horizontalSizeClass == .regular ? 22 : 17, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: horizontalSizeClass == .regular ? 176 : 116, idealWidth: 210, maxWidth: 260, alignment: .leading)
        .layoutPriority(1)
    }

    private var modePicker: some View {
        Picker("", selection: calendarModeSelection) {
            ForEach(CadenceCalendarViewMode.pickerCases, id: \.self) { mode in
                Text(mode.rawValue).tag("mode:\(mode.rawValue)")
            }

            Text("Board").tag("presentation:\(CadenceCalendarPresentation.board.rawValue)")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(Theme.blue)
    }

    private var calendarModeSelection: Binding<String> {
        Binding(
            get: {
                presentation == .board
                    ? "presentation:\(CadenceCalendarPresentation.board.rawValue)"
                    : "mode:\(viewMode.rawValue)"
            },
            set: { selection in
                if selection == "presentation:\(CadenceCalendarPresentation.board.rawValue)" {
                    presentation = .board
                } else if selection.hasPrefix("mode:") {
                    let rawValue = String(selection.dropFirst("mode:".count))
                    if let mode = CadenceCalendarViewMode(rawValue: rawValue) {
                        presentation = .timeline
                        viewMode = mode
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var zoomControls: some View {
        if presentation == .timeline && viewMode != .month {
            HStack(spacing: 6) {
                iOSFeatureIconButton(systemImage: "minus") {
                    zoomLevel = max(1, zoomLevel - 1)
                }
                Text("\(zoomLevel)x")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(minWidth: 24)
                iOSFeatureIconButton(systemImage: "plus") {
                    zoomLevel = min(3, zoomLevel + 1)
                }
            }
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 6) {
            iOSFeatureIconButton(systemImage: "chevron.left", action: previous)
            iOSFeatureIconButton(systemImage: "location.fill", action: today)
            iOSFeatureIconButton(systemImage: "chevron.right", action: next)
        }
    }
}
#endif
