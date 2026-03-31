#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import EventKit

private let calBaseHourHeight: CGFloat = 60
private let calStartHour = 0
private let calEndHour = 24
private let calTimeWidth:  CGFloat = 44   // text frame width
private let calTimeInset:  CGFloat = 10   // trailing gap between labels and columns
private let calTimeTotalWidth: CGFloat = 54  // calTimeWidth + calTimeInset
private let calDayHeaderHeight: CGFloat = 52
private let calRenderDays = 3650   // ~10 years; LazyHStack only renders visible columns

enum CalViewMode: String, CaseIterable {
    case week      = "Week"
    case twoWeeks  = "2 Weeks"
    case month     = "Month"

    var daysCount: Int {
        switch self {
        case .week:      return 7
        case .twoWeeks:  return 14
        case .month:     return 1  // unused for timeline
        }
    }
}

struct CalendarPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [AppTask]

    @State private var viewMode: CalViewMode = .week
    @State private var scrollToTodayTrigger = false
    @AppStorage("calendarZoomLevel") private var zoomLevel: Int = 1
    @AppStorage("calendarRememberedTimelineHour") private var rememberedScrollHour: Int = -1
    @AppStorage("calendarRememberedTimelineDateKey") private var rememberedDateKey: String = ""
    @State private var hContentOffset: CGFloat = 0
    @State private var visibleMonthIdx: Int = 60  // index into MonthGridView's 120-month window
    @State private var isRestoringVerticalScroll = true
    @State private var isRestoringHorizontalScroll = true
    @State private var didRestoreTimelineScroll = false

    private let cal = Calendar.current
    private var bufferStart: Date {
        cal.date(byAdding: .day, value: -1825, to: cal.startOfDay(for: Date())) ?? Date()  // 5 years back
    }
    private var todayDayIdx: Int {
        cal.dateComponents([.day], from: bufferStart, to: cal.startOfDay(for: Date())).day ?? 1825
    }
    private var tasksByDate: [String: [AppTask]] {
        var dict: [String: [AppTask]] = [:]
        for task in allTasks where task.scheduledStartMin >= 0 && !task.isCancelled {
            dict[task.scheduledDate, default: []].append(task)
        }
        return dict
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("Calendar")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.dim)
                    Text("·")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.dim.opacity(0.5))
                    Text(calendarTitleLabel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .animation(.none, value: calendarTitleLabel)
                }
                Spacer()
                Button("Today") {
                    scrollToTodayTrigger.toggle()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(minWidth: 70, minHeight: 30)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(Theme.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                TimelineZoomControl(zoomLevel: $zoomLevel, range: 1...3)

                HStack(spacing: 2) {
                    ForEach(CalViewMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue) { viewMode = mode }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 11, weight: viewMode == mode ? .semibold : .regular))
                            .foregroundStyle(viewMode == mode ? Theme.blue : Theme.dim)
                            .frame(minWidth: 78, minHeight: 30)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .background(viewMode == mode ? Theme.blue.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            if viewMode == .month {
                MonthGridView(allTasks: allTasks, tasksByDate: tasksByDateForMonth, visibleMonthIdx: $visibleMonthIdx)
            } else {
                GeometryReader { geo in
                    let colWidth = max(80, (geo.size.width - calTimeTotalWidth) / CGFloat(viewMode.daysCount))
                    let timelineViewportWidth = max(0, geo.size.width - calTimeTotalWidth)
                    let totalDaysWidth = colWidth * CGFloat(calRenderDays)
                    let scrollViewportHeight = max(0, geo.size.height - calDayHeaderHeight - 1)
                    let targetHours: CGFloat = zoomLevel == 1 ? 12 : zoomLevel == 2 ? 8 : 4
                    let hourHeight = scrollViewportHeight / targetHours
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Theme.surface)
                                .frame(width: calTimeTotalWidth, height: calDayHeaderHeight)
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(Theme.borderSubtle.opacity(0.7)).frame(width: 1)
                                }
                            LazyHStack(spacing: 0) {
                                ForEach(0..<calRenderDays, id: \.self) { dayIdx in
                                    let date = cal.date(byAdding: .day, value: dayIdx, to: bufferStart)!
                                    CalDayHeaderView(date: date)
                                        .frame(width: colWidth)
                                }
                            }
                            .frame(width: totalDaysWidth, alignment: .leading)
                            .offset(x: hContentOffset)
                            .transaction { $0.animation = nil }
                            .frame(width: timelineViewportWidth, alignment: .leading)
                            .clipped()
                        }
                        .frame(height: calDayHeaderHeight)
                        .background(Theme.surface)

                        Divider().background(Theme.borderSubtle)

                        ScrollViewReader { vProxy in
                            ScrollView(.vertical) {
                                HStack(alignment: .top, spacing: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(calStartHour..<calEndHour, id: \.self) { hour in
                                            CalTimeRailLabel(hour: hour, hourHeight: hourHeight)
                                                .id("tl_\(hour)")
                                        }
                                    }
                                    .frame(width: calTimeTotalWidth)
                                    .background(Theme.surface)
                                    .overlay(alignment: .trailing) {
                                        Rectangle().fill(Theme.borderSubtle.opacity(0.7)).frame(width: 1)
                                    }

                                    ScrollViewReader { hProxy in
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            LazyHStack(alignment: .top, spacing: 0) {
                                                ForEach(0..<calRenderDays, id: \.self) { dayIdx in
                                                    let date = cal.date(byAdding: .day, value: dayIdx, to: bufferStart)!
                                                    let key = DateFormatters.dateKey(from: date)
                                                    CalDayColumn(
                                                        date: date,
                                                        tasks: tasksByDate[key] ?? [],
                                                        allTasks: allTasks,
                                                        colWidth: colWidth,
                                                        hourHeight: hourHeight
                                                    )
                                                    .frame(width: colWidth)
                                                    .id("day_\(dayIdx)")
                                                }
                                            }
                                            .frame(width: totalDaysWidth, alignment: .leading)
                                        }
                                        .frame(width: timelineViewportWidth, alignment: .leading)
                                        .scrollTargetBehavior(CalendarColumnSnap(colWidth: colWidth))
                                        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
                                        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                                            guard didRestoreTimelineScroll, !isRestoringHorizontalScroll else { return }
                                            hContentOffset = -x
                                            let rawDay = Int(round(x / max(colWidth, 1)))
                                            let clampedDay = min(max(rawDay, 0), calRenderDays - 1)
                                            let visibleDate = cal.date(byAdding: .day, value: clampedDay, to: bufferStart) ?? Date()
                                            rememberedDateKey = DateFormatters.dateKey(from: visibleDate)
                                        }
                                        .onAppear {
                                            restoreTimelineScrollIfNeeded(vProxy: vProxy, hProxy: hProxy)
                                        }
                                        .onChange(of: scrollToTodayTrigger) {
                                            rememberedDateKey = DateFormatters.todayKey()
                                            isRestoringHorizontalScroll = true
                                            hContentOffset = -CGFloat(todayDayIdx) * colWidth
                                            withAnimation {
                                                hProxy.scrollTo("day_\(todayDayIdx)", anchor: .leading)
                                            }
                                            DispatchQueue.main.async {
                                                isRestoringHorizontalScroll = false
                                            }
                                        }
                                    }
                                }
                            }
                            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                                guard didRestoreTimelineScroll, !isRestoringVerticalScroll else { return }
                                let rawHour = calStartHour + Int(y / max(hourHeight, 1))
                                rememberedScrollHour = min(max(rawHour, calStartHour), calEndHour - 1)
                            }
                            .onAppear {
                                didRestoreTimelineScroll = false
                                isRestoringVerticalScroll = true
                                isRestoringHorizontalScroll = true
                            }
                            .scrollBounceBehavior(.always, axes: [.vertical])
                            .onChange(of: scrollToTodayTrigger) {
                                let currentHour = Calendar.current.component(.hour, from: Date())
                                let scrollHour = max(calStartHour, currentHour - 1)
                                rememberedScrollHour = scrollHour
                                isRestoringVerticalScroll = true
                                withAnimation {
                                    vProxy.scrollTo("tl_\(scrollHour)", anchor: .top)
                                }
                                DispatchQueue.main.async {
                                    isRestoringVerticalScroll = false
                                }
                            }
                            .onChange(of: viewMode) { _, newMode in
                                if newMode != .month {
                                    didRestoreTimelineScroll = false
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
    }

    private var visibleMonthLabel: String {
        let currentMonthStart: Date = {
            var comps = cal.dateComponents([.year, .month], from: Date())
            comps.day = 1
            return cal.date(from: comps) ?? Date()
        }()
        let month = cal.date(byAdding: .month, value: visibleMonthIdx - 60, to: currentMonthStart) ?? Date()
        return DateFormatters.monthYear.string(from: month)
    }

    private var calendarTitleLabel: String {
        if viewMode == .month {
            return visibleMonthLabel
        }
        let visibleDate = DateFormatters.date(from: rememberedDateKey)
            ?? cal.date(byAdding: .day, value: rememberedTimelineDayIndex, to: bufferStart)
            ?? Date()
        return DateFormatters.monthYear.string(from: visibleDate)
    }

    private var rememberedTimelineDayIndex: Int {
        guard let rememberedDate = DateFormatters.date(from: rememberedDateKey) else { return todayDayIdx }
        let day = cal.dateComponents([.day], from: bufferStart, to: cal.startOfDay(for: rememberedDate)).day ?? todayDayIdx
        return min(max(day, 0), calRenderDays - 1)
    }

    private func restoreTimelineScrollIfNeeded(vProxy: ScrollViewProxy, hProxy: ScrollViewProxy) {
        guard !didRestoreTimelineScroll else { return }

        let currentHour = Calendar.current.component(.hour, from: Date())
        let fallbackHour = max(calStartHour, currentHour - 1)
        let scrollHour = rememberedScrollHour >= calStartHour ? rememberedScrollHour : fallbackHour
        let targetDay = rememberedTimelineDayIndex

        didRestoreTimelineScroll = true
        isRestoringHorizontalScroll = true
        isRestoringVerticalScroll = true

        DispatchQueue.main.async {
            hProxy.scrollTo("day_\(targetDay)", anchor: .leading)
            vProxy.scrollTo("tl_\(scrollHour)", anchor: .top)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isRestoringHorizontalScroll = false
                isRestoringVerticalScroll = false
            }
        }
    }

    // tasksByDate for month view — all tasks with a due date or scheduled date
    private var tasksByDateForMonth: [String: [AppTask]] {
        var dict: [String: [AppTask]] = [:]
        for task in allTasks where !task.isCancelled {
            if !task.scheduledDate.isEmpty {
                dict[task.scheduledDate, default: []].append(task)
            } else if !task.dueDate.isEmpty {
                dict[task.dueDate, default: []].append(task)
            }
        }
        return dict
    }

}

