#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-3140, the board half — the macOS Calendar Board reads the page's observed day.**
///
/// `CalendarPageView` already holds a `CadenceObservedDay` and hands its key to the month grid and
/// the timeline viewport. The board was the one presentation still reading the clock itself: its
/// rails (`railTasks`) and each day column's amber "today" accent (`isToday`) called
/// `DateFormatters.todayKey()` during `body`, and nothing re-ran `body` at midnight. And because
/// the board's window is floored at today, the day that just ended stayed on screen as column 0
/// while its cards also moved into the Overdue rail.
///
/// The rail and accent halves are wiring, so they are pinned at the source; the re-floor decision
/// is a function, so it is pinned by behaviour. No test here moves `NSTimeZone.default`: every
/// calendar is built with an explicit zone.
@MainActor
struct CalendarBoardObservedDayTests {
    private func readCode(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    private static let viewsPrefix = "Cadence/macOS/Views/"

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    @Test func thePageHandsTheBoardItsObservedDay() throws {
        let source = try readCode(Self.viewsPrefix + "CalendarPageView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct CalendarPageView", in: source))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: page))
        #expect(body.contains("CalendarPageBoardView(\n                    todayKey: observedDay.todayKey,"))
    }

    @Test func theBoardReadsNoClockForTodayAndForwardsTheKeyToItsRailsAndColumns() throws {
        let source = try readCode(Self.viewsPrefix + "CalendarPageBoardSupportViews.swift")
        let board = try #require(CadenceSourceScan.declarationBody("struct CalendarPageBoardView", in: source))
        #expect(board.contains("let todayKey: String"))
        #expect(!board.contains("DateFormatters.todayKey()"))
        #expect(board.contains("CalendarBoardPlannerSupport.railTasks(from: allTasks, todayKey: todayKey)"))
        #expect(board.contains("dateKey: dateKey,\n                            todayKey: todayKey,"))
        // The window re-floors when the observed day moves, through the tested decision below.
        #expect(board.contains(".onChange(of: todayKey)"))
        #expect(board.contains("Self.windowNeedsRefloor("))
    }

    @Test func theDayColumnsTodayAccentComparesAgainstTheHandedDownKey() throws {
        let source = try readCode(Self.viewsPrefix + "CalendarBoardDayColumnSupportViews.swift")
        let column = try #require(CadenceSourceScan.declarationBody("struct CalendarBoardDayColumn", in: source))
        #expect(column.contains("let todayKey: String"))
        #expect(column.contains("dateKey == todayKey"))
        #expect(!column.contains("DateFormatters.todayKey()"))
    }

    @Test func aWindowLaidOutYesterdayNeedsRefloorWhenTheDayTurns() throws {
        let calendar = Self.calendar("America/New_York")
        let yesterdayStart = try #require(DateFormatters.date(from: "2026-10-20", in: calendar))
        // Laid out at 23:59 the night before — the time of day must not matter, only the day.
        let lateYesterday = yesterdayStart.addingTimeInterval(23 * 3600 + 59 * 60)
        #expect(CalendarPageBoardView.windowNeedsRefloor(
            windowStart: lateYesterday, todayKey: "2026-10-21", calendar: calendar
        ))
        #expect(CalendarPageBoardView.windowNeedsRefloor(
            windowStart: yesterdayStart, todayKey: "2026-10-21", calendar: calendar
        ))
    }

    @Test func aWindowAlreadyAtOrPastTodayIsLeftAlone() throws {
        let calendar = Self.calendar("America/New_York")
        let todayStart = try #require(DateFormatters.date(from: "2026-10-21", in: calendar))
        let future = try #require(DateFormatters.date(from: "2026-11-02", in: calendar))
        // Floored exactly at today: the relation is strict, so the user's scroll is not reset.
        #expect(!CalendarPageBoardView.windowNeedsRefloor(
            windowStart: todayStart, todayKey: "2026-10-21", calendar: calendar
        ))
        #expect(!CalendarPageBoardView.windowNeedsRefloor(
            windowStart: todayStart.addingTimeInterval(3600), todayKey: "2026-10-21", calendar: calendar
        ))
        #expect(!CalendarPageBoardView.windowNeedsRefloor(
            windowStart: future, todayKey: "2026-10-21", calendar: calendar
        ))
    }

    @Test func noWindowYetOrAnUnreadableKeyIsNotARefloor() throws {
        let calendar = Self.calendar("America/New_York")
        let past = try #require(DateFormatters.date(from: "2026-01-01", in: calendar))
        #expect(!CalendarPageBoardView.windowNeedsRefloor(
            windowStart: nil, todayKey: "2026-10-21", calendar: calendar
        ))
        #expect(!CalendarPageBoardView.windowNeedsRefloor(
            windowStart: past, todayKey: "not-a-key", calendar: calendar
        ))
    }

    @Test func theDayIsReadInTheCalendarsOwnZone() throws {
        // 2026-10-21 02:00 in Tokyo is still 2026-10-20 in New York. Measured in Tokyo, a window
        // starting then is today; measured in New York it is yesterday. The key must be parsed in
        // the same calendar the window is measured in, or one of these two answers flips.
        let tokyo = Self.calendar("Asia/Tokyo")
        let newYork = Self.calendar("America/New_York")
        let tokyoEarly = try #require(DateFormatters.date(from: "2026-10-21", in: tokyo)).addingTimeInterval(2 * 3600)
        #expect(!CalendarPageBoardView.windowNeedsRefloor(
            windowStart: tokyoEarly, todayKey: "2026-10-21", calendar: tokyo
        ))
        #expect(CalendarPageBoardView.windowNeedsRefloor(
            windowStart: tokyoEarly, todayKey: "2026-10-21", calendar: newYork
        ))
        // Far west of the host: parsed in the system zone instead, "2026-10-21" would land on the
        // 20th in Honolulu and the window laid out on the 20th would wrongly look current.
        let honolulu = Self.calendar("Pacific/Honolulu")
        let honoluluEvening = try #require(DateFormatters.date(from: "2026-10-20", in: honolulu)).addingTimeInterval(20 * 3600)
        #expect(CalendarPageBoardView.windowNeedsRefloor(
            windowStart: honoluluEvening, todayKey: "2026-10-21", calendar: honolulu
        ))
    }
}
#endif
