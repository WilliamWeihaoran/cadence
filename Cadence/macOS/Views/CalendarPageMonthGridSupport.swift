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
    let rawIndex = todayMonthIdx + delta
    let clampedIndex = min(max(rawIndex, 0), CalendarMonthGridMetrics.totalMonths - 1)
    #if DEBUG
    // Dev-only diagnostic (never traps, never changes the return value): surfaces window-
    // boundary mismatches — e.g. the timeline's day buffer and the month grid's window use
    // different spans — that would otherwise silently clamp with no signal anything was off.
    if rawIndex != clampedIndex {
        print("[CalendarMonthGrid] monthIndex(for:) computed an out-of-window index (\(rawIndex)); the anchor date fell outside the month grid's \(CalendarMonthGridMetrics.totalMonths)-month buffer and was silently clamped to \(clampedIndex).")
    }
    #endif
    return clampedIndex
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

/// Single source of truth for the month grid's window size and cell sizing.
/// Previously `totalMonths` (120), `todayMonthIdx`/`todayMonthIndex` (60), and
/// `cellHeight` (130) were each declared independently in `CalendarPageComponents.swift`,
/// `CalendarPageStateSupport.swift`, and `CalendarPageView.swift` — any future edit to one
/// without the others would silently desync the offset table from actual scroll position.
enum CalendarMonthGridMetrics {
    static let totalMonths = 120
    static let todayMonthIndex = 60
    static let cellHeight: CGFloat = 130
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
