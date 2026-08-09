#if os(macOS)
import SwiftUI

enum CalendarMonthGridSupport {
    static func currentMonthStart(calendar: Calendar, reference: Date = Date()) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: reference)
        comps.day = 1
        return calendar.date(from: comps) ?? reference
    }

    // MARK: - Block tiling rule

    /// How many days at the head of `month` the grid renders inside the **previous** month's
    /// block.
    ///
    /// A block begins on its month's first Sunday, so the 0–6 days before that Sunday are
    /// carried as trailing fill on the block before it. This function is the only place that
    /// rule is written down: `weeksInMonth`, `weeks(for:)`, `blockFirstDay(of:)` and
    /// `blockMonthStart(for:)` all read it here instead of each recomputing `7 - startWeekday`.
    ///
    /// That single derivation is the point. "Which days does this block hold" and "which block
    /// holds this day" are answers to the same question, and the moment they are computed from
    /// two separate copies of the rule they are free to disagree — which is exactly how the
    /// month grid ended up tagging today's cell with an id that the "Today" jump never asked
    /// for. See the header note on `cumulativeOffsets(totalMonths:...viewportHeight:...)` for
    /// the same lesson learned about the offset table.
    static func leadingDaysRenderedInPreviousBlock(of month: Date, calendar: Calendar) -> Int {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return 0 }
        let startWeekday = calendar.component(.weekday, from: first) - 1
        return startWeekday == 0 ? 0 : (7 - startWeekday)
    }

    /// First day the block for `month` actually renders — its month's first Sunday.
    ///
    /// The 1st of the month is *not* a safe stand-in for a block: for a month that does not
    /// start on a Sunday the 1st is drawn on the previous page, so a round trip through it
    /// lands one block early.
    static func blockFirstDay(of month: Date, calendar: Calendar) -> Date {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return month }
        let carried = leadingDaysRenderedInPreviousBlock(of: first, calendar: calendar)
        return calendar.date(byAdding: .day, value: carried, to: first) ?? first
    }

    /// The month whose block **renders** `date` — which is not always the calendar month `date`
    /// falls in.
    ///
    /// For the 0–6 days that precede their month's first Sunday, the rendering block is the
    /// month before. Anything that turns a date into a scroll target has to ask this, not
    /// `monthStart(for:)`; anything that names a month for the reader asks `monthStart(for:)`.
    static func blockMonthStart(for date: Date, calendar: Calendar) -> Date {
        let ownMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let carried = leadingDaysRenderedInPreviousBlock(of: ownMonth, calendar: calendar)
        guard calendar.component(.day, from: date) <= carried else { return ownMonth }
        return calendar.date(byAdding: .month, value: -1, to: ownMonth) ?? ownMonth
    }

    static func weeksInMonth(_ month: Date, calendar: Calendar) -> Int {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 5 }
        let skipCount = leadingDaysRenderedInPreviousBlock(of: first, calendar: calendar)
        let remaining = max(0, range.count - skipCount)
        return max(1, (remaining + 6) / 7)
    }

    static func cumulativeOffsets(
        totalMonths: Int,
        todayMonthIdx: Int,
        currentMonthStart: Date,
        cellHeight: CGFloat,
        calendar: Calendar
    ) -> [CGFloat] {
        cumulativeOffsets(
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            calendar: calendar
        ) { weeks in CGFloat(weeks) * cellHeight }
    }

    /// Offset table for a viewport-sized grid, where each month block is exactly one screen tall.
    ///
    /// Derived from `CalendarMonthGridMetrics.monthHeight`, the same function the rendered rows
    /// are sized with. That shared derivation is the point: the table is a model of the layout,
    /// and a model built from different numbers than the layout drifts a little further with
    /// every month until the header names a month the grid is not showing.
    static func cumulativeOffsets(
        totalMonths: Int,
        todayMonthIdx: Int,
        currentMonthStart: Date,
        viewportHeight: CGFloat,
        calendar: Calendar
    ) -> [CGFloat] {
        cumulativeOffsets(
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            calendar: calendar
        ) { weeks in
            CalendarMonthGridMetrics.monthHeight(weeksInMonth: weeks, viewportHeight: viewportHeight)
        }
    }

    private static func cumulativeOffsets(
        totalMonths: Int,
        todayMonthIdx: Int,
        currentMonthStart: Date,
        calendar: Calendar,
        height: (Int) -> CGFloat
    ) -> [CGFloat] {
        var offsets: [CGFloat] = []
        var y: CGFloat = 0
        for i in 0..<totalMonths {
            offsets.append(y)
            let month = calendar.date(byAdding: .month, value: i - todayMonthIdx, to: currentMonthStart) ?? currentMonthStart
            y += height(weeksInMonth(month, calendar: calendar))
        }
        return offsets
    }

    static func weeks(for month: Date, calendar: Calendar) -> [[Date?]] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return [] }
        guard let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }

        var days: [Date?] = []
        let skipCount = leadingDaysRenderedInPreviousBlock(of: first, calendar: calendar)
        if skipCount < daysInMonth {
            for i in skipCount..<daysInMonth {
                days.append(calendar.date(byAdding: .day, value: i, to: first)!)
            }
        }

        if days.count % 7 != 0 {
            let remainder = days.count % 7
            let needed = 7 - remainder
            for i in 0..<needed {
                days.append(calendar.date(byAdding: .day, value: daysInMonth + i, to: first)!)
            }
        }

        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }
}
#endif
