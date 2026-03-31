#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import EventKit

let calBaseHourHeight: CGFloat = 60
let calStartHour = 0
let calEndHour = 24
let calTimeWidth: CGFloat = 44
let calTimeInset: CGFloat = 10
let calTimeTotalWidth: CGFloat = 54
let calDayHeaderHeight: CGFloat = 52
let calRenderDays = 3650

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
#endif
