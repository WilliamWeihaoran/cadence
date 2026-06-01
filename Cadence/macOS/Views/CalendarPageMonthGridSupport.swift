#if os(macOS)
import SwiftUI
import Foundation

func monthStart(for date: Date, calendar: Calendar) -> Date {
    let comps = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: comps) ?? date
}

func monthIndex(for date: Date, currentMonthStart: Date, todayMonthIdx: Int, calendar: Calendar) -> Int {
    let targetMonthStart = monthStart(for: date, calendar: calendar)
    let delta = calendar.dateComponents([.month], from: currentMonthStart, to: targetMonthStart).month ?? 0
    return min(max(todayMonthIdx + delta, 0), 119)
}

func monthIndexForOffset(y: CGFloat, offsets: [CGFloat], totalMonths: Int) -> Int {
    let monthCount = min(offsets.count, max(totalMonths, 0))
    guard monthCount > 0 else { return 0 }

    var lo = 0
    var hi = monthCount - 1
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if offsets[mid] <= y { lo = mid } else { hi = mid - 1 }
    }
    return lo
}

enum CalendarMonthGridIdentifiers {
    static func month(_ index: Int) -> String {
        "month_\(index)"
    }

    static func day(monthIndex: Int, dateKey: String) -> String {
        "month_day_\(monthIndex)_\(dateKey)"
    }
}

struct MonthGridWeekdayHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .background(Theme.surface)
    }
}
#endif
