import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The compact Month view's non-view logic: which days its agenda lists, how tall the grid may be so
/// that every week of the month is on screen, and the two rules that keep the grid and the agenda
/// from driving each other's selection in a loop.
@MainActor
struct CalendarMonthAgendaTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ key: String) -> Date {
        DateFormatters.date(from: key, in: calendar) ?? Date()
    }

    // MARK: - Which days the agenda lists

    /// The agenda lists exactly what the grid draws. If those two lists ever diverge, a grid cell
    /// becomes a control that scrolls nowhere.
    @Test func agendaListsEveryDayTheGridDraws() {
        let monthDate = date("2026-08-15")
        let gridDays = CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar)
        let agendaDays = CadenceCalendarMonthAgendaSupport.agendaDays(
            forMonthContaining: monthDate,
            calendar: calendar
        )

        #expect(agendaDays == gridDays)
        #expect(!agendaDays.isEmpty)
    }

    /// Empty days are listed too. Listing only days that hold something would leave a quiet month
    /// with three sections and nothing to scroll, and the grid's other twenty-eight cells with
    /// nowhere to jump to.
    @Test func agendaListsDaysWhateverTheyHold() {
        let keys = CadenceCalendarMonthAgendaSupport.agendaDayKeys(
            forMonthContaining: date("2026-02-10"),
            calendar: calendar
        )

        // February 2026 starts on a Sunday and has 28 days: exactly four grid weeks.
        #expect(keys.count == 28)
        #expect(keys.first == "2026-02-01")
        #expect(keys.last == "2026-02-28")
        #expect(keys.contains("2026-02-10"))
    }

    /// The grid pads out to whole weeks, so the agenda carries the adjacent-month days the grid
    /// draws in its leading and trailing cells.
    @Test func agendaCarriesTheGridsPaddingDays() {
        let keys = CadenceCalendarMonthAgendaSupport.agendaDayKeys(
            forMonthContaining: date("2026-08-15"),
            calendar: calendar
        )

        #expect(keys.count % 7 == 0)
        #expect(keys.first == "2026-07-26")
        #expect(keys.last == "2026-09-05")
    }

    /// Parsed in the system zone, not the UTC calendar the grid tests use: the label goes through
    /// `DateFormatters`, which formats in the system zone, so a UTC midnight would print as the day
    /// before west of Greenwich.
    @Test func dayHeaderReadsWeekdayThenDate() throws {
        let august15 = try #require(DateFormatters.date(from: "2026-08-15"))
        #expect(CadenceCalendarMonthAgendaSupport.dayHeaderLabel(for: august15) == "Sat · Aug 15")
    }

    // MARK: - Two-way selection sync

    @Test func tappingAGridDayScrollsTheAgendaToIt() {
        let keys = CadenceCalendarMonthAgendaSupport.agendaDayKeys(
            forMonthContaining: date("2026-08-15"),
            calendar: calendar
        )

        #expect(
            CadenceCalendarMonthAgendaSupport.scrollTarget(
                selectedKey: "2026-08-22",
                scrolledKey: "2026-08-15",
                agendaDayKeys: keys
            ) == "2026-08-22"
        )
    }

    /// The half of the loop guard that faces the finger: a selection that arrived *from* a scroll
    /// already matches where the agenda is, and re-issuing the scroll would fight the gesture that
    /// produced it.
    @Test func aSelectionTheAgendaIsAlreadyOnIssuesNoScroll() {
        #expect(
            CadenceCalendarMonthAgendaSupport.scrollTarget(
                selectedKey: "2026-08-15",
                scrolledKey: "2026-08-15",
                agendaDayKeys: ["2026-08-15"]
            ) == nil
        )
    }

    /// A day the agenda does not list has no section to scroll to. Issuing the scroll anyway would
    /// be silently dropped and leave the grid and the agenda pointing at different days.
    @Test func aDayTheAgendaDoesNotListIssuesNoScroll() {
        let keys = CadenceCalendarMonthAgendaSupport.agendaDayKeys(
            forMonthContaining: date("2026-08-15"),
            calendar: calendar
        )

        #expect(!keys.contains("2026-12-25"))
        #expect(
            CadenceCalendarMonthAgendaSupport.scrollTarget(
                selectedKey: "2026-12-25",
                scrolledKey: "2026-08-15",
                agendaDayKeys: keys
            ) == nil
        )
    }

    @Test func scrollingTheAgendaMovesTheSelection() {
        #expect(
            CadenceCalendarMonthAgendaSupport.selectionTarget(
                scrolledKey: "2026-08-19",
                selectedKey: "2026-08-15"
            ) == "2026-08-19"
        )
    }

    /// The other half of the loop guard: the scroll a grid tap causes settles on the day that is
    /// already selected, and must not push that selection back through a second time.
    @Test func aScrollLandingOnTheSelectedDayChangesNothing() {
        #expect(
            CadenceCalendarMonthAgendaSupport.selectionTarget(
                scrolledKey: "2026-08-15",
                selectedKey: "2026-08-15"
            ) == nil
        )
        #expect(
            CadenceCalendarMonthAgendaSupport.selectionTarget(
                scrolledKey: nil,
                selectedKey: "2026-08-15"
            ) == nil
        )
    }

    // MARK: - Grid geometry

    @Test func weekRowCountFollowsTheMonth() {
        // Aug 2026: Sat 1st, 31 days — six grid rows.
        #expect(
            CadenceCalendarMonthAgendaSupport.weekRowCount(
                forMonthContaining: date("2026-08-15"),
                calendar: calendar
            ) == 6
        )
        // Feb 2026: Sun 1st, 28 days — four.
        #expect(
            CadenceCalendarMonthAgendaSupport.weekRowCount(
                forMonthContaining: date("2026-02-10"),
                calendar: calendar
            ) == 4
        )
    }

    /// The whole point of the compact grid: a six-week month fits on a phone pane. The old cell had
    /// a 104pt minimum, which put three of those six weeks below the fold.
    @Test func everyWeekOfASixWeekMonthFitsAPhonePane() {
        let paneHeight: CGFloat = 600
        let headerHeight: CGFloat = 22
        let rowHeight = CadenceCalendarMonthAgendaSupport.gridRowHeight(
            availableHeight: paneHeight,
            rowCount: 6,
            weekdayHeaderHeight: headerHeight
        )

        #expect(rowHeight * 6 + headerHeight <= paneHeight)
        #expect(rowHeight * 6 + headerHeight < paneHeight * 0.55)
    }

    /// A grid cell is a control, so it never goes below a 44pt touch target however little room the
    /// pane has — the grid gives up its share of the pane before it gives up being tappable.
    @Test func rowHeightNeverDropsBelowATouchTarget() {
        #expect(
            CadenceCalendarMonthAgendaSupport.gridRowHeight(
                availableHeight: 200,
                rowCount: 6,
                weekdayHeaderHeight: 22
            ) == CGFloat(44)
        )
        #expect(
            CadenceCalendarMonthAgendaSupport.gridRowHeight(
                availableHeight: 0,
                rowCount: 6,
                weekdayHeaderHeight: 22
            ) == CGFloat(44)
        )
    }

    /// A tall pane must not turn a four-week month into four bands of empty grid — the agenda under
    /// it is what the rest of the height is for.
    @Test func rowHeightIsCappedOnATallPane() {
        let rowHeight = CadenceCalendarMonthAgendaSupport.gridRowHeight(
            availableHeight: 1400,
            rowCount: 4,
            weekdayHeaderHeight: 22
        )

        // `CGFloat`-spelled: `#expect` records a bare integer literal as an `Int`, which never
        // compares equal to a `CGFloat`.
        #expect(rowHeight == CGFloat(58))
    }

    @Test func rowHeightSurvivesAMonthWithNoRows() {
        #expect(
            CadenceCalendarMonthAgendaSupport.gridRowHeight(
                availableHeight: 600,
                rowCount: 0,
                weekdayHeaderHeight: 22
            ) == CGFloat(44)
        )
    }
}
