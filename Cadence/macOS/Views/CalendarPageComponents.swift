#if os(macOS)
import SwiftUI
import SwiftData
import EventKit
import Foundation

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
        CalendarMonthGridSupport.currentMonthStart(calendar: cal)
    }

    private var cumulativeOffsets: [CGFloat] {
        CalendarMonthGridSupport.cumulativeOffsets(
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            cellHeight: cellHeight,
            calendar: cal
        )
    }

    private func weeksInMonth(_ month: Date) -> Int {
        CalendarMonthGridSupport.weeksInMonth(month, calendar: cal)
    }

    var body: some View {
        VStack(spacing: 0) {
            MonthGridWeekdayHeader()

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
                    CalendarMonthGridInteractionSupport.handleScroll(
                        y: y,
                        offsets: offsets,
                        totalMonths: totalMonths,
                        visibleMonthIdx: &visibleMonthIdx,
                        didInitialPosition: didInitialPosition
                    )
                }
                .onAppear {
                    CalendarMonthGridInteractionSupport.handleAppear(
                        proxy: proxy,
                        visibleMonthIdx: $visibleMonthIdx,
                        todayMonthIdx: todayMonthIdx,
                        setDidInitialPosition: { didInitialPosition = $0 }
                    )
                }
                .onChange(of: scrollToTodayTrigger) {
                    CalendarMonthGridInteractionSupport.handleTodayTrigger(
                        proxy: proxy,
                        visibleMonthIdx: $visibleMonthIdx,
                        todayMonthIdx: todayMonthIdx
                    )
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
        CalendarMonthGridSupport.weeks(for: month, calendar: cal)
    }
}

#endif
