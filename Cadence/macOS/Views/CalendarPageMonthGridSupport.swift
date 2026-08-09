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

/// The month that actually occupies most of the viewport, not merely the one that owns its
/// top pixel.
///
/// `monthIndexForOffset` answers "which month band contains this y", which is the right
/// question for a scroll position but the wrong one for a header: one pixel past a boundary
/// the top row belongs to the next month while the remaining ~95% of the screen is still the
/// previous one, and the header would rename the whole page after a nudge. Measuring overlap
/// makes the label flip when the screen actually changes hands.
///
/// A `viewportHeight` of zero (unmeasured geometry) degrades to the top-anchored answer.
func dominantMonthIndex(
    topY: CGFloat,
    viewportHeight: CGFloat,
    offsets: [CGFloat],
    totalMonths: Int
) -> Int {
    let monthCount = min(offsets.count, max(totalMonths, 0))
    guard monthCount > 0 else { return 0 }

    let top = max(topY, 0)
    guard viewportHeight > 0 else {
        return monthIndexForOffset(y: top, offsets: offsets, totalMonths: totalMonths)
    }

    let bottom = top + viewportHeight
    let first = monthIndexForOffset(y: top, offsets: offsets, totalMonths: totalMonths)
    let last = monthIndexForOffset(y: bottom, offsets: offsets, totalMonths: totalMonths)

    var best = first
    var bestOverlap = -CGFloat.greatestFiniteMagnitude
    for idx in first...last {
        let start = offsets[idx]
        let end = idx + 1 < monthCount ? offsets[idx + 1] : CGFloat.greatestFiniteMagnitude
        let overlap = min(bottom, end) - max(top, start)
        // Strictly greater, so an exact tie keeps the earlier month rather than jittering
        // between two equal halves.
        if overlap > bestOverlap {
            bestOverlap = overlap
            best = idx
        }
    }
    return best
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

    /// Fallback row height, used only before the grid's viewport has been measured (the first
    /// layout pass reports a zero height). Real rows are sized by `rowHeight(weeksInMonth:_:)`.
    static let cellHeight: CGFloat = 130

    /// Floor for a week row. Below this a cell cannot show its day number plus a single chip,
    /// so a very short window scrolls instead of shrinking rows into illegibility.
    static let minimumRowHeight: CGFloat = 72

    /// Row height that divides the viewport evenly across *this* month's own week rows, so a
    /// month is exactly one screen tall: no dead band under a short month, no scrolling
    /// within a month.
    ///
    /// The grid tiles months without repeating days (a month block starts on its first Sunday
    /// and the days before it belong to the previous block), so a block is 4, 5, or 6 rows.
    /// Dividing by that count — rather than a fixed 6 — is what makes every month fill the
    /// window exactly.
    static func rowHeight(weeksInMonth: Int, viewportHeight: CGFloat) -> CGFloat {
        let weeks = CGFloat(max(1, weeksInMonth))
        guard viewportHeight > 0 else { return cellHeight }
        return max(minimumRowHeight, viewportHeight / weeks)
    }

    /// Rendered height of a whole month block. This is the *single* source of truth shared by
    /// the rendered rows and the scroll-offset table — see `CalendarMonthGridSupport
    /// .cumulativeOffsets`. Keeping one function on both sides is what prevents the two from
    /// drifting apart and mislabelling the header.
    static func monthHeight(weeksInMonth: Int, viewportHeight: CGFloat) -> CGFloat {
        let weeks = max(1, weeksInMonth)
        return CGFloat(weeks) * rowHeight(weeksInMonth: weeks, viewportHeight: viewportHeight)
    }
}

/// Vertical budget inside one month day cell.
///
/// The cell is now a fixed height (see `CalendarMonthGridMetrics.rowHeight`), so the chip cap
/// can no longer be a hardcoded `prefix(5)`: it has to be derived from the height the row was
/// actually given, or a short window would clip chips and a tall one would waste the space.
enum CalendarMonthCellLayout {
    /// 6pt top padding + the 24pt day-number circle.
    static let headerHeight: CGFloat = 30
    static let headerChipSpacing: CGFloat = 3
    static let chipHeight: CGFloat = 15
    static let chipSpacing: CGFloat = 2
    static let bottomPadding: CGFloat = 4
    /// Hollow completion circle on a task chip. Matches the task-row glyph elsewhere in the app.
    static let completionGlyphSize: CGFloat = 9

    /// How many chips fit in a row of `rowHeight`, ignoring any overflow label.
    static func chipCapacity(rowHeight: CGFloat) -> Int {
        let available = rowHeight - headerHeight - headerChipSpacing - bottomPadding
        guard available >= chipHeight else { return 0 }
        return max(0, Int((available + chipSpacing) / (chipHeight + chipSpacing)))
    }

    /// Splits a day's items into drawn chips and a "+N more" remainder.
    ///
    /// When there is overflow the label takes one chip slot (it is shorter than a chip, so it
    /// always fits where a chip would have), which keeps the cell inside its fixed height.
    static func chipLayout(totalItems: Int, rowHeight: CGFloat) -> (visible: Int, overflow: Int) {
        let capacity = chipCapacity(rowHeight: rowHeight)
        guard totalItems > capacity else { return (max(0, totalItems), 0) }
        let visible = max(0, capacity - 1)
        return (visible, totalItems - visible)
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
