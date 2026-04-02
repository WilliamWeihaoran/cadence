#if os(macOS)
import SwiftUI
import SwiftData
import EventKit
import Foundation

private func agentDebugLogMonthGrid(runId: String, hypothesisId: String, location: String, message: String, data: [String: Any]) {
    func sanitize(_ value: Any) -> Any {
        switch value {
        case let v as CGFloat: return Double(v)
        case let v as Float: return Double(v)
        case let v as Int: return v
        case let v as Double: return v
        case let v as Bool: return v
        case let v as String: return v
        case let v as [String: Any]:
            return v.mapValues { sanitize($0) }
        case let v as [Any]:
            return v.map { sanitize($0) }
        default:
            return String(describing: value)
        }
    }
    var payload: [String: Any] = [
        "sessionId": "2fa876",
        "runId": runId,
        "hypothesisId": hypothesisId,
        "location": location,
        "message": message,
        "data": sanitize(data),
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    if payload["id"] == nil {
        payload["id"] = "log_\(UUID().uuidString)"
    }
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          let url = URL(string: "http://127.0.0.1:7275/ingest/924ba59d-9d09-412e-a58b-19119790b9ed") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2fa876", forHTTPHeaderField: "X-Debug-Session-Id")
    request.httpBody = json
    URLSession.shared.dataTask(with: request).resume()
}

private func monthStart(for date: Date, calendar: Calendar) -> Date {
    let comps = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: comps) ?? date
}

private func monthIndex(for date: Date, currentMonthStart: Date, todayMonthIdx: Int, calendar: Calendar) -> Int {
    let targetMonthStart = monthStart(for: date, calendar: calendar)
    let delta = calendar.dateComponents([.month], from: currentMonthStart, to: targetMonthStart).month ?? 0
    return min(max(todayMonthIdx + delta, 0), 119)
}

private func monthIndexForOffset(y: CGFloat, offsets: [CGFloat], totalMonths: Int) -> Int {
    var lo = 0
    var hi = max(totalMonths - 1, 0)
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if offsets[mid] <= y { lo = mid } else { hi = mid - 1 }
    }
    return lo
}

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
    let scrollToTodayTrigger: Bool

    private let totalMonths = 120
    private let todayMonthIdx = 60
    private let cellHeight: CGFloat = 130
    private let cal = Calendar.current
    @State private var didInitialPosition = false

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
        // This must match MonthWeeksView.weeks. We render the last week's "spillover"
        // days (next month) in the current month, then skip the first partial week
        // in the next month to avoid duplicated rows at month boundaries.
        let skipCount = startWeekday == 0 ? 0 : (7 - startWeekday)
        let remaining = max(0, range.count - skipCount)
        return max(1, (remaining + 6) / 7)
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
                    guard didInitialPosition else { return }
                    let offsetBasedIdx = monthIndexForOffset(y: y, offsets: offsets, totalMonths: totalMonths)
                    let midpointY = y + (2 * cellHeight)
                    let midIdx = monthIndexForOffset(y: midpointY, offsets: offsets, totalMonths: totalMonths)
                    let month = cal.date(byAdding: .month, value: midIdx - todayMonthIdx, to: currentMonthStart) ?? currentMonthStart
                    let dateFromMidpoint = cal.date(byAdding: .day, value: 14, to: month) ?? month
                    let computedFromDate = monthIndex(for: dateFromMidpoint, currentMonthStart: currentMonthStart, todayMonthIdx: todayMonthIdx, calendar: cal)
                    // #region agent log
                    agentDebugLogMonthGrid(
                        runId: "month-drift",
                        hypothesisId: "H2",
                        location: "CalendarPageComponents.swift:MonthGridView.onScrollGeometryChange",
                        message: "Computed visible month from scroll offset",
                        data: [
                            "y": y,
                            "offsetBasedIdx": offsetBasedIdx,
                            "midpointY": midpointY,
                            "midIdx": midIdx,
                            "dateDerivedIdx": computedFromDate,
                            "previousVisibleMonthIdx": visibleMonthIdx,
                            "didInitialPosition": didInitialPosition
                        ]
                    )
                    // #endregion
                    if visibleMonthIdx != computedFromDate { visibleMonthIdx = computedFromDate }
                }
                .onAppear {
                    // #region agent log
                    agentDebugLogMonthGrid(
                        runId: "month-drift",
                        hypothesisId: "H1",
                        location: "CalendarPageComponents.swift:MonthGridView.onAppear",
                        message: "Month grid appeared and set baseline month index",
                        data: [
                            "todayMonthIdx": todayMonthIdx,
                            "visibleMonthIdxBefore": visibleMonthIdx
                        ]
                    )
                    // #endregion
                    visibleMonthIdx = todayMonthIdx
                    DispatchQueue.main.async {
                        proxy.scrollTo("month_\(todayMonthIdx)", anchor: .top)
                        DispatchQueue.main.async {
                            didInitialPosition = true
                            // #region agent log
                            agentDebugLogMonthGrid(
                                runId: "month-drift",
                                hypothesisId: "H1",
                                location: "CalendarPageComponents.swift:MonthGridView.onAppear.async",
                                message: "Initial month positioning completed",
                                data: [
                                    "didInitialPosition": didInitialPosition,
                                    "visibleMonthIdxAfter": visibleMonthIdx
                                ]
                            )
                            // #endregion
                        }
                    }
                }
                .onChange(of: scrollToTodayTrigger) {
                    // #region agent log
                    agentDebugLogMonthGrid(
                        runId: "month-drift",
                        hypothesisId: "H4",
                        location: "CalendarPageComponents.swift:MonthGridView.onChange.scrollToTodayTrigger",
                        message: "Received Today trigger in month grid",
                        data: [
                            "visibleMonthIdxBefore": visibleMonthIdx,
                            "todayMonthIdx": todayMonthIdx
                        ]
                    )
                    // #endregion
                    visibleMonthIdx = todayMonthIdx
                    withAnimation {
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
        // "Merge" month boundaries:
        // - The previous month renders the next month's leading days in its last week.
        // - Therefore, this month skips its own first partial week so that row isn't duplicated.
        let skipCount = startWeekday == 0 ? 0 : (7 - startWeekday)
        if skipCount < daysInMonth {
            for i in skipCount..<daysInMonth {
                days.append(cal.date(byAdding: .day, value: i, to: first)!)
            }
        }
        // Fill trailing cells with next-month dates so the month ends on a full week
        // without causing overlap at the start of the next month.
        if days.count % 7 != 0 {
            let remainder = days.count % 7
            let needed = 7 - remainder
            for i in 0..<needed {
                days.append(cal.date(byAdding: .day, value: daysInMonth + i, to: first)!)
            }
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
            onCreateEvent: { title, startMin, endMin, calendarID, notes in
                calendarManager.createStandaloneEvent(title: title, startMin: startMin, durationMinutes: endMin - startMin, calendarID: calendarID, date: date, notes: notes)
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
