#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCalendarView: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @AppStorage("ios.calendar.viewMode") private var viewModeRaw = CadenceCalendarViewMode.week.rawValue
    @AppStorage("ios.calendar.presentation") private var presentationRaw = iOSCalendarPresentation.timeline.rawValue
    @AppStorage("ios.calendar.zoomLevel") private var zoomLevel = 1
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var anchorDate = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current

    private var viewMode: CadenceCalendarViewMode {
        get { CadenceCalendarViewMode(rawValue: viewModeRaw) ?? .week }
        set { viewModeRaw = newValue.rawValue }
    }

    private var presentation: iOSCalendarPresentation {
        get { iOSCalendarPresentation(rawValue: presentationRaw) ?? .timeline }
        set { presentationRaw = newValue.rawValue }
    }

    private var navigationMode: CadenceCalendarViewMode {
        presentation == .board ? .month : viewMode
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
        CadenceScheduleSupport.bundles(on: selectedKey, in: bundlesByDate)
    }

    private var selectedUnscheduledTasks: [AppTask] {
        CadenceScheduleSupport.unscheduledTasks(on: selectedKey, in: unscheduledTasksByDate)
    }

    private var selectedDueOnlyTasks: [AppTask] {
        CadenceScheduleSupport.dueOnlyTasks(on: selectedKey, from: allTasks)
    }

    private var titleLabel: String {
        CadenceScheduleSupport.calendarTitle(for: anchorDate, mode: navigationMode, calendar: calendar)
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var compactCalendarHeight: CGFloat {
        presentation == .timeline && viewMode != .month ? 620 : 470
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
    }

    @ViewBuilder
    private var calendarContent: some View {
        if presentation == .board {
            iOSCalendarBoardMonth(
                monthDate: anchorDate,
                selectedDate: $selectedDate,
                monthTasksByDate: monthTasksByDate,
                bundlesByDate: bundlesByDate
            )
        } else if viewMode == .month {
            iOSCalendarMonthGrid(
                monthDate: anchorDate,
                selectedDate: $selectedDate,
                monthTasksByDate: monthTasksByDate,
                bundlesByDate: bundlesByDate
            )
        } else {
            iOSCalendarTimelineGrid(
                dates: visibleDates,
                selectedDate: $selectedDate,
                scheduledTasksByDate: scheduledTasksByDate,
                unscheduledTasksByDate: unscheduledTasksByDate,
                bundlesByDate: bundlesByDate,
                zoomLevel: zoomLevel
            )
        }
    }

    private var dayInspector: some View {
        iOSCalendarDayInspector(
            date: selectedDate,
            tasks: selectedTasks,
            bundles: selectedBundles,
            unscheduledTasks: selectedUnscheduledTasks,
            dueOnlyTasks: selectedDueOnlyTasks
        )
    }

    private func setViewMode(_ newMode: CadenceCalendarViewMode) {
        presentationRaw = iOSCalendarPresentation.timeline.rawValue
        viewModeRaw = newMode.rawValue
        if newMode == .month {
            anchorDate = selectedDate
        } else if !visibleDates.contains(where: { calendar.isDate($0, inSameDayAs: selectedDate) }) {
            anchorDate = selectedDate
        }
    }

    private func setPresentation(_ newPresentation: iOSCalendarPresentation) {
        presentationRaw = newPresentation.rawValue
        if newPresentation == .board {
            anchorDate = selectedDate
        }
    }

    private func moveAnchor(by value: Int) {
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

private enum iOSCalendarPresentation: String, CaseIterable, Hashable {
    case timeline = "Timeline"
    case board = "Board"
}

private struct iOSCalendarToolbar: View {
    let title: String
    @Binding var viewMode: CadenceCalendarViewMode
    @Binding var presentation: iOSCalendarPresentation
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
                HStack(spacing: 10) {
                    titleBlock
                    Spacer(minLength: 8)
                    modePicker
                    zoomControls
                    navigationControls
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, horizontalSizeClass == .regular ? 14 : 10)
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
        HStack(spacing: 4) {
            ForEach(CadenceCalendarViewMode.allCases, id: \.self) { mode in
                Button {
                    presentation = .timeline
                    viewMode = mode
                } label: {
                    calendarModeLabel(
                        title: mode.rawValue,
                        isSelected: presentation == .timeline && viewMode == mode
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                presentation = .board
            } label: {
                calendarModeLabel(title: "Board", isSelected: presentation == .board)
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.35), lineWidth: 1)
        }
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

    private func calendarModeLabel(title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
            .frame(minWidth: 48, minHeight: 28)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.blue.opacity(0.11) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Theme.blue.opacity(0.28) : Color.clear, lineWidth: 1)
            }
    }
}
#endif
