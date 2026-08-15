import CoreGraphics
import Foundation

/// The logic behind the compact **Month** view: a month grid on top, a live agenda underneath.
///
/// Month was the last calendar mode still carrying the shared chrome block `ecaf80f` removed from
/// Week and Board — the four "0 total / 0 timed / 0 tasks / 0 events" chips, the selected-day card,
/// and the oversized empty state. It was left deliberately: the grid alone lists nothing, so
/// stripping the inspector without building an agenda first would have left a month you could look
/// at but not read. This type is that agenda's half of the work — which days it lists, what each
/// day's heading says, how tall the grid may grow, and the two rules that keep tapping a grid day
/// and scrolling the agenda from driving each other in a loop.
///
/// It lives in `Shared/` rather than beside the view because `Cadence/iOS/` is inside
/// `#if os(iOS)` and invisible to the macOS-built `CadenceTests`.
enum CadenceCalendarMonthAgendaSupport {

    // MARK: - Which days the agenda lists

    /// The days the agenda lists, in order: **exactly** the days the grid draws.
    ///
    /// Not the calendar month, and not just the days that hold something. The grid and the agenda
    /// are two views of one list, so every cell has a section to jump to and every section has a
    /// cell to light up. Listing only the month proper would leave the grid's leading and trailing
    /// cells as controls that look tappable and scroll nowhere; listing only non-empty days would
    /// do the same to every empty day, which is most of them — and would leave a quiet month with
    /// too little agenda to scroll, which is the other half of the two-way sync.
    static func agendaDays(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> [Date] {
        CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar)
    }

    static func agendaDayKeys(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> [String] {
        agendaDays(forMonthContaining: monthDate, calendar: calendar).map {
            DateFormatters.dateKey(from: $0, calendar: calendar)
        }
    }

    /// A day section's heading — `Sat · Aug 15`, which the shared board column header uppercases to
    /// `SAT · AUG 15`. Same shape as a Calendar Board day column's heading, because it is the same
    /// thing: the label over one day's items.
    static func dayHeaderLabel(for date: Date) -> String {
        "\(DateFormatters.dayOfWeek.string(from: date)) · \(DateFormatters.shortDate.string(from: date))"
    }

    // MARK: - Two-way selection sync

    /// The agenda section a **selection change** should scroll to, or `nil` to leave the agenda
    /// where it is.
    ///
    /// `nil` in the two cases that would otherwise close the loop between the grid and the agenda:
    /// the agenda already sits at that section — which is what a selection arriving *from* a scroll
    /// looks like, so re-issuing the scroll would fight the finger — and a day the agenda does not
    /// list, where the scroll would be dropped on the floor and leave the two out of step with no
    /// way back.
    static func scrollTarget(selectedKey: String, scrolledKey: String?, agendaDayKeys: [String]) -> String? {
        guard scrolledKey != selectedKey else { return nil }
        guard agendaDayKeys.contains(selectedKey) else { return nil }
        return selectedKey
    }

    /// The day a **scrolled-to section** should select, or `nil` to leave the selection alone.
    ///
    /// The mirror of `scrollTarget`: a scroll that lands back on the already-selected day — which is
    /// what the scroll *caused by* a grid tap settles into — changes nothing, so the tap does not
    /// bounce back through the selection a second time.
    static func selectionTarget(scrolledKey: String?, selectedKey: String) -> String? {
        guard let scrolledKey, scrolledKey != selectedKey else { return nil }
        return scrolledKey
    }

    // MARK: - Grid geometry

    /// How many week rows the grid draws for this month — 4, 5 or 6 depending on where the first of
    /// the month falls.
    static func weekRowCount(forMonthContaining monthDate: Date, calendar: Calendar = .current) -> Int {
        let days = agendaDays(forMonthContaining: monthDate, calendar: calendar).count
        return max(0, days / 7)
    }

    /// The height of one week row, so that **every** week of the month is on screen at once.
    ///
    /// The compact month used to give the grid the bottom ~40% of a pane it shared with a day
    /// inspector, at a 104pt minimum cell — three weeks fitted and the rest were below the fold, on
    /// the one view whose entire job is showing a whole month. Rows are sized to a share of the
    /// pane instead, so the row *count* is what the grid honours and the row *height* is what gives.
    /// The floor is a 44pt touch target, never less: a cell is a control.
    static func gridRowHeight(
        availableHeight: CGFloat,
        rowCount: Int,
        weekdayHeaderHeight: CGFloat,
        gridHeightFraction: CGFloat = 0.46,
        minimumRowHeight: CGFloat = 44,
        maximumRowHeight: CGFloat = 58
    ) -> CGFloat {
        guard rowCount > 0 else { return minimumRowHeight }
        let fraction = min(max(gridHeightFraction, 0), 1)
        let budget = max(0, availableHeight * fraction - weekdayHeaderHeight)
        let fitted = budget / CGFloat(rowCount)
        return min(max(fitted, minimumRowHeight), max(minimumRowHeight, maximumRowHeight))
    }
}
