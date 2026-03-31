#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct CalTimeRailLabel: View {
    let hour: Int
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Theme.surface)
                .frame(height: hourHeight)

            Text("\(hour)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: calTimeWidth, alignment: .topTrailing)
                .padding(.trailing, calTimeInset)
                .padding(.top, 2)
        }
    }
}

struct MonthGridView: View {
    let allTasks: [AppTask]
    let tasksByDate: [String: [AppTask]]
    @Binding var visibleMonthIdx: Int

    private let totalMonths = 120
    private let todayMonthIdx = 60
    private let cellHeight: CGFloat = 130
    private let cal = Calendar.current

    private var currentMonthStart: Date {
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.day = 1
        return cal.date(from: comps) ?? Date()
    }

    private var cumulativeOffsets: [CGFloat] {
        var offsets: [CGFloat] = []
        var y: CGFloat = 0
        for i in 0..<totalMonths {
            offsets.append(y)
            let month = cal.date(byAdding: .month, value: i - todayMonthIdx, to: currentMonthStart)!
            y += CGFloat(weeksInMonth(month)) * cellHeight
        }
        return offsets
    }

    private func weeksInMonth(_ month: Date) -> Int {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: first) else { return 5 }
        let startWeekday = cal.component(.weekday, from: first) - 1
        let total = startWeekday + range.count
        return (total + 6) / 7
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            let offsets = cumulativeOffsets
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<totalMonths, id: \.self) { idx in
                            let month = cal.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart)!
                            MonthWeeksView(month: month, tasksByDate: tasksByDate, allTasks: allTasks)
                                .id("month_\(idx)")
                        }
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                    var lo = 0, hi = totalMonths - 1
                    while lo < hi {
                        let mid = (lo + hi + 1) / 2
                        if offsets[mid] <= y { lo = mid } else { hi = mid - 1 }
                    }
                    if visibleMonthIdx != lo { visibleMonthIdx = lo }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("month_\(todayMonthIdx)", anchor: .top)
                    }
                }
            }
        }
        .background(Theme.bg)
    }
}

struct MonthWeeksView: View {
    let month: Date
    let tasksByDate: [String: [AppTask]]
    let allTasks: [AppTask]

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            ForEach(weeks.indices, id: \.self) { weekIdx in
                HStack(spacing: 0) {
                    ForEach(weeks[weekIdx].indices, id: \.self) { dayIdx in
                        if let date = weeks[weekIdx][dayIdx] {
                            let key = DateFormatters.dateKey(from: date)
                            MonthDayCell(date: date, tasks: tasksByDate[key] ?? [], allTasks: allTasks, displayMonth: month)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 130)
                                .overlay(alignment: .topTrailing) {
                                    Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(width: 0.5)
                                }
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(height: 0.5)
                                }
                        }
                    }
                }
            }
        }
    }

    private var weeks: [[Date?]] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let startWeekday = cal.component(.weekday, from: first) - 1
        guard let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count else { return [] }
        var days: [Date?] = []
        for i in 0..<startWeekday {
            days.append(cal.date(byAdding: .day, value: i - startWeekday, to: first)!)
        }
        for i in 0..<daysInMonth {
            days.append(cal.date(byAdding: .day, value: i, to: first)!)
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }
}

struct MonthDayCell: View {
    let date: Date
    let tasks: [AppTask]
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
        let linkedIDs = Set(allTasks.compactMap { $0.calendarEventID.isEmpty ? nil : $0.calendarEventID })
        return calendarManager.fetchEvents(for: date)
            .filter { event in
                guard let id = event.eventIdentifier else { return true }
                return !linkedIDs.contains(id)
            }
            .map { CalendarEventItem(event: $0) }
    }

    private var visibleEvents: [CalendarEventItem] {
        guard calendarManager.isAuthorized else { return [] }
        return calendarEvents
    }

    private var taskChips: [AppTask] { Array(tasks.prefix(5)) }
    private var eventChips: [CalendarEventItem] {
        Array(visibleEvents.prefix(max(0, 5 - taskChips.count)))
    }
    private var overflow: Int {
        tasks.count + visibleEvents.count - taskChips.count - eventChips.count
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
                    .background(Color(hex: task.containerColor).opacity(task.isDone ? 0.08 : 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                ForEach(eventChips) { event in
                    Text(event.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(event.calendarColor.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
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
            Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.5)).frame(height: 0.5)
        }
    }
}

struct CalDayHeaderView: View {
    let date: Date
    private let cal = Calendar.current
    private var isToday: Bool { cal.isDateInToday(date) }

    var body: some View {
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
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.4)).frame(width: 0.5)
        }
    }
}

struct CalDayColumn: View {
    let date: Date
    let tasks: [AppTask]
    let allTasks: [AppTask]
    let colWidth: CGFloat
    let hourHeight: CGFloat
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager

    private var dateKey: String {
        DateFormatters.dateKey(from: date)
    }

    private var externalEventItems: [CalendarEventItem] {
        let _ = calendarManager.storeVersion
        let linkedIDs = Set(allTasks.compactMap { $0.calendarEventID.isEmpty ? nil : $0.calendarEventID })
        return calendarManager.fetchEvents(for: date)
            .filter { event in
                guard let id = event.eventIdentifier else { return true }
                return !linkedIDs.contains(id)
            }
            .map { CalendarEventItem(event: $0) }
    }

    var body: some View {
        TimelineDayCanvas(
            date: date,
            dateKey: dateKey,
            tasks: tasks,
            allTasks: allTasks,
            metrics: TimelineMetrics(startHour: calStartHour, endHour: calEndHour, hourHeight: hourHeight),
            width: colWidth,
            style: .calendar,
            showCurrentTimeDot: true,
            dropBehavior: .perHour,
            onCreateTask: { title, startMin, endMin in
                SchedulingActions.createTask(title: title, dateKey: dateKey, startMin: startMin, endMin: endMin, in: modelContext)
            },
            onDropTaskAtMinute: { task, startMin in
                SchedulingActions.dropTask(task, to: dateKey, startMin: startMin)
            },
            externalEvents: externalEventItems,
            onCreateEvent: { title, startMin, endMin, calendarID in
                calendarManager.createStandaloneEvent(title: title, startMin: startMin, durationMinutes: endMin - startMin, calendarID: calendarID, date: date)
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.4)).frame(width: 0.5)
        }
    }
}

struct CalendarColumnSnap: ScrollTargetBehavior {
    let colWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let x = target.rect.minX
        let col = (x / colWidth).rounded()
        target.rect.origin.x = col * colWidth
    }
}
#endif
