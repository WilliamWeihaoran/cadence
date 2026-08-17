import Foundation
import Testing
@testable import Cadence

/// Which day Month's date dropdown opens on.
///
/// Month binds a **week row start**, and its title resolves that window to a month by reading the
/// middle of it — correct for a title, since a six-row window aligned to August begins in July. The
/// seed used to be the same value, so the popover opened with August **16** lit up: the middle of
/// six rows of seven, a number produced by the layout and pointed at by nothing on screen.
///
/// The rule now is *today when the displayed month contains today, otherwise the first*. These pin
/// both halves, and the property that made the old behaviour wrong in the first place: the seed is a
/// day the reader can account for.
@MainActor
struct CalendarMonthPickerSeedTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ key: String) -> Date {
        DateFormatters.date(from: key, in: calendar) ?? Date()
    }

    private func key(_ date: Date) -> String {
        DateFormatters.dateKey(from: date, calendar: calendar)
    }

    private func alignedWindow(_ monthKey: String) -> Date {
        CadenceCalendarMonthWindow.topRow(forMonthContaining: date(monthKey), calendar: calendar)
    }

    /// The month you are standing in opens on the day you are standing on, which is also where the
    /// popover's own `Today` row would put it.
    @Test func theCurrentMonthSeedsOnToday() {
        let now = date("2026-08-18")
        let seed = CadenceCalendarDateTitleSupport.pickerDate(
            for: alignedWindow("2026-08-15"),
            format: .month,
            now: now,
            calendar: calendar
        )
        #expect(key(seed) == "2026-08-18")
    }

    /// Any other month has no such day, so it opens on the one the month's name means.
    @Test func anotherMonthSeedsOnTheFirst() {
        let now = date("2026-08-18")
        for (monthKey, expected) in [("2026-02-15", "2026-02-01"), ("2026-11-15", "2026-11-01"), ("2025-12-15", "2025-12-01")] {
            let seed = CadenceCalendarDateTitleSupport.pickerDate(
                for: alignedWindow(monthKey),
                format: .month,
                now: now,
                calendar: calendar
            )
            #expect(key(seed) == expected, "\(monthKey) seeded \(key(seed))")
        }
    }

    /// The regression itself. `displayedMonth` lands three rows down the window — August 16 under a
    /// grid reading "August" — and the seed must no longer be that value, whichever month it is.
    @Test func theSeedIsNeverTheWindowsMiddleDay() {
        let now = date("2026-08-18")
        for monthKey in ["2026-02-15", "2026-08-15", "2026-11-15"] {
            let window = alignedWindow(monthKey)
            let middle = CadenceCalendarMonthWindow.displayedMonth(topRowStart: window, calendar: calendar)
            let seed = CadenceCalendarDateTitleSupport.pickerDate(
                for: window,
                format: .month,
                now: now,
                calendar: calendar
            )
            #expect(key(seed) != key(middle), "\(monthKey) still seeds the middle row")
        }
    }

    /// Whatever day it picks has to be **in the month the grid is showing**, or the popover and the
    /// title disagree about where you are — and the seed must still round-trip back to the same
    /// window, so opening the dropdown and closing it cannot move the grid.
    @Test func theSeedStaysInsideTheDisplayedMonthAndDoesNotMoveTheGrid() {
        let now = date("2026-08-18")
        for monthKey in ["2026-02-15", "2026-08-15", "2026-11-15", "2027-01-15"] {
            let window = alignedWindow(monthKey)
            let displayed = CadenceCalendarMonthWindow.displayedMonth(topRowStart: window, calendar: calendar)
            let seed = CadenceCalendarDateTitleSupport.pickerDate(
                for: window,
                format: .month,
                now: now,
                calendar: calendar
            )

            #expect(calendar.isDate(seed, equalTo: displayed, toGranularity: .month), "\(monthKey) seeded \(key(seed))")

            let back = CadenceCalendarDateTitleSupport.anchor(forPicked: seed, format: .month, calendar: calendar)
            #expect(key(back) == key(window), "\(monthKey) drifted to \(key(back))")
        }
    }

    /// The day surfaces bind the day they show, so their seed is that day and nothing about this
    /// changed for them.
    @Test func aDaySurfaceStillSeedsOnItsOwnDay() {
        let seed = CadenceCalendarDateTitleSupport.pickerDate(
            for: date("2026-03-09"),
            format: .day,
            now: date("2026-08-18"),
            calendar: calendar
        )
        #expect(key(seed) == "2026-03-09")
    }
}
