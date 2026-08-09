#if os(macOS)
import SwiftUI

enum CalendarMonthGridSupport {
    static func currentMonthStart(calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: Date())
        comps.day = 1
        return calendar.date(from: comps) ?? Date()
    }

    static func weeksInMonth(_ month: Date, calendar: Calendar) -> Int {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 5 }
        let startWeekday = calendar.component(.weekday, from: first) - 1
        let skipCount = startWeekday == 0 ? 0 : (7 - startWeekday)
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
        let startWeekday = calendar.component(.weekday, from: first) - 1
        guard let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }

        var days: [Date?] = []
        let skipCount = startWeekday == 0 ? 0 : (7 - startWeekday)
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
