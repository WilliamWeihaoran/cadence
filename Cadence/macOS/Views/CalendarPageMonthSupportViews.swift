#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct MonthDayCell: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let allTasks: [AppTask]
    let displayMonth: Date

    @Environment(CalendarManager.self) private var calendarManager

    private let cal = Calendar.current

    private var isToday: Bool { cal.isDateInToday(date) }
    private var isCurrentMonth: Bool {
        cal.component(.month, from: date) == cal.component(.month, from: displayMonth) &&
        cal.component(.year, from: date) == cal.component(.year, from: displayMonth)
    }

    private var calendarEvents: [CalendarEventItem] {
        let _ = calendarManager.storeVersion
        return calendarManager.fetchEvents(for: date)
            .map { CalendarEventItem(event: $0) }
    }

    private var visibleEvents: [CalendarEventItem] {
        guard calendarManager.isAuthorized else { return [] }
        return calendarEvents
    }

    private var bundleChips: [TaskBundle] { Array(bundles.prefix(5)) }
    private var taskChips: [AppTask] { Array(tasks.prefix(max(0, 5 - bundleChips.count))) }
    private var eventChips: [CalendarEventItem] {
        Array(visibleEvents.prefix(max(0, 5 - bundleChips.count - taskChips.count)))
    }
    private var overflow: Int {
        bundles.count + tasks.count + visibleEvents.count - bundleChips.count - taskChips.count - eventChips.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(DateFormatters.dayNumber.string(from: date))
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : (isCurrentMonth ? Theme.text : Theme.dim))
                    .frame(width: 24, height: 24)
                    .background(isToday ? Theme.blue : Color.clear)
                    .clipShape(Circle())
                Spacer()
            }
            .padding(.top, 6)
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(bundleChips) { bundle in
                    HStack(spacing: 3) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                        Text(bundle.title.isEmpty ? "Task Bundle" : bundle.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                                .fill(Theme.surfaceElevated)
                            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                                .fill(Theme.amber.opacity(0.14))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                            .stroke(.white.opacity(0.045), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                }
                ForEach(taskChips) { task in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(hex: task.containerColor))
                            .frame(width: 5, height: 5)
                        Text(task.title)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                                .fill(Theme.surfaceElevated)
                            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                                .fill(Color(hex: task.containerColor).opacity(task.isDone ? 0.06 : 0.12))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                            .stroke(.white.opacity(0.045), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                }
                ForEach(eventChips) { event in
                    Text(event.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            ZStack {
                            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                                .fill(Theme.surfaceElevated)
                            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                                .fill(event.calendarColor.opacity(0.34))
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                                .stroke(.white.opacity(0.06), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
                }
                if overflow > 0 {
                    Text("+ \(overflow) more")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 5)
                }
            }
            .padding(.horizontal, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(isToday ? Theme.blue.opacity(0.04) : Theme.bg)
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.columnGridOpacity))
                .frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.majorGridOpacity))
                .frame(height: 0.5)
        }
    }
}

struct CalDayHeaderView: View {
    let date: Date
    var allDayEvents: [EKEvent] = []
    var unscheduledTasks: [AppTask] = []

    private let cal = Calendar.current
    private var isToday: Bool { cal.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(DateFormatters.dayOfWeek.string(from: date).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                    .kerning(0.5)
                Text(DateFormatters.dayNumber.string(from: date))
                    .font(.system(size: 18, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : Theme.text)
                    .frame(width: 32, height: 32)
                    .background(isToday ? Theme.blue : Color.clear)
                    .clipShape(Circle())
            }
            .frame(height: calDayHeaderHeight)
            .frame(maxWidth: .infinity)
            .background(isToday ? Theme.blue.opacity(0.05) : Theme.surface)

            allDayBannerContent
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: calAllDayBannerHeight, alignment: .top)
                .background(isToday ? Theme.blue.opacity(0.03) : Theme.surface)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.columnGridOpacity))
                .frame(width: 0.5)
        }
    }

    private var allDayBannerContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(unscheduledTasks) { task in
                    AllDayTaskChip(task: task)
                }
                ForEach(allDayEvents, id: \.eventIdentifier) { event in
                    AllDayEventChip(event: event)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
}

