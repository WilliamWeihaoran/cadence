#if os(macOS)
import EventKit
import SwiftUI

struct CalendarPageBoardView: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let allTasks: [AppTask]
    let tasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]

    @Environment(CalendarManager.self) private var calendarManager

    private var selectedKey: String { DateFormatters.dateKey(from: selectedDate) }

    private var boardSummaries: [String: CadenceCalendarBoardDaySummary] {
        let _ = calendarManager.storeVersion
        return CadenceCalendarBoardSupport.monthSummaries(
            monthDate: monthDate,
            tasksByDate: tasksByDate,
            bundlesByDate: bundlesByDate
        ) { date, _ in
            calendarEvents(for: date).map(calendarEventMarker)
        }
    }

    private var selectedTasks: [AppTask] {
        CadenceScheduleSupport.calendarDayTasks(on: selectedKey, from: allTasks)
    }

    private var selectedBundles: [TaskBundle] {
        CadenceScheduleSupport.items(on: selectedKey, in: bundlesByDate)
    }

    private var selectedEvents: [EKEvent] {
        calendarEvents(for: selectedDate)
    }

    var body: some View {
        HStack(spacing: 0) {
            CalendarBoardMonthView(
                monthDate: monthDate,
                selectedDate: $selectedDate,
                summariesByDate: boardSummaries,
                horizontalPadding: 24,
                weekdayTopPadding: 16,
                weekdayBottomPadding: 12,
                cellSpacing: 12,
                minCellHeight: 82,
                surfaceFill: Theme.surfaceElevated.opacity(0.28),
                backgroundFill: Theme.bg
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Theme.borderSubtle.opacity(CalendarVisualStyle.dividerOpacity))

            CalendarBoardDayInspector(
                date: selectedDate,
                tasks: selectedTasks,
                bundles: selectedBundles,
                events: selectedEvents
            )
            .frame(width: 360)
        }
        .background(Theme.bg)
    }

    private func calendarEvents(for date: Date) -> [EKEvent] {
        guard calendarManager.isAuthorized else { return [] }
        let allDay = calendarManager.fetchAllDayEvents(for: date)
        let timed = calendarManager.fetchEvents(for: date)
        return (allDay + timed).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
            return (lhs.startDate ?? .distantPast) < (rhs.startDate ?? .distantPast)
        }
    }

    private func calendarEventMarker(_ event: EKEvent) -> CadenceCalendarBoardMarker {
        CadenceCalendarBoardMarker(
            id: event.calendarItemIdentifier,
            kind: .event,
            color: Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1)),
            isCompleted: false,
            count: 1
        )
    }
}

private struct CalendarBoardDayInspector: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let events: [EKEvent]

    private var totalCount: Int {
        tasks.count + bundles.count + events.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DateFormatters.longDate.string(from: date).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.dim)
                    Text("Schedule")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                }

                Spacer()

                Text("\(totalCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.blue.opacity(0.14)))
            }
            .padding(22)

            Divider().background(Theme.borderSubtle.opacity(CalendarVisualStyle.dividerOpacity))

            if totalCount == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                    Text("Nothing scheduled")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Tasks and calendar events will show here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !events.isEmpty {
                            CalendarBoardInspectorSection(title: "Events", tint: Theme.purple) {
                                ForEach(events, id: \.calendarItemIdentifier) { event in
                                    CalendarBoardEventRow(event: event)
                                }
                            }
                        }

                        if !bundles.isEmpty {
                            CalendarBoardInspectorSection(title: "Bundles", tint: Theme.amber) {
                                ForEach(bundles) { bundle in
                                    CalendarBoardBundleRow(bundle: bundle)
                                }
                            }
                        }

                        if !tasks.isEmpty {
                            CalendarBoardInspectorSection(title: "Tasks", tint: Theme.blue) {
                                ForEach(tasks) { task in
                                    CalendarBoardTaskRow(task: task)
                                }
                            }
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Theme.surface)
    }
}

private struct CalendarBoardInspectorSection<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)

            VStack(spacing: 8) {
                content
            }
        }
    }
}

private struct CalendarBoardTaskRow: View {
    let task: AppTask
    @State private var showInspector = false

    var body: some View {
        Button { showInspector = true } label: {
            CalendarBoardInspectorRowShell(
                title: task.title.isEmpty ? "Untitled Task" : task.title,
                subtitle: taskSubtitle,
                tint: Color(hex: task.containerColor),
                systemImage: task.isDone ? "checkmark.circle.fill" : "circle"
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showInspector, arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
    }

    private var taskSubtitle: String {
        if task.scheduledStartMin >= 0 {
            return CadenceScheduleSupport.timeRangeLabel(
                startMinute: task.scheduledStartMin,
                endMinute: task.scheduledEndMin
            )
        }
        if !task.dueDate.isEmpty {
            return "Due"
        }
        return task.containerName.isEmpty ? "Task" : task.containerName
    }
}

private struct CalendarBoardBundleRow: View {
    let bundle: TaskBundle

    var body: some View {
        CalendarBoardInspectorRowShell(
            title: bundle.displayTitle,
            subtitle: CadenceScheduleSupport.timeRangeLabel(startMinute: bundle.startMin, endMinute: bundle.endMin),
            tint: Theme.amber,
            systemImage: "tray.full.fill"
        )
    }
}

private struct CalendarBoardEventRow: View {
    let event: EKEvent

    private var tint: Color {
        Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1))
    }

    var body: some View {
        CalendarBoardInspectorRowShell(
            title: event.title ?? "Untitled Event",
            subtitle: subtitle,
            tint: tint,
            systemImage: event.isAllDay ? "calendar" : "clock"
        )
    }

    private var subtitle: String {
        if event.isAllDay { return "All day" }
        guard let startDate = event.startDate, let endDate = event.endDate else { return "Event" }
        let calendar = Calendar.current
        let start = calendar.component(.hour, from: startDate) * 60 + calendar.component(.minute, from: startDate)
        let end = calendar.component(.hour, from: endDate) * 60 + calendar.component(.minute, from: endDate)
        return CadenceScheduleSupport.timeRangeLabel(startMinute: start, endMinute: max(start + 5, end))
    }
}

private struct CalendarBoardInspectorRowShell: View {
    let title: String
    let subtitle: String
    let tint: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(0.64))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        }
    }
}
#endif
