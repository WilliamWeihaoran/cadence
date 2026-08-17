import Foundation
import Testing
@testable import Cadence

/// Month's continuously scrolling grid, and the date title that replaced the `‹ ➤ ›` cluster on
/// every calendar surface.
///
/// Month was the last calendar mode that stepped rather than scrolled: a fixed 4/5/6-row grid of one
/// month, rebuilt by the toolbar's chevrons. It now scrolls a week row at a time through a wide run
/// of rows, the way the timed grids and the Board already scroll through day columns — so the same
/// three things have to hold, and none of them is visible on screen when it stops holding:
///
/// 1. A row index and a date agree, both ways, and every row is a week boundary.
/// 2. The window slides before the run ends, so "without end" is true rather than merely large.
/// 3. The title names what is on screen, not the row at its edge — a six-row window aligned to
///    August *starts* in July.
///
/// Landscape is unverifiable through the simulator tooling (there is no rotate action), so the pane
/// heights an iPad in landscape produces are covered here and nowhere else.
@MainActor
struct CalendarMonthScrollWindowTests {

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

    // MARK: - Where a month opens

    /// Entering Month puts the **first row of that month's grid** at the top, not the week the
    /// selected day happens to fall in. Otherwise choosing the 20th would open on a window running
    /// from the 16th into the next month, with the first three weeks of the month above the fold on
    /// the one view whose subject is a month.
    @Test func aMonthOpensOnTheFirstRowOfItsOwnGrid() {
        for dayOfMonth in [1, 9, 20, 31] {
            let day = date(String(format: "2026-08-%02d", dayOfMonth))
            let top = CadenceCalendarMonthWindow.topRow(forMonthContaining: day, calendar: calendar)
            let gridDays = CadenceScheduleSupport.monthGridDays(for: day, calendar: calendar)
            #expect(key(top) == key(gridDays[0]), "August opened on \(key(top)) from day \(dayOfMonth)")
        }
    }

    /// Six rows from that top covers every day of the month, for a month that needs six and for one
    /// that needs four. This is what makes a fixed visible row count safe.
    @Test func sixRowsFromTheTopCoverTheWholeMonth() {
        // August 2026 starts on a Saturday and needs six rows; February 2026 starts on a Sunday and
        // is exactly four.
        for monthKey in ["2026-08-15", "2026-02-15", "2026-11-15", "2027-01-15"] {
            let top = CadenceCalendarMonthWindow.topRow(forMonthContaining: date(monthKey), calendar: calendar)
            let visibleDays = CadenceCalendarMonthWindow.visibleRowCount * CadenceCalendarMonthWindow.daysPerRow
            let last = calendar.date(byAdding: .day, value: visibleDays - 1, to: top) ?? top
            let monthDays = CadenceScheduleSupport.monthGridDays(for: date(monthKey), calendar: calendar)
            #expect(monthDays.allSatisfy { $0 >= top && $0 <= last }, "\(monthKey) did not fit six rows")
        }
    }

    // MARK: - Row index ↔ date

