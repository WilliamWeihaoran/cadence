import Foundation
import Testing
@testable import Cadence

#if os(macOS)
/// [[T-5352]]: the Mac Calendar measured its Day/Week buffer and its month grid from `Date()` on
/// every body pass, and the page re-renders at the day change — so a window left open across
/// midnight slid every column forward a day (and every month block forward a month at a month
/// change) under a scroll offset that stayed put. The page now holds the day it was opened on.
@Suite
struct CalendarPageMidnightAnchorTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test
    func aColumnKeepsItsDateAcrossMidnightAndTodayIsWhatMoves() {
        let opened = day(2026, 10, 18, hour: 23)
        let bufferStart = CalendarPageDataSupport.bufferStart(calendar: calendar, anchorDay: opened)
        let todayAtOpen = CalendarPageDataSupport.todayDayIndex(bufferStart: bufferStart, calendar: calendar, today: opened)
        #expect(todayAtOpen == 1825)

        // One minute past midnight: the same buffer, so column 1825 is still Oct 18 …
        let afterMidnight = day(2026, 10, 19, hour: 0).addingTimeInterval(60)
        let column = calendar.date(byAdding: .day, value: todayAtOpen, to: bufferStart)!
        #expect(calendar.isDate(column, inSameDayAs: day(2026, 10, 18)))
        // … and today is the next column, not the same index re-dated.
        let todayAfter = CalendarPageDataSupport.todayDayIndex(bufferStart: bufferStart, calendar: calendar, today: afterMidnight)
        #expect(todayAfter == todayAtOpen + 1)
    }

    @Test
    func todaysMonthBlockIsCountedFromTheHeldMonthAfterAMonthChange() {
        let held = CalendarMonthGridSupport.currentMonthStart(calendar: calendar, reference: day(2026, 10, 31, hour: 23))
        let nextMorning = day(2026, 11, 18)
        let anchored = CalendarPageStateSupport.monthIndexForToday(
            calendar: calendar,
            today: nextMorning,
            currentMonthStart: held
        )
        #expect(anchored == CalendarPageStateSupport.todayMonthIndex + 1,
                "the Today jump aimed at the block the grid draws October in")
    }

    @Test
    func theMonthTitleNamesTheHeldMonthsBlock() {
        // A month far from the clock's, so a label read from `Date()` cannot pass by coincidence.
        let held = CalendarMonthGridSupport.currentMonthStart(calendar: calendar, reference: day(2025, 3, 15))
        let label = CalendarPageStateSupport.visibleMonthLabel(
            visibleMonthIdx: CalendarPageStateSupport.todayMonthIndex,
            calendar: calendar,
            currentMonthStart: held
        )
        #expect(label == DateFormatters.monthYear.string(from: day(2025, 3, 15)))
    }

    /// The page and the grid read the held anchor, never the clock.
    @Test
    func thePageAndTheGridHoldTheirAnchor() throws {
        let page = try #require(CadenceSourceScan.declarationBody(
            "struct CalendarPageView",
            in: try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageView.swift")
        ))
        #expect(page.contains("@State private var calendarAnchorDay = Calendar.current.startOfDay(for: Date())"))
        #expect(page.contains("CalendarPageDataSupport.bufferStart(calendar: cal, anchorDay: calendarAnchorDay)"))
        #expect(page.contains("currentMonthStart: monthAnchorStart"))
        #expect(!page.contains("CalendarMonthGridSupport.currentMonthStart(calendar: cal)"),
                "the page still reads the month of now")
        #expect(!page.contains("monthIndexForToday(calendar: cal)"))

        let grid = try #require(CadenceSourceScan.declarationBody(
            "struct MonthGridView",
            in: try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageComponents.swift")
        ))
        #expect(grid.contains("let currentMonthStart: Date"))
        #expect(!grid.contains("CalendarMonthGridSupport.currentMonthStart(calendar: cal)"))
    }
}
#endif
