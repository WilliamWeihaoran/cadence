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
    let bundlesByDate: [String: [TaskBundle]]
    @Binding var visibleMonthIdx: Int
    let scrollToTodayTrigger: Bool

    private let totalMonths = CalendarMonthGridMetrics.totalMonths
    private let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex
    private let cal = Calendar.current
    @State private var didInitialPosition = false
    @State private var isProgrammaticScroll = false

    private var currentMonthStart: Date {
        CalendarMonthGridSupport.currentMonthStart(calendar: cal)
    }

    private func weeksInMonth(_ month: Date) -> Int {
        CalendarMonthGridSupport.weeksInMonth(month, calendar: cal)
    }

    var body: some View {
        VStack(spacing: 0) {
            MonthGridWeekdayHeader()

            Divider().background(Theme.borderSubtle.opacity(CalendarVisualStyle.dividerOpacity))

            // The grid is sized from the space actually left for it, so a month block is one
            // screen tall. That is what makes an empty month stop wasting the window — and it
            // is also what keeps the scroll-offset table honest, since the table and the rows
            // are now generated from the same height function.
            GeometryReader { geo in
                monthScroll(viewportHeight: geo.size.height)
            }
        }
        .background(Theme.bg)
    }

    private func monthScroll(viewportHeight: CGFloat) -> some View {
        let offsets = CalendarMonthGridSupport.cumulativeOffsets(
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            viewportHeight: viewportHeight,
            calendar: cal
        )

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<totalMonths, id: \.self) { idx in
                        let month = cal.date(byAdding: .month, value: idx - todayMonthIdx, to: currentMonthStart)!
                        MonthWeeksView(
                            month: month,
                            monthIndex: idx,
                            tasksByDate: tasksByDate,
                            bundlesByDate: bundlesByDate,
                            allTasks: allTasks,
                            rowHeight: CalendarMonthGridMetrics.rowHeight(
                                weeksInMonth: weeksInMonth(month),
                                viewportHeight: viewportHeight
                            )
                        )
                        .id(CalendarMonthGridIdentifiers.month(idx))
                    }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                CalendarMonthGridInteractionSupport.handleScroll(
                    y: y,
                    offsets: offsets,
                    totalMonths: totalMonths,
                    viewportHeight: viewportHeight,
                    visibleMonthIdx: &visibleMonthIdx,
                    didInitialPosition: didInitialPosition,
                    isProgrammaticScroll: isProgrammaticScroll
                )
            }
            .onAppear {
                CalendarMonthGridInteractionSupport.handleAppear(
                    proxy: proxy,
                    visibleMonthIdx: $visibleMonthIdx,
                    todayMonthIdx: todayMonthIdx,
                    setDidInitialPosition: { didInitialPosition = $0 },
                    setProgrammaticScroll: { isProgrammaticScroll = $0 }
                )
            }
            .onChange(of: viewportHeight) { _, _ in
                CalendarMonthGridInteractionSupport.handleViewportHeightChange(
                    proxy: proxy,
                    visibleMonthIdx: visibleMonthIdx,
                    didInitialPosition: didInitialPosition,
                    setProgrammaticScroll: { isProgrammaticScroll = $0 }
                )
            }
            .onChange(of: scrollToTodayTrigger) {
                CalendarMonthGridInteractionSupport.handleTodayTrigger(
                    proxy: proxy,
                    todayMonthIdx: todayMonthIdx,
                    todayKey: DateFormatters.todayKey(),
                    centersTodayCell: todayMonthOverflowsViewport(viewportHeight),
                    setProgrammaticScroll: { isProgrammaticScroll = $0 }
                )
            }
        }
    }

    /// True only when the window is too short to fit today's month, in which case the jump has
    /// to scroll to today's row rather than trusting the month header to bring it on screen.
    private func todayMonthOverflowsViewport(_ viewportHeight: CGFloat) -> Bool {
        guard viewportHeight > 0 else { return true }
        let weeks = weeksInMonth(currentMonthStart)
        return CalendarMonthGridMetrics.monthHeight(
            weeksInMonth: weeks,
            viewportHeight: viewportHeight
        ) > viewportHeight + 0.5
    }
}

struct MonthWeeksView: View {
    let month: Date
    let monthIndex: Int
    let tasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let allTasks: [AppTask]
    let rowHeight: CGFloat

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
                                bundles: bundlesByDate[key] ?? [],
                                allTasks: allTasks,
                                displayMonth: month,
                                rowHeight: rowHeight
                            )
                            .id(CalendarMonthGridIdentifiers.day(monthIndex: monthIndex, dateKey: key))
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight)
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
                }
            }
        }
    }

    private var weeks: [[Date?]] {
        CalendarMonthGridSupport.weeks(for: month, calendar: cal)
    }
}

#endif