private struct CalTimeRailLabel: View {
    let hour: Int
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Theme.surface)
                .frame(height: hourHeight)

            Text(hourLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: calTimeWidth, alignment: .topTrailing)
                .padding(.trailing, calTimeInset)
                .padding(.top, 2)
        }
    }

    private var hourLabel: String { "\(hour)" }
}

// MARK: - Month Grid View (infinite vertical scroll)

private struct MonthGridView: View {
    let allTasks: [AppTask]
    let tasksByDate: [String: [AppTask]]
    @Binding var visibleMonthIdx: Int

    // 10-year window: 5 years back, 5 years forward
    private let totalMonths = 120
    private let todayMonthIdx = 60
    private let cellHeight: CGFloat = 130
    private let cal = Calendar.current

    private var currentMonthStart: Date {
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.day = 1
        return cal.date(from: comps) ?? Date()
    }

    /// Precomputed cumulative y-offsets for each month (weeks × cellHeight).
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
            // Fixed day-of-week header
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
                            let month = cal.date(
                                byAdding: .month, value: idx - todayMonthIdx,
                                to: currentMonthStart
                            )!
                            MonthWeeksView(
                                month: month,
                                tasksByDate: tasksByDate,
                                allTasks: allTasks
                            )
                            .id("month_\(idx)")
                        }
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                    // Binary search: find the last month whose cumulative offset ≤ scroll offset
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

