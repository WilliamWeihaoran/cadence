import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// [[T-11731]] / [[T-12150]]: the touch month grid pages one month on a horizontal swipe, and a tap
/// on a greyed neighbouring-month day moves the grid to that day's month.
///
/// The fixture is **December 2026**, the month the ticket measured: Dec 1 2026 is a Tuesday, so
/// the grid opens on Sunday Nov 29 and carries Jan 1–2 2027 in its last row; Jan 3 is the greyed
/// day the ticket tapped.
@MainActor
struct CalendarMonthPagingTests {

    private static func gridCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    // MARK: - What a release means

    @Test func aLongLeftSwipePagesToTheNextMonth() {
        let direction = CadenceCalendarMonthPaging.pageDirection(
            translation: CGSize(width: -210, height: 6),
            horizontalVelocity: 0,
            contentOverflowsWidth: false
        )
        #expect(direction == .next)
    }

    @Test func aLongRightSwipePagesToThePreviousMonth() {
        let direction = CadenceCalendarMonthPaging.pageDirection(
            translation: CGSize(width: 240, height: -10),
            horizontalVelocity: 0,
            contentOverflowsWidth: false
        )
        #expect(direction == .previous)
    }

    /// The vertical half of the arbitration: a release that is mostly vertical is a scroll, however
    /// far it also travelled sideways.
    @Test func aMostlyVerticalDragDoesNotPage() {
        let direction = CadenceCalendarMonthPaging.pageDirection(
            translation: CGSize(width: -80, height: 200),
            horizontalVelocity: -900,
            contentOverflowsWidth: false
        )
        #expect(direction == nil)
    }

    /// A short drag pages only when it is flicked, and only a flick in the direction it travelled.
    @Test func aShortDragPagesOnlyOnAFlickThatAgreesWithIt() {
        let short = CGSize(width: -30, height: 0)
        #expect(CadenceCalendarMonthPaging.commitDistance > abs(short.width))
        #expect(CadenceCalendarMonthPaging.pageDirection(
            translation: short, horizontalVelocity: 0, contentOverflowsWidth: false
        ) == nil)
        #expect(CadenceCalendarMonthPaging.pageDirection(
            translation: short, horizontalVelocity: -900, contentOverflowsWidth: false
        ) == .next)
        #expect(CadenceCalendarMonthPaging.pageDirection(
            translation: short, horizontalVelocity: 900, contentOverflowsWidth: false
        ) == nil)
    }

    /// The commit distance sits past the axis claim, so a drag only just read as horizontal is not
    /// yet a page. A relation, not a figure.
    @Test func theCommitDistanceIsPastTheAxisClaimDistance() {
        #expect(CadenceCalendarMonthPaging.commitDistance > CadenceSwipeActionMetrics.standard.claimDistance)
    }

    /// At very large text the grid is wider than its pane and scrolls sideways; there a horizontal
    /// drag reveals the clipped columns and never pages.
    @Test func aGridWiderThanItsPaneNeverPages() {
        let direction = CadenceCalendarMonthPaging.pageDirection(
            translation: CGSize(width: -260, height: 0),
            horizontalVelocity: -1200,
            contentOverflowsWidth: true
        )
        #expect(direction == nil)
    }

    // MARK: - Where a page lands

    @Test func pagingFromDecemberLandsOnTheTopRowOfJanuaryAndNovember() throws {
        let calendar = Self.gridCalendar()
        let decemberTop = CadenceCalendarMonthWindow.topRow(forMonthContaining: try Self.day(2026, 12, 1, calendar), calendar: calendar)
        #expect(decemberTop == (try Self.day(2026, 11, 29, calendar)))

        let next = CadenceCalendarMonthPaging.topRow(paging: .next, fromTopRow: decemberTop, calendar: calendar)
        #expect(next == CadenceCalendarMonthWindow.topRow(forMonthContaining: try Self.day(2027, 1, 1, calendar), calendar: calendar))
        #expect(calendar.component(.month, from: CadenceCalendarMonthWindow.displayedMonth(topRowStart: next, calendar: calendar)) == 1)

        let previous = CadenceCalendarMonthPaging.topRow(paging: .previous, fromTopRow: decemberTop, calendar: calendar)
        #expect(previous == CadenceCalendarMonthWindow.topRow(forMonthContaining: try Self.day(2026, 11, 1, calendar), calendar: calendar))
    }

    /// Paging reads the month the grid is *showing*, not the top row's own month: December's grid
    /// opens on a November row, and "previous" from it is November, not October.
    @Test func pagingReadsTheDisplayedMonthNotTheTopRowsOwnMonth() throws {
        let calendar = Self.gridCalendar()
        let decemberTop = try Self.day(2026, 11, 29, calendar)
        let previous = CadenceCalendarMonthPaging.topRow(paging: .previous, fromTopRow: decemberTop, calendar: calendar)
        let shown = CadenceCalendarMonthWindow.displayedMonth(topRowStart: previous, calendar: calendar)
        #expect(calendar.component(.month, from: shown) == 11)
        #expect(calendar.component(.year, from: shown) == 2026)
    }

    // MARK: - A tap on a greyed day

    @Test func tappingAGreyedNextMonthDayMovesTheGridToThatMonth() throws {
        let calendar = Self.gridCalendar()
        let december = try Self.day(2026, 12, 18, calendar)
        let january3 = try Self.day(2027, 1, 3, calendar)
        let top = try #require(CadenceCalendarMonthPaging.topRowFollowingSelection(of: january3, displayMonth: december, calendar: calendar))
        #expect(top == CadenceCalendarMonthWindow.topRow(forMonthContaining: january3, calendar: calendar))
    }

    @Test func tappingAGreyedPreviousMonthDayMovesTheGridToThatMonth() throws {
        let calendar = Self.gridCalendar()
        let december = try Self.day(2026, 12, 18, calendar)
        let november30 = try Self.day(2026, 11, 30, calendar)
        let top = try #require(CadenceCalendarMonthPaging.topRowFollowingSelection(of: november30, displayMonth: december, calendar: calendar))
        #expect(top == CadenceCalendarMonthWindow.topRow(forMonthContaining: november30, calendar: calendar))
    }

    @Test func tappingADayOfTheShownMonthLeavesTheGridWhereItIs() throws {
        let calendar = Self.gridCalendar()
        let december = try Self.day(2026, 12, 18, calendar)
        #expect(CadenceCalendarMonthPaging.topRowFollowingSelection(of: try Self.day(2026, 12, 31, calendar), displayMonth: december, calendar: calendar) == nil)
        #expect(CadenceCalendarMonthPaging.topRowFollowingSelection(of: try Self.day(2026, 12, 1, calendar), displayMonth: december, calendar: calendar) == nil)
    }
}
