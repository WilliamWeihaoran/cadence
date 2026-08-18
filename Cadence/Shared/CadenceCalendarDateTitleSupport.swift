import Foundation

// MARK: - The calendar's date title

/// What the calendar's date title names, and how far from "now" it currently is.
///
/// Every calendar surface now has the same title: the date at the leading edge of what is on screen,
/// with a chevron and a popover that jumps somewhere else. What differs is the *unit* — a timed grid
/// and the Board are looking at a day, Month is looking at a month — and that difference is three
/// paired questions (what does the label say, when is it "now", what does a picked date mean), which
/// is exactly the kind of thing that drifts when it is spelled at the call site.
///
/// This exists because the `‹ ➤ ›` cluster was deleted from all four surfaces. Its middle control
/// was `location.fill` — jump to today, not a direction — so the title had to grow that shortcut
/// before the cluster could go.
enum CadenceCalendarDateTitleFormat: Hashable {
    /// One day: Week, 2 Weeks and the Board, all of which scroll a day at a time.
    case day
    /// One month: the month grid, which scrolls a week row at a time but is read a month at a time.
    case month
}

enum CadenceCalendarDateTitleSupport {
    static func label(
        for date: Date,
        format: CadenceCalendarDateTitleFormat,
        calendar: Calendar = .current
    ) -> String {
        switch format {
        case .day:
            return DateFormatters.shortDate.string(from: date)
        case .month:
            return DateFormatters.monthYear.string(
                from: CadenceCalendarMonthWindow.displayedMonth(topRowStart: date, calendar: calendar)
            )
        }
    }

    /// Whether the title is naming the present. The title renders in `Theme.text` when it is and in
    /// `Theme.blue` when it is not, so the header itself says you have scrolled away — without it a
    /// week in March is indistinguishable at a glance from this one.
    static func isAtNow(
        _ date: Date,
        format: CadenceCalendarDateTitleFormat,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch format {
        case .day:
            return calendar.isDate(date, inSameDayAs: now)
        case .month:
            let displayed = CadenceCalendarMonthWindow.displayedMonth(topRowStart: date, calendar: calendar)
            return calendar.isDate(displayed, equalTo: now, toGranularity: .month)
        }
    }

    /// The day the title's popover should open on. For Month the bound value is a **week row start**,
    /// which is a layout position rather than a date the user ever chose — opening the picker on it
    /// would highlight July 27 under a grid reading "August".
    ///
    /// `displayedMonth` is the right answer for the *title*, and the wrong one for the *seed*: it
    /// resolves the window to its middle day, so an August-aligned window seeded the picker on
    /// August 16 — a day nobody chose and nothing on screen points at, arrived at because six rows
    /// of seven halve to twenty-one. The month is a real reading of the window; the day inside it is
    /// a layout artefact, and the seed is the one place the day is visible.
    ///
    /// So Month names the day itself: **today when the displayed month contains today, otherwise
    /// the first**. Today is the only day of a month the user has a standing relationship with, and
    /// it agrees with `isAtNow` and with the popover's own `Today` row, so the current month opens
    /// with the highlight already where that row would put it. Any other month has no such day, and
    /// the 1st is what "August" means read as a date — stable, and never a number the reader has to
    /// work out. `anchor(forPicked:)` discards the day component either way, so this decides what is
    /// highlighted and nothing about where a pick lands.
    static func pickerDate(
        for date: Date,
        format: CadenceCalendarDateTitleFormat,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        switch format {
        case .day:
            return calendar.startOfDay(for: date)
        case .month:
            let displayed = CadenceCalendarMonthWindow.displayedMonth(topRowStart: date, calendar: calendar)
            if calendar.isDate(displayed, equalTo: now, toGranularity: .month) {
                return calendar.startOfDay(for: now)
            }
            return calendar.dateInterval(of: .month, for: displayed)?.start ?? displayed
        }
    }

    /// The value to write back when a day is picked — the inverse of `pickerDate`. Picking any day of
    /// August in Month scrolls the grid to August's first row, not to the week that day falls in.
    static func anchor(
        forPicked date: Date,
        format: CadenceCalendarDateTitleFormat,
        calendar: Calendar = .current
    ) -> Date {
        switch format {
        case .day:
            return calendar.startOfDay(for: date)
        case .month:
            return CadenceCalendarMonthWindow.topRow(forMonthContaining: date, calendar: calendar)
        }
    }

    /// Where the popover's `Today` row goes. `anchor(forPicked:)` of now, stated separately because
    /// this is the half that replaced a toolbar button and it should be findable by name.
    static func nowAnchor(
        format: CadenceCalendarDateTitleFormat,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        anchor(forPicked: now, format: format, calendar: calendar)
    }
}