// Renders just the week rows for one month
private struct MonthWeeksView: View {
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
                            MonthDayCell(
                                date: date,
                                tasks: tasksByDate[key] ?? [],
                                allTasks: allTasks,
                                displayMonth: month
                            )
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
        // Leading overflow: days from previous month
        for i in 0..<startWeekday {
            days.append(cal.date(byAdding: .day, value: i - startWeekday, to: first)!)
        }
        // Days of this month
        for i in 0..<daysInMonth {
            days.append(cal.date(byAdding: .day, value: i, to: first)!)
        }
        // Trailing filler: blank cells (nil) — next month's dates shown in next month only
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }
}

// MARK: - Month Day Cell

private struct MonthDayCell: View {
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
    private var dayNum: String { DateFormatters.dayNumber.string(from: date) }

    /// EKEvents for this date, minus any already tracked as Cadence tasks
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
    private var taskChips:  [AppTask]          { Array(tasks.prefix(5)) }
    private var eventChips: [CalendarEventItem] {
        Array(visibleEvents.prefix(max(0, 5 - taskChips.count)))
    }
    private var overflow: Int {
        tasks.count + visibleEvents.count - taskChips.count - eventChips.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Day number
            HStack {
                Text(dayNum)
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : (isCurrentMonth ? Theme.text : Theme.dim))
                    .frame(width: 24, height: 24)
                    .background(isToday ? Theme.blue : Color.clear)
                    .clipShape(Circle())
                Spacer()
            }
            .padding(.top, 6)
            .padding(.horizontal, 8)

            // Task + event chips
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

// MARK: - Day Header (sticky row)

private struct CalDayHeaderView: View {
    let date: Date
    private let cal = Calendar.current
    private var isToday: Bool { cal.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 2) {
            Text(dayOfWeek)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                .kerning(0.5)
            Text(dayNumber)
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

    private var dayOfWeek: String {
        DateFormatters.dayOfWeek.string(from: date).uppercased()
    }
    private var dayNumber: String {
        DateFormatters.dayNumber.string(from: date)
    }
}

// MARK: - Day Column (hour content only, no header)

private struct CalDayColumn: View {
    let date: Date
    let tasks: [AppTask]
    let allTasks: [AppTask]
    let colWidth: CGFloat
    let hourHeight: CGFloat
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager

    private let cal = Calendar.current
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
            metrics: TimelineMetrics(
                startHour: calStartHour,
                endHour: calEndHour,
                hourHeight: hourHeight
            ),
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

// MARK: - Column snapping

private struct CalendarColumnSnap: ScrollTargetBehavior {
    let colWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let x = target.rect.minX
        let col = (x / colWidth).rounded()
        target.rect.origin.x = col * colWidth
    }
}
#endif