struct AllDayTaskChip: View {
    let task: AppTask
    @State private var showInspector = false

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color(hex: task.containerColor))
                .frame(width: 5, height: 5)
            Text(task.title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .fill(Theme.surfaceElevated)
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .fill(Color(hex: task.containerColor).opacity(showInspector ? 0.18 : 0.12))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 4, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { showInspector = true }
        .popover(isPresented: $showInspector, arrowEdge: .bottom) {
            TaskDetailPopover(task: task)
        }
        .draggable(task.id.uuidString)
    }
}

struct AllDayEventChip: View {
    let event: EKEvent

    private var eventColor: Color {
        Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1))
    }

    var body: some View {
        Text(event.title ?? "Untitled")
            .font(.system(size: 10))
            .foregroundStyle(.white)
            .lineLimit(1)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .fill(Theme.surfaceElevated)
                RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                    .fill(eventColor.opacity(0.34))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CalendarVisualStyle.chipRadius)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
            .draggable("allDayEvent:\(event.eventIdentifier ?? "")")
    }
}

struct CalDayColumn: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let eventCache: CalendarEventDayCache
    let colWidth: CGFloat
    let hourHeight: CGFloat
    let showHalfHourMarks: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager

    private var dateKey: String {
        DateFormatters.dateKey(from: date)
    }

    private var externalEventItems: [CalendarEventItem] {
        return eventCache.timedEvents(for: date, calendarManager: calendarManager)
            .map { CalendarEventItem(event: $0) }
    }

    var body: some View {
        TimelineDayCanvas(
            date: date,
            dateKey: dateKey,
            tasks: tasks,
            bundles: bundles,
            allTasks: allTasks,
            allBundles: allBundles,
            areas: areas,
            projects: projects,
            metrics: TimelineMetrics(startHour: calStartHour, endHour: calEndHour, hourHeight: hourHeight),
            width: colWidth,
            style: .calendar,
            showCurrentTimeDot: true,
            showHalfHourMarks: showHalfHourMarks,
            dropBehavior: .perHour,
            onCreateTask: { title, startMin, endMin, containerSelection, sectionName, notes, subtaskTitles in
                SchedulingActions.createTask(
                    title: title,
                    dateKey: dateKey,
                    startMin: startMin,
                    endMin: endMin,
                    containerSelection: containerSelection,
                    sectionName: sectionName,
                    notes: notes,
                    subtaskTitles: subtaskTitles,
                    areas: areas,
                    projects: projects,
                    in: modelContext
                )
            },
            onCreateBundle: { title, startMin, endMin, selectedTasks in
                let bundle = SchedulingActions.createBundle(title: title, dateKey: dateKey, startMin: startMin, endMin: endMin, in: modelContext)
                selectedTasks.forEach { SchedulingActions.addTask($0, to: bundle) }
            },
            onDropTaskAtMinute: { task, startMin in
                SchedulingActions.dropTask(task, to: dateKey, startMin: startMin)
            },
            onDropBundleAtMinute: { bundle, startMin in
                SchedulingActions.dropBundle(bundle, to: dateKey, startMin: startMin)
            },
            onDropTaskOnBundle: { task, bundle in
                SchedulingActions.addTask(task, to: bundle)
            },
            externalEvents: externalEventItems,
            onCreateEvent: { title, startMin, endMin, calendarID, notes in
                calendarManager.createStandaloneEvent(title: title, startMin: startMin, durationMinutes: endMin - startMin, calendarID: calendarID, date: date, notes: notes)
            },
            prefersCalendarEventCreation: true,
            onDropAllDayEventAtMinute: { eventID, startMin in
                guard let event = calendarManager.event(withIdentifier: eventID) else { return }
                calendarManager.convertAllDayEventToTimed(event, startMin: startMin, dateKey: dateKey)
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.columnGridOpacity))
                .frame(width: 0.5)
        }
    }
}
#endif
