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
    let eventCache: CalendarEventDayCache
    @Binding var visibleMonthIdx: Int
    /// The month every cell in the grid is tinted against — **one** value for the whole grid, not
    /// one per block.
    ///
    /// This is the change the user asked for: the highlight is a property of what you are looking
    /// at, the way iOS's Month grid has always had it, rather than of which block a row happens to
    /// be drawn in. `nil` means "not measured yet" — while a programmatic jump is in flight, and
    /// before the first scroll report — and `tintMonth` falls back to the anchored block's own
    /// month, which is exactly right at the moment a block is pinned to the top of the viewport.
    ///
    /// A `@Binding` because the page's title reads it too, so the header cannot name a month the
    /// grid has stopped highlighting. See `CalendarPageLifecycleSupport.calendarTitleLabel`.
    @Binding var displayedMonth: Date?
    let scrollToTodayTrigger: Bool

    private let totalMonths = CalendarMonthGridMetrics.totalMonths
    private let todayMonthIdx = CalendarMonthGridMetrics.todayMonthIndex
    private let cal = Calendar.current
    @State private var didInitialPosition = false
    @State private var isProgrammaticScroll = false

    private var currentMonthStart: Date {
        CalendarMonthGridSupport.currentMonthStart(calendar: cal)
    }

    /// The single month the whole grid tints against. See `displayedMonth`.
    private var tintMonth: Date {
        displayedMonth ?? blockMonth(at: visibleMonthIdx)
    }

    private func blockMonth(at index: Int) -> Date {
        cal.date(byAdding: .month, value: index - todayMonthIdx, to: currentMonthStart) ?? currentMonthStart
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
                            // The grid's month, not this block's. A block passing its own `month`
                            // here is precisely the behaviour this replaced — see `displayedMonth`.
                            displayedMonth: tintMonth,
                            tasksByDate: tasksByDate,
                            bundlesByDate: bundlesByDate,
                            allTasks: allTasks,
                            eventCache: eventCache,
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
                    todayMonthIdx: todayMonthIdx,
                    currentMonthStart: currentMonthStart,
                    calendar: cal,
                    visibleMonthIdx: &visibleMonthIdx,
                    displayedMonth: &displayedMonth,
                    didInitialPosition: didInitialPosition,
                    isProgrammaticScroll: isProgrammaticScroll
                )
            }
            .onAppear {
                // Dropped, not recomputed: the three handlers below all anchor a block at the top
                // of the viewport, which is the one arrangement where the block's own month *is*
                // the displayed month — so the fallback in `tintMonth` is the right answer until
                // the scroll reports back.
                displayedMonth = nil
                CalendarMonthGridInteractionSupport.handleAppear(
                    proxy: proxy,
                    visibleMonthIdx: $visibleMonthIdx,
                    todayMonthIdx: todayMonthIdx,
                    setDidInitialPosition: { didInitialPosition = $0 },
                    setProgrammaticScroll: { isProgrammaticScroll = $0 }
                )
            }
            .onChange(of: viewportHeight) { _, _ in
                displayedMonth = nil
                CalendarMonthGridInteractionSupport.handleViewportHeightChange(
                    proxy: proxy,
                    visibleMonthIdx: visibleMonthIdx,
                    didInitialPosition: didInitialPosition,
                    setProgrammaticScroll: { isProgrammaticScroll = $0 }
                )
            }
            .onChange(of: scrollToTodayTrigger) {
                displayedMonth = nil
                CalendarMonthGridInteractionSupport.handleTodayTrigger(
                    proxy: proxy,
                    todayMonthIdx: todayMonthIdx,
                    todayKey: DateFormatters.todayKey(),
                    currentMonthStart: currentMonthStart,
                    calendar: cal,
                    centersTodayCell: todayBlockOverflowsViewport(viewportHeight),
                    setProgrammaticScroll: { isProgrammaticScroll = $0 }
                )
            }
        }
    }

    /// True only when the window is too short to fit the block that renders today, in which case
    /// the jump has to scroll to today's row rather than trusting the block anchor to bring it
    /// on screen.
    ///
    /// Measured against today's *rendering* block, not today's calendar month: on a day before
    /// its month's first Sunday those are different blocks with different row counts, and it is
    /// the block being scrolled to whose height decides whether today lands on screen.
    private func todayBlockOverflowsViewport(_ viewportHeight: CGFloat) -> Bool {
        guard viewportHeight > 0 else { return true }
        let weeks = weeksInMonth(CalendarMonthGridSupport.blockMonthStart(for: Date(), calendar: cal))
        return CalendarMonthGridMetrics.monthHeight(
            weeksInMonth: weeks,
            viewportHeight: viewportHeight
        ) > viewportHeight + 0.5
    }
}

struct MonthWeeksView: View {
    /// The block's own month. It decides which days this block **draws** — nothing about how they
    /// are tinted. Those two used to be the same value; see `displayedMonth`.
    let month: Date
    let monthIndex: Int
    /// The month the whole grid is reading as, from `MonthGridView`. Passed down rather than
    /// derived here on purpose: a block cannot see the viewport, and a block that answered this
    /// question for itself is what made the grid light two months at once mid-scroll.
    let displayedMonth: Date
    let tasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let allTasks: [AppTask]
    let eventCache: CalendarEventDayCache
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
                                displayMonth: displayedMonth,
                                blockMonth: month,
                                eventCache: eventCache,
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
