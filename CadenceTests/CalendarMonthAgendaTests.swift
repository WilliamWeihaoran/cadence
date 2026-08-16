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

    /// A grid cell is a control, so it holds a 44pt touch target on every pane that can carry the
    /// grid and the agenda at once — which is every pane a real device hands this view.
    @Test func rowHeightHoldsATouchTargetOnAnyPaneThatFitsBoth() {
        for paneHeight in stride(from: CGFloat(400), through: 1400, by: 50) {
            let rowHeight = CadenceCalendarMonthAgendaSupport.gridRowHeight(
                availableHeight: paneHeight,
                rowCount: 6,
                weekdayHeaderHeight: 22
            )
            #expect(rowHeight >= 44, "row collapsed below the touch floor at \(paneHeight)pt")
        }
    }

    /// The blank-agenda regression, pinned.
    ///
    /// The touch floor used to be applied last and unconditionally, so a six-row month asked for
    /// `22 + 6 × 44 + 8 = 294pt` of grid however short the pane was. The grid is the fixed-height
    /// child of that `VStack` and the agenda's `ScrollView` is the flexible one, so the grid was
    /// served first and the agenda was laid out at whatever remained — nothing, on any pane under
    /// ~300pt. A zero-height scroll view reads as a pane that draws its grid and then shows no day
    /// headings, no rows, and no scroll in either direction that brings any back.
    ///
    /// The floor is a floor on the grid's share, not a claim against the pane: the agenda keeps its
    /// minimum first, and the cells give up height rather than give up the agenda.
    @Test func theAgendaAlwaysKeepsRoomToDrawSomething() {
        let headerHeight: CGFloat = 22
        let bottomPadding: CGFloat = 8

        for rowCount in 4...6 {
            for paneHeight in stride(from: CGFloat(120), through: 1400, by: 20) {
                let rowHeight = CadenceCalendarMonthAgendaSupport.gridRowHeight(
                    availableHeight: paneHeight,
                    rowCount: rowCount,
                    weekdayHeaderHeight: headerHeight
                )
                let gridHeight = rowHeight * CGFloat(rowCount) + headerHeight + bottomPadding
                let agendaHeight = paneHeight - gridHeight

                // On a pane too short even for the grid's own chrome, the agenda gets what is left
                // after that chrome — but never nothing.
                let owed = min(
                    CadenceCalendarMonthAgendaSupport.agendaMinimumHeight,
                    max(0, paneHeight - headerHeight - bottomPadding)
                )

                #expect(
                    agendaHeight >= owed - 0.001,
                    "\(rowCount) rows in \(paneHeight)pt left the agenda \(agendaHeight)pt"
                )
            }
        }
    }

    /// The specific pane the old floor blanked: 280pt of calendar, five week rows.
    @Test func aShortPaneShrinksTheGridRatherThanTheAgenda() {
        let rowHeight = CadenceCalendarMonthAgendaSupport.gridRowHeight(
            availableHeight: 280,
            rowCount: 5,
            weekdayHeaderHeight: 22
        )

        #expect(rowHeight < 44)
        #expect(280 - (rowHeight * 5 + 22 + 8) >= 96)
    }

    @Test func rowHeightSurvivesAPaneWithNoHeight() {
        #expect(
            CadenceCalendarMonthAgendaSupport.gridRowHeight(
                availableHeight: 0,
                rowCount: 6,
                weekdayHeaderHeight: 22
            ) == CGFloat(0)
        )
    }

    /// The phone this view shipped on is untouched by the cap: a 402×874 phone gives Month roughly
    /// 750pt, where the grid's 0.46 share is what decides the row height and the cap never binds.
    @Test func aPhonePaneIsSizedByItsShareNotByTheCap() {
        #expect(
            CadenceCalendarMonthAgendaSupport.gridRowHeight(
                availableHeight: 750,
                rowCount: 6,
                weekdayHeaderHeight: 22
            ) == CadenceCalendarMonthAgendaSupport.gridRowHeight(
                availableHeight: 750,
                rowCount: 6,
                weekdayHeaderHeight: 22,
                agendaMinimumHeight: 0
            )
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
