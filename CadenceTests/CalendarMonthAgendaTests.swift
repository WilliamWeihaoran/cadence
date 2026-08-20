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

    /// `agendaDays` is the **candidate** list — every day of the grid, whatever it holds. What the
    /// agenda draws is this minus the quiet days (see the quiet-day section below); keeping the
    /// candidate list complete is what gives `nearestListedDayKey` something to resolve against.
    ///
    /// This test used to be called `agendaListsDaysWhateverTheyHold` and argued that listing only
    /// populated days would leave a quiet month with nothing to scroll. That is now the shipped
    /// behaviour: the user looked at thirty bare headers and decided a header that says "nothing"
    /// is still chrome. The function is unchanged; only what is done with its result is.
    @Test func agendaDaysCoversEveryDayTheGridDrawsWhateverItHolds() {
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

    // MARK: - Quiet days draw nothing

    /// August 2026's grid runs Jul 26 → Sep 5. Three populated days, chosen to sit apart so
    /// "nearest" has something to be nearest to.
    private let listed = ["2026-08-05", "2026-08-14", "2026-08-27"]

    /// A tap on a quiet day is a live control, not a dead one.
    ///
    /// Most of the grid's cells have no section of their own now. `.scrollPosition(id:)` drops a
    /// scroll to an id the stack does not contain — silently — so without this the grid would light
    /// a day and the agenda would stay where it was, with no gesture that puts them back.
    @Test func aTapOnAQuietDayResolvesToTheNextDayThatHasSomething() {
        #expect(CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: "2026-08-06", listedDayKeys: listed) == "2026-08-14")
        #expect(CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: "2026-08-13", listedDayKeys: listed) == "2026-08-14")
        // A day before every populated one still reads forward.
        #expect(CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: "2026-07-26", listedDayKeys: listed) == "2026-08-05")
    }

    /// A populated day resolves to itself — the resolution is not allowed to round a real section
    /// away to a neighbour.
    @Test func aDayThatHasASectionResolvesToItself() {
        for key in listed {
            #expect(CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: key, listedDayKeys: listed) == key)
        }
    }

    /// Past the last populated day there is no following section, so the preceding one is the
    /// fallback. Forward is the preference, not the only direction.
    @Test func aTapAfterTheLastPopulatedDayFallsBackToThePrecedingOne() {
        #expect(CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: "2026-08-28", listedDayKeys: listed) == "2026-08-27")
        #expect(CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: "2026-09-05", listedDayKeys: listed) == "2026-08-27")
    }

    /// The month that holds nothing at all. Every other case has a section to land on; this one has
    /// none, and answering with anything would be inventing a scroll target. The view draws no
    /// scroll view here at all, so there is nothing for a position to point at.
    @Test func aMonthHoldingNothingResolvesToNoSectionAtAll() {
        #expect(CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: "2026-08-15", listedDayKeys: []) == nil)
        #expect(
            CadenceCalendarMonthAgendaSupport.scrollTarget(
                forSelectedDay: "2026-08-15",
                scrolledKey: nil,
                listedDayKeys: []
            ) == nil
        )
        #expect(
            CadenceCalendarMonthAgendaSupport.initialScrollTarget(
                forSelectedDay: "2026-08-15",
                listedDayKeys: []
            ) == nil
        )
    }

    /// **This is the call site's decision, not a helper's.** `iOSCalendarMonthAgendaList` calls
    /// exactly this on a selection change, so a version that skipped the resolution — the old
    /// `scrollTarget(selectedKey:scrolledKey:agendaDayKeys:)`, which answers `nil` for any day the
    /// agenda does not list — fails here.
    ///
    /// The composition order is the reason the two steps are one function: resolving *after* the
    /// containment guard would compare an unlisted key against the list and always answer `nil`,
    /// which is the dead tap this exists to remove.
    @Test func theSelectionScrollTargetResolvesBeforeItGuards() {
        // The dead-tap answer, from the un-resolved spelling that is still the backstop.
        #expect(
            CadenceCalendarMonthAgendaSupport.scrollTarget(
                selectedKey: "2026-08-06",
                scrolledKey: "2026-08-05",
                agendaDayKeys: listed
            ) == nil
        )
        // The live one.
        #expect(
            CadenceCalendarMonthAgendaSupport.scrollTarget(
                forSelectedDay: "2026-08-06",
                scrolledKey: "2026-08-05",
                listedDayKeys: listed
            ) == "2026-08-14"
        )
    }

    /// The loop guard survives the resolution: a quiet day that resolves to the section the agenda
    /// is already parked on issues no scroll, so a selection arriving *from* a scroll cannot bounce
    /// back and fight the finger.
    @Test func aQuietDayResolvingToWhereTheAgendaAlreadyIsIssuesNoScroll() {
        #expect(
            CadenceCalendarMonthAgendaSupport.scrollTarget(
                forSelectedDay: "2026-08-13",
                scrolledKey: "2026-08-14",
                listedDayKeys: listed
            ) == nil
        )
        #expect(
            CadenceCalendarMonthAgendaSupport.scrollTarget(
                forSelectedDay: "2026-08-14",
                scrolledKey: "2026-08-14",
                listedDayKeys: listed
            ) == nil
        )
    }

    /// The opening position resolves the same way the later taps do, so the first frame and the
    /// first tap cannot disagree about which section a day belongs to.
    @Test func theOpeningSectionResolvesLikeATap() {
        for probe in ["2026-07-26", "2026-08-05", "2026-08-06", "2026-08-27", "2026-09-05"] {
            #expect(
                CadenceCalendarMonthAgendaSupport.initialScrollTarget(
                    forSelectedDay: probe,
                    listedDayKeys: listed
                ) == CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: probe, listedDayKeys: listed)
            )
        }
    }

    /// Every resolution names a section that exists. The whole point is that a resolved key can be
    /// handed to `.scrollPosition(id:)` without being dropped.
    @Test func everyResolvedDayIsOneTheAgendaActuallyDraws() {
        let grid = CadenceCalendarMonthAgendaSupport.agendaDayKeys(
            forMonthContaining: date("2026-08-15"),
            calendar: calendar
        )
        #expect(grid.count == 42)
        for key in grid {
            let resolved = CadenceCalendarMonthAgendaSupport.nearestListedDayKey(to: key, listedDayKeys: listed)
            #expect(resolved.map(listed.contains) == true, "\(key) resolved to \(resolved ?? "nothing")")
        }
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
