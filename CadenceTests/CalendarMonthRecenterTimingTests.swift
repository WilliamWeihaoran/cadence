import Foundation
import Testing
@testable import Cadence

/// **When** the iOS month grid is allowed to rebuild its window, as opposed to whether it is owed
/// one.
///
/// Recentring is the most expensive thing that grid does: it reassigns `windowStart`, which re-dates
/// every one of the 420 rows in the lazy stack, and then writes the scroll position to the row's new
/// index. Performed inside a scroll callback that is what a stutter is — SwiftUI relaying out the
/// whole stack and having its scroll position reassigned underneath live momentum.
///
/// The gate is `ScrollPhase.isScrolling`, a **signal** the scroll view reports, not a delay standing
/// in for one. `CadenceLazyScrollAnchor` records what the delay cost when this repo tried it
/// (`ecaf80f`: a 0.08s guard that expired before the settle arrived and wrote a garbage day into
/// persisted state), and the same objection would apply to a timer here.
///
/// Deferring cannot be unconditional. A deferral that is never redeemed leaves the grid parked
/// against the end of a finite run of rows, where a scroll stops dead at a date nobody chose, so
/// inside `hardEdgeRowCount` of either end the recentre happens mid-gesture and the hitch is the
/// better of the two outcomes.
@MainActor
struct CalendarMonthRecenterTimingTests {

    private let renderRows = CadenceCalendarMonthWindow.renderRowCount
    private let visibleRows = CadenceCalendarMonthWindow.visibleRowCount
    private let anchorRow = CadenceCalendarMonthWindow.leadingRowCount

    /// The fling case, which is the bug. A grid resting where it opens — the middle of its window —
    /// is nowhere near the recentre threshold, so however fast the scroll, no row it crosses can
    /// ask for a window rebuild.
    @Test func aFlingFromTheMiddleOfTheWindowNeverRecentres() {
        // The soft threshold is 42 rows from either end of 420; the anchor sits at 210. A fling
        // covers a handful of rows, and the whole band around the anchor answers `.none`.
        for offset in -60...60 {
            let index = anchorRow + offset
            #expect(
                CadenceCalendarMonthWindow.recenterTiming(topIndex: index, isScrolling: true) == .none,
                "row \(index) asked to recentre mid-fling"
            )
            #expect(CadenceCalendarMonthWindow.recenterTiming(topIndex: index, isScrolling: false) == .none)
        }
    }

    /// Deep into the run, where a recentre genuinely is owed: a live scroll defers it, and only a
    /// live scroll does. This is the pair the fix turns on.
    @Test func anOwedRecentreWaitsWhileTheScrollIsLiveAndHappensWhenItStops() {
        // Just inside the leading band, with plenty of runway left before row 0.
        let leading = CalendarBoardPlannerSupport.plannerRecenterThreshold
        #expect(CadenceCalendarMonthWindow.recenterTiming(topIndex: leading, isScrolling: true) == .whenScrollSettles)
        #expect(CadenceCalendarMonthWindow.recenterTiming(topIndex: leading, isScrolling: false) == .now)

        // And the same at the trailing end.
        let trailing = renderRows - CalendarBoardPlannerSupport.plannerRecenterThreshold - 1
        #expect(CadenceCalendarMonthWindow.recenterTiming(topIndex: trailing, isScrolling: true) == .whenScrollSettles)
        #expect(CadenceCalendarMonthWindow.recenterTiming(topIndex: trailing, isScrolling: false) == .now)
    }

    /// The other half of "wait for a signal": a wait that is never redeemed is worse than a hitch.
    /// Against either end of the run the recentre goes through mid-scroll.
    @Test func aScrollAboutToRunOutOfRowsRecentresWithoutWaiting() {
        for index in 0...CadenceCalendarMonthWindow.hardEdgeRowCount {
            #expect(
                CadenceCalendarMonthWindow.recenterTiming(topIndex: index, isScrolling: true) == .now,
                "row \(index) deferred a recentre with no runway left"
            )
        }

        let lastTopRow = renderRows - visibleRows
        for index in (lastTopRow - CadenceCalendarMonthWindow.hardEdgeRowCount)...lastTopRow {
            #expect(
                CadenceCalendarMonthWindow.recenterTiming(topIndex: index, isScrolling: true) == .now,
                "row \(index) deferred a recentre with no runway left"
            )
        }
    }

    /// Runway is measured to the last row that can *become* the top row, not to the last row that
    /// exists. The final `visibleRowCount` rows fill the viewport under the top row and can never
    /// be scrolled to, so counting them would promise a screenful of scrolling that is not there.
    @Test func runwayIsMeasuredAgainstTheLastRowThatCanBeTheTopRow() {
        let lastTopRow = renderRows - visibleRows
        #expect(CadenceCalendarMonthWindow.rowsOfRunway(topIndex: lastTopRow) == 0)
        #expect(CadenceCalendarMonthWindow.rowsOfRunway(topIndex: 0) == 0)
        #expect(CadenceCalendarMonthWindow.rowsOfRunway(topIndex: lastTopRow - 5) == 5)
        // The anchor sits at 210 of 420, so the shorter side is the trailing one: 414 - 210.
        #expect(CadenceCalendarMonthWindow.rowsOfRunway(topIndex: anchorRow) == lastTopRow - anchorRow)
        #expect(lastTopRow - anchorRow > CalendarBoardPlannerSupport.plannerRecenterThreshold)
        // Past the end clamps to nothing rather than going negative and reading as runway.
        #expect(CadenceCalendarMonthWindow.rowsOfRunway(topIndex: renderRows) == 0)
    }

    /// A deferral is redeemable: every index that answers `.whenScrollSettles` answers `.now` for
    /// the same index once the scroll stops. Nothing can be owed a recentre and never get one.
    @Test func everyDeferralIsRedeemedOnTheSettle() {
        for index in 0..<renderRows {
            if CadenceCalendarMonthWindow.recenterTiming(topIndex: index, isScrolling: true) == .whenScrollSettles {
                #expect(CadenceCalendarMonthWindow.recenterTiming(topIndex: index, isScrolling: false) == .now)
            }
        }
    }

    /// Timing says when; `recenteredWindowStart` still says whether there is anywhere to move to.
    /// A window already centred on the top row is a no-op in both, so a settle cannot re-scroll a
    /// grid that is where it should be.
    @Test func timingDoesNotOverrideTheNoOpGuard() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1

        let anchor = try #require(DateFormatters.date(from: "2026-08-15", in: calendar))
        let edgeIndex = CalendarBoardPlannerSupport.plannerRecenterThreshold
        let start = CadenceCalendarMonthWindow.windowStart(for: anchor, calendar: calendar)
        let edgeDate = CadenceCalendarMonthWindow.date(at: edgeIndex, windowStart: start, calendar: calendar)

        // Owed, and there is somewhere to go.
        #expect(CadenceCalendarMonthWindow.recenterTiming(topIndex: edgeIndex, isScrolling: false) == .now)
        #expect(
            CadenceCalendarMonthWindow.recenteredWindowStart(
                topIndex: edgeIndex,
                topDate: edgeDate,
                currentWindowStart: start,
                calendar: calendar
            ) != nil
        )

        // Owed, but the window is already built around this row: nothing to do.
        let alreadyCentred = CadenceCalendarMonthWindow.windowStart(for: edgeDate, calendar: calendar)
        #expect(
            CadenceCalendarMonthWindow.recenteredWindowStart(
                topIndex: edgeIndex,
                topDate: edgeDate,
                currentWindowStart: alreadyCentred,
                calendar: calendar
            ) == nil
        )
    }
}
