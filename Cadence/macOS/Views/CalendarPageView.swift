#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let calBaseHourHeight: CGFloat = 60
private let calStartHour = 0
private let calEndHour = 24
private let calTimeWidth:  CGFloat = 44   // text frame width
private let calTimeInset:  CGFloat = 10   // trailing gap between labels and columns
private let calTimeTotalWidth: CGFloat = 54  // calTimeWidth + calTimeInset
private let calDayHeaderHeight: CGFloat = 52
private let calRenderDays = 90

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
    @State private var zoomLevel: Int = 1
    @State private var hContentOffset: CGFloat = 0

    private var hourHeight: CGFloat {
        switch zoomLevel {
        case 1: return calBaseHourHeight        // 60 — full day visible
        case 2: return calBaseHourHeight * 1.6  // 96
        default: return calBaseHourHeight * 2.8 // 168
        }
    }

    private let cal = Calendar.current
    private var bufferStart: Date {
        cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date())) ?? Date()
    }
    private var todayDayIdx: Int {
        cal.dateComponents([.day], from: bufferStart, to: cal.startOfDay(for: Date())).day ?? 30
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
                Text("Calendar")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("Today") {
                    scrollToTodayTrigger.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                HStack(spacing: 4) {
                    Button { if zoomLevel > 1 { zoomLevel -= 1 } } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(zoomLevel > 1 ? Theme.dim : Theme.dim.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    Text("\(zoomLevel)×")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 22)
                    Button { if zoomLevel < 3 { zoomLevel += 1 } } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(zoomLevel < 3 ? Theme.dim : Theme.dim.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 2) {
                    ForEach(CalViewMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue) { viewMode = mode }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: viewMode == mode ? .semibold : .regular))
                            .foregroundStyle(viewMode == mode ? Theme.blue : Theme.dim)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
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
                MonthGridView(allTasks: allTasks, tasksByDate: tasksByDateForMonth)
            } else {
                GeometryReader { geo in
                    let colWidth = max(80, (geo.size.width - calTimeTotalWidth) / CGFloat(viewMode.daysCount))
                    let timelineViewportWidth = max(0, geo.size.width - calTimeTotalWidth)
                    let totalDaysWidth = colWidth * CGFloat(calRenderDays)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Theme.surface)
                                .frame(width: calTimeTotalWidth, height: calDayHeaderHeight)
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(Theme.borderSubtle.opacity(0.7)).frame(width: 1)
                                }
                            HStack(spacing: 0) {
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
                                        ScrollView(.horizontal, showsIndicators: true) {
                                            HStack(alignment: .top, spacing: 0) {
                                                ForEach(0..<calRenderDays, id: \.self) { dayIdx in
                                                    let date = cal.date(byAdding: .day, value: dayIdx, to: bufferStart)!
                                                    let key = dateKey(for: date)
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
                                        .onScrollGeometryChange(for: CGFloat.self) { scrollGeo in
                                            scrollGeo.contentOffset.x
                                        } action: { _, x in
                                            let nextOffset = -x
                                            if abs(hContentOffset - nextOffset) > 0.1 {
                                                hContentOffset = nextOffset
                                            }
                                        }
                                        .onAppear {
                                            DispatchQueue.main.async {
                                                hProxy.scrollTo("day_\(todayDayIdx)", anchor: .leading)
                                            }
                                        }
                                        .onChange(of: scrollToTodayTrigger) {
                                            withAnimation {
                                                hProxy.scrollTo("day_\(todayDayIdx)", anchor: .leading)
                                            }
                                        }
                                    }
                                }
                            }
                            .onAppear {
                                let currentHour = Calendar.current.component(.hour, from: Date())
                                let scrollHour = max(calStartHour, currentHour - 1)
                                DispatchQueue.main.async {
                                    vProxy.scrollTo("tl_\(scrollHour)", anchor: .top)
                                }
                            }
                            .onChange(of: scrollToTodayTrigger) {
                                let currentHour = Calendar.current.component(.hour, from: Date())
                                let scrollHour = max(calStartHour, currentHour - 1)
                                withAnimation {
                                    vProxy.scrollTo("tl_\(scrollHour)", anchor: .top)
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

    private func hourLabel(_ hour: Int) -> String {
        return "\(hour)"
    }

    private func dateKey(for date: Date) -> String {
        DateFormatters.dateKey(from: date)
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

// MARK: - Month Grid View

private struct MonthGridView: View {
    let allTasks: [AppTask]
    let tasksByDate: [String: [AppTask]]

    @State private var displayMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            // Month nav header
            HStack {
                Button("‹") { goMonth(-1) }
                    .buttonStyle(.plain)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.dim)
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("›") { goMonth(1) }
                    .buttonStyle(.plain)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            // Day of week headers
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

            // Calendar grid
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(weeks.indices, id: \.self) { weekIdx in
                        HStack(spacing: 0) {
                            ForEach(weeks[weekIdx], id: \.self) { date in
                                let key = dateKey(date)
                                MonthDayCell(
                                    date: date,
                                    tasks: tasksByDate[key] ?? [],
                                    allTasks: allTasks,
                                    displayMonth: displayMonth
                                )
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.bg)
    }

    private var monthTitle: String {
        DateFormatters.monthYear.string(from: displayMonth)
    }

    private func goMonth(_ delta: Int) {
        if let newDate = cal.date(byAdding: .month, value: delta, to: displayMonth) {
            displayMonth = newDate
        }
    }

    private var weeks: [[Date]] {
        guard let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: displayMonth)) else { return [] }
        let startWeekday = cal.component(.weekday, from: firstOfMonth) - 1  // 0=Sun
        guard let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count else { return [] }
        var allDays: [Date] = []
        for i in 0..<startWeekday {
            allDays.append(cal.date(byAdding: .day, value: i - startWeekday, to: firstOfMonth)!)
        }
        for i in 0..<daysInMonth {
            allDays.append(cal.date(byAdding: .day, value: i, to: firstOfMonth)!)
        }
        let lastDay = cal.date(byAdding: .day, value: daysInMonth - 1, to: firstOfMonth)!
        while allDays.count % 7 != 0 {
            allDays.append(cal.date(byAdding: .day, value: allDays.count - startWeekday - daysInMonth, to: lastDay)!)
        }
        return stride(from: 0, to: allDays.count, by: 7).map { Array(allDays[$0..<min($0 + 7, allDays.count)]) }
    }

    private func dateKey(_ date: Date) -> String {
        DateFormatters.dateKey(from: date)
    }
}

// MARK: - Month Day Cell

private struct MonthDayCell: View {
    let date: Date
    let tasks: [AppTask]
    let allTasks: [AppTask]
    let displayMonth: Date

    private let cal = Calendar.current

    private var isToday: Bool { cal.isDateInToday(date) }
    private var isCurrentMonth: Bool {
        cal.component(.month, from: date) == cal.component(.month, from: displayMonth) &&
        cal.component(.year, from: date) == cal.component(.year, from: displayMonth)
    }

    private var dayNum: String {
        DateFormatters.dayNumber.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Day number (top)
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

            // Task chips (up to 3)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(tasks.prefix(3))) { task in
                    Text(task.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: task.containerColor).opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if tasks.count > 3 {
                    Text("+ \(tasks.count - 3) more")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 5)
                }
            }
            .padding(.horizontal, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 90)
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

    private let cal = Calendar.current
    private var dateKey: String {
        DateFormatters.dateKey(from: date)
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
                let task = AppTask(title: title)
                task.scheduledDate = dateKey
                task.scheduledStartMin = startMin
                task.estimatedMinutes = max(5, endMin - startMin)
                modelContext.insert(task)
            },
            onDropTaskAtMinute: { task, startMin in
                task.scheduledDate = dateKey
                task.scheduledStartMin = startMin
                task.estimatedMinutes = max(task.estimatedMinutes, 60)
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.4)).frame(width: 0.5)
        }
    }
}
#endif