    /// A row index and its date round-trip through the window, and a date's index is the index of its
    /// **week** — so a mid-week date persisted by an older build still resolves to a row.
    @Test func aRowIndexAndItsDateAgreeBothWays() {
        let anchor = date("2026-08-15")
        let start = CadenceCalendarMonthWindow.windowStart(for: anchor, calendar: calendar)

        for index in [0, 13, 210, 419] {
            let rowDate = CadenceCalendarMonthWindow.date(at: index, windowStart: start, calendar: calendar)
            #expect(CadenceCalendarMonthWindow.index(for: rowDate, windowStart: start, calendar: calendar) == index)
        }

        let midWeek = date("2026-08-19")
        let weekStart = CadenceScheduleSupport.startOfWeek(containing: midWeek, calendar: calendar)
        #expect(
            CadenceCalendarMonthWindow.index(for: midWeek, windowStart: start, calendar: calendar)
                == CadenceCalendarMonthWindow.index(for: weekStart, windowStart: start, calendar: calendar)
        )
    }

    /// Every rendered row is a week start. A row that began mid-week would put a week's day numbers
    /// under the wrong weekday headings — the same skew `weekdaySymbols` exists to prevent.
    @Test func everyRenderedRowStartsOnAWeekBoundary() {
        let start = CadenceCalendarMonthWindow.windowStart(for: date("2026-08-15"), calendar: calendar)
        for index in [0, 1, 5, 209, 210, 419] {
            let rowDate = CadenceCalendarMonthWindow.date(at: index, windowStart: start, calendar: calendar)
            #expect(
                key(CadenceScheduleSupport.startOfWeek(containing: rowDate, calendar: calendar)) == key(rowDate),
                "row \(index) began at \(key(rowDate))"
            )
        }
    }

    // MARK: - The window slides

    /// The middle of the run leaves the window alone, and both ends rebuild it. Without the first
    /// half the grid re-scrolls under a finger that is still moving; without the second half
    /// "infinite" is a 420-row wall you hit in eight years of scrolling.
    @Test func theWindowSlidesAtEitherEndAndNowhereElse() {
        let anchor = date("2026-08-15")
        let start = CadenceCalendarMonthWindow.windowStart(for: anchor, calendar: calendar)
        let middle = CadenceCalendarMonthWindow.date(at: 210, windowStart: start, calendar: calendar)

        #expect(
            CadenceCalendarMonthWindow.recenteredWindowStart(
                topIndex: 210,
                topDate: middle,
                currentWindowStart: start,
                calendar: calendar
            ) == nil
        )

        for edgeIndex in [3, CadenceCalendarMonthWindow.renderRowCount - 4] {
            let edgeDate = CadenceCalendarMonthWindow.date(at: edgeIndex, windowStart: start, calendar: calendar)
            let rebuilt = CadenceCalendarMonthWindow.recenteredWindowStart(
                topIndex: edgeIndex,
                topDate: edgeDate,
                currentWindowStart: start,
                calendar: calendar
            )
            #expect(rebuilt != nil, "the window did not slide at row \(edgeIndex)")
            guard let rebuilt else { continue }
            let newIndex = CadenceCalendarMonthWindow.index(for: edgeDate, windowStart: rebuilt, calendar: calendar)
            #expect(newIndex == CadenceCalendarMonthWindow.leadingRowCount)
        }
    }

    /// The no-op guard: a rebuilt start that lands where the window already is returns `nil` rather
    /// than re-asserting the same position. Re-asserting is a scroll, and a scroll issued while the
    /// finger is down fights it.
    @Test func aWindowAlreadyInPlaceIsNotRebuilt() {
        let edgeDate = date("2026-08-15")
        let alreadyCentred = CadenceCalendarMonthWindow.windowStart(for: edgeDate, calendar: calendar)
        #expect(
            CadenceCalendarMonthWindow.recenteredWindowStart(
                topIndex: 2,
                topDate: edgeDate,
                currentWindowStart: alreadyCentred,
                calendar: calendar
            ) == nil
        )
    }

    /// Scrolling a decade forward one recentre at a time never runs out of rows: after each rebuild
    /// the top row sits back in the middle of the run.
    @Test func scrollingForwardIndefinitelyNeverRunsOutOfRows() {
        var windowStart = CadenceCalendarMonthWindow.windowStart(for: date("2026-08-15"), calendar: calendar)
        var topDate = date("2026-08-15")

        for _ in 0..<12 {
            // Jump 200 rows, which is past the trailing threshold from the middle of the run.
            topDate = calendar.date(byAdding: .day, value: 200 * 7, to: topDate) ?? topDate
            let index = CadenceCalendarMonthWindow.index(for: topDate, windowStart: windowStart, calendar: calendar)
            guard let rebuilt = CadenceCalendarMonthWindow.recenteredWindowStart(
                topIndex: index,
                topDate: topDate,
                currentWindowStart: windowStart,
                calendar: calendar
            ) else {
                Issue.record("the window refused to slide at \(key(topDate))")
                return
            }
            windowStart = rebuilt
            let settled = CadenceCalendarMonthWindow.index(for: topDate, windowStart: windowStart, calendar: calendar)
            #expect(settled == CadenceCalendarMonthWindow.leadingRowCount)
            #expect(settled < CadenceCalendarMonthWindow.renderRowCount - 1)
        }
    }

    // MARK: - What the title says

    /// The trap this whole reading exists for. A six-row window aligned to August 2026 starts on the
    /// week containing **July 26**, so naming the top row would print "July 2026" over a grid that is
    /// plainly August.
    @Test func theDisplayedMonthIsTheOneOnScreenNotTheOneTheTopRowStartsIn() {
        let top = CadenceCalendarMonthWindow.topRow(forMonthContaining: date("2026-08-15"), calendar: calendar)
        #expect(calendar.component(.month, from: top) == 7)
        let displayed = CadenceCalendarMonthWindow.displayedMonth(topRowStart: top, calendar: calendar)
        #expect(DateFormatters.monthYear.string(from: displayed) == "August 2026")
        #expect(
            CadenceCalendarDateTitleSupport.label(for: top, format: .month, calendar: calendar) == "August 2026"
        )
    }

    /// Every month reads as itself when its grid is aligned to the top of the window — which is where
    /// entering Month, picking a date and jumping to today all put it.
    @Test func everyAlignedMonthNamesItself() {
        for month in 1...12 {
            let anyDay = date(String(format: "2026-%02d-15", month))
            let top = CadenceCalendarMonthWindow.topRow(forMonthContaining: anyDay, calendar: calendar)
            let displayed = CadenceCalendarMonthWindow.displayedMonth(topRowStart: top, calendar: calendar)
            #expect(
                calendar.isDate(displayed, equalTo: anyDay, toGranularity: .month),
                "month \(month) read as \(DateFormatters.monthYear.string(from: displayed))"
            )
        }
    }

    /// The day title is unchanged: the leftmost column, blue when it is not today.
    @Test func theDayTitleNamesTheLeadingColumn() {
        let someDay = date("2026-08-07")
        #expect(
            CadenceCalendarDateTitleSupport.label(for: someDay, format: .day, calendar: calendar)
                == DateFormatters.shortDate.string(from: someDay)
        )
        #expect(!CadenceCalendarDateTitleSupport.isAtNow(someDay, format: .day, now: date("2026-08-08"), calendar: calendar))
        #expect(CadenceCalendarDateTitleSupport.isAtNow(someDay, format: .day, now: date("2026-08-07"), calendar: calendar))
    }

    /// "Away from now" is a month for Month and a day for everything else. A month title that went
    /// blue on every day but the 1st would be blue permanently, which says nothing.
    @Test func awayFromNowIsMeasuredInTheUnitTheTitleIsRead() {
        let august = CadenceCalendarMonthWindow.topRow(forMonthContaining: date("2026-08-15"), calendar: calendar)
        #expect(CadenceCalendarDateTitleSupport.isAtNow(august, format: .month, now: date("2026-08-01"), calendar: calendar))
        #expect(CadenceCalendarDateTitleSupport.isAtNow(august, format: .month, now: date("2026-08-31"), calendar: calendar))
        #expect(!CadenceCalendarDateTitleSupport.isAtNow(august, format: .month, now: date("2026-09-01"), calendar: calendar))
        #expect(!CadenceCalendarDateTitleSupport.isAtNow(august, format: .month, now: date("2025-08-15"), calendar: calendar))
    }

    /// Picking a day in the popover scrolls Month to that day's **month**, not to the week it falls
    /// in — and the value written back is a week row the grid can resolve.
    @Test func pickingADayInMonthScrollsToThatMonthsFirstRow() {
        let picked = date("2026-09-23")
        let anchor = CadenceCalendarDateTitleSupport.anchor(forPicked: picked, format: .month, calendar: calendar)
        #expect(key(anchor) == key(CadenceCalendarMonthWindow.topRow(forMonthContaining: picked, calendar: calendar)))
        #expect(
            CadenceCalendarDateTitleSupport.label(for: anchor, format: .month, calendar: calendar) == "September 2026"
        )
    }

    /// Opening the popover and closing it without picking must not move the grid. The seed goes
    /// through `displayedMonth`, and the write-back through `topRow`, so an already-aligned window has
    /// to survive the round trip unchanged.
    @Test func seedingThePickerFromAnAlignedWindowIsAFixedPoint() {
        for monthKey in ["2026-02-15", "2026-08-15", "2026-11-15"] {
            let aligned = CadenceCalendarMonthWindow.topRow(forMonthContaining: date(monthKey), calendar: calendar)
            let seed = CadenceCalendarDateTitleSupport.pickerDate(for: aligned, format: .month, calendar: calendar)
            let back = CadenceCalendarDateTitleSupport.anchor(forPicked: seed, format: .month, calendar: calendar)
            #expect(key(back) == key(aligned), "\(monthKey) drifted to \(key(back))")
        }
    }

    /// The `Today` row is what replaced the toolbar's `location.fill`, so it has to actually land on
    /// now in both units.
    @Test func theTodayShortcutLandsOnNowInBothUnits() {
        let now = date("2026-08-19")
        #expect(key(CadenceCalendarDateTitleSupport.nowAnchor(format: .day, now: now, calendar: calendar)) == "2026-08-19")

        let monthAnchor = CadenceCalendarDateTitleSupport.nowAnchor(format: .month, now: now, calendar: calendar)
        #expect(CadenceCalendarDateTitleSupport.isAtNow(monthAnchor, format: .month, now: now, calendar: calendar))
        #expect(
            CadenceCalendarDateTitleSupport.label(for: monthAnchor, format: .month, calendar: calendar) == "August 2026"
        )
    }

    // MARK: - How a day is drawn

    /// The pairing the month grids had **inverted**: today took the solid fill and the selected day
    /// took the wash, which is the opposite of `MonthCalendarPanel` — the panel behind every date
    /// picker in the app. Two surfaces saying the same two facts in each other's colours.
    @Test func todayAndSelectedTakeTheDatePickersOwnTreatment() {
        #expect(CadenceCalendarDayBadge.style(isToday: false, isSelected: false) == .plain)
        #expect(CadenceCalendarDayBadge.style(isToday: true, isSelected: false) == .today)
        #expect(CadenceCalendarDayBadge.style(isToday: false, isSelected: true) == .selected)
        #expect(CadenceCalendarDayBadge.style(isToday: true, isSelected: true) == .todayAndSelected)

        #expect(CadenceCalendarDayBadge.today.fill == .wash)
        #expect(CadenceCalendarDayBadge.today.label == .accent)
        #expect(CadenceCalendarDayBadge.selected.fill == .solid)
        #expect(CadenceCalendarDayBadge.selected.label == .onFill)
        #expect(CadenceCalendarDayBadge.plain.fill == .none)
        #expect(CadenceCalendarDayBadge.plain.label == .normal)
        // `MonthCalendarPanel` draws today at 0.15 of `Theme.blue`. One number, named once.
        #expect(CadenceCalendarDayBadge.washOpacity == 0.15)
    }

    /// Today-and-selected has to be distinguishable from **either** alone. Both it and a plain
    /// selection take the solid fill, so the ring is the whole of what separates them — and a grid
    /// where selecting today made the today marker vanish would have lost a fact rather than
    /// combined two.
    @Test func todayStaysVisibleWhenItIsAlsoTheSelectedDay() {
        #expect(CadenceCalendarDayBadge.todayAndSelected.showsTodayRing)
        for badge in CadenceCalendarDayBadge.allCases where badge != .todayAndSelected {
            #expect(!badge.showsTodayRing, "\(badge) drew the today ring")
        }

        // The four states are pairwise distinct in what they actually draw.
        let drawn = CadenceCalendarDayBadge.allCases.map { [$0.fill.hashValue, $0.label.hashValue, $0.showsTodayRing ? 1 : 0] }
        #expect(Set(drawn.map { "\($0)" }).count == CadenceCalendarDayBadge.allCases.count)
    }

    /// Only a resting day is drawn at ordinary weight; the other three are emphasized. `.plain` being
    /// the sole exception is what keeps a month of neighbours from all looking marked.
    @Test func onlyARestingDayIsDrawnAtOrdinaryWeight() {
        #expect(!CadenceCalendarDayBadge.plain.isEmphasized)
        #expect(CadenceCalendarDayBadge.today.isEmphasized)
        #expect(CadenceCalendarDayBadge.selected.isEmphasized)
        #expect(CadenceCalendarDayBadge.todayAndSelected.isEmphasized)
    }

    // MARK: - Events

    /// The fetch window is keyed on the displayed month, so it must cover **every** row position that
    /// reads as that month, plus the six rows visible from it. Miss that and the grid draws days with
    /// no events on them at scroll positions the key does not change at — which looks like the events
    /// being gone, not like a fetch window being short.
    @Test func theEventWindowCoversEveryRowThatReadsAsItsMonth() {
        let month = date("2026-08-15")
        let windowKeys = Set(
            CadenceCalendarMonthWindow.eventWindowDates(displayedMonth: month, calendar: calendar).map(key)
        )
        let aligned = CadenceCalendarMonthWindow.topRow(forMonthContaining: month, calendar: calendar)

        for rowOffset in -6...6 {
            let top = calendar.date(byAdding: .day, value: rowOffset * 7, to: aligned) ?? aligned
            let displayed = CadenceCalendarMonthWindow.displayedMonth(topRowStart: top, calendar: calendar)
            guard calendar.isDate(displayed, equalTo: month, toGranularity: .month) else { continue }

            let visibleDays = CadenceCalendarMonthWindow.visibleRowCount * CadenceCalendarMonthWindow.daysPerRow
            for dayOffset in 0..<visibleDays {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: top) ?? top
                #expect(windowKeys.contains(key(day)), "\(key(day)) was on screen with no events fetched for it")
            }
        }
    }

    /// And it is bounded: a window that grew with the scroll would be a per-week EventKit sweep,
    /// which is the cost `eventWindowKey` was made coarse to avoid.
    @Test func theEventWindowIsAFixedSpan() {
        for monthKey in ["2026-02-15", "2026-08-15", "2027-01-15"] {
            #expect(
                CadenceCalendarMonthWindow.eventWindowDates(displayedMonth: date(monthKey), calendar: calendar).count
                    == CadenceCalendarMonthWindow.eventWindowRowCount * CadenceCalendarMonthWindow.daysPerRow
            )
        }
    }
}
