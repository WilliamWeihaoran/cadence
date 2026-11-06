import CoreGraphics
import Foundation

/// Which way a month-grid swipe pages.
nonisolated enum CadenceCalendarMonthPageDirection: Int, Equatable {
    case previous = -1
    case next = 1
}

/// The two ways the touch month grid changes month besides scrolling it ([[T-11731]]).
///
/// The iPhone's Month used to change month only through the date-label picker, or by scrolling the
/// rows vertically past the turn of the month: a horizontal swipe did nothing, and a tap on a greyed
/// day of the neighbouring month selected it and left the grid where it was, so the day you had
/// just picked was drawn as a carried day of a month you were not reading. [[T-12150]] ruled both:
///
/// - **A horizontal swipe pages one month** — left is the next month, right the previous — on the
///   touch grid only. The Mac gets no swipe: it has a pointer and a keyboard, and its month cell
///   leaves the grid for the timeline on a click, which is the hardware reason [[T-8201]] asks for.
///   The Week surface's horizontal pan ([[T-8921]]) is a different surface and is not this.
/// - **A tap on a greyed adjacent-month day selects it and moves the grid to its month.** The Mac
///   already follows such a click — it opens the day in Week — so it needs no change.
///
/// In `Shared/` because `Cadence/iOS/` is behind `#if os(iOS)` and invisible to the macOS-built
/// `CadenceTests`. The axis arbitration that decides whether the grid may take a drag at all is
/// `CadenceSwipeActionSupport.axisClaim`, enforced by `iOSRowHorizontalPanRecognizer`; this only
/// decides what a drag that was handed to the grid *means* on release.
///
/// Main-actor (the target default), not `nonisolated`, because `CadenceCalendarMonthWindow` is.
enum CadenceCalendarMonthPaging {
    /// How far a release has to have travelled horizontally to page without a flick. Past the axis
    /// recognizer's own claim distance, so a drag that has only just been read as horizontal is not
    /// yet a page.
    static let commitDistance: CGFloat = 56

    /// What releasing a horizontal drag over the month grid does: page one way, or nothing.
    ///
    /// - `contentOverflowsWidth`: the grid is wider than its pane (very large text), so a sideways
    ///   drag belongs to the horizontal scroll view that reveals the clipped columns, never to paging.
    /// - The drag must still be horizontal by the same ratio the axis claim used — a release that
    ///   ended up mostly vertical is a scroll that wandered, not a swipe.
    /// - It commits on distance, or on a flick in the direction it travelled.
    static func pageDirection(
        translation: CGSize,
        horizontalVelocity: CGFloat,
        contentOverflowsWidth: Bool,
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> CadenceCalendarMonthPageDirection? {
        guard !contentOverflowsWidth else { return nil }
        guard CadenceSwipeActionSupport.isHorizontal(translation: translation, metrics: metrics) else { return nil }
        let dx = translation.width
        let travelled = abs(dx) >= commitDistance
        let flicked = abs(horizontalVelocity) >= metrics.velocityCommit && (horizontalVelocity < 0) == (dx < 0)
        guard travelled || flicked else { return nil }
        return dx < 0 ? .next : .previous
    }

    /// The top row to scroll to after paging `direction` from a grid whose top row is `topRowStart`.
    ///
    /// Read from the month the grid is *showing* (`CadenceCalendarMonthWindow.displayedMonth`), not
    /// the top row's own month: a window aligned to August opens on the week of July 27, and paging
    /// "back one" from there must land on July, not June.
    static func topRow(
        paging direction: CadenceCalendarMonthPageDirection,
        fromTopRow topRowStart: Date,
        calendar: Calendar = .current
    ) -> Date {
        let shown = CadenceCalendarMonthWindow.displayedMonth(topRowStart: topRowStart, calendar: calendar)
        let target = calendar.date(byAdding: .month, value: direction.rawValue, to: shown) ?? shown
        return CadenceCalendarMonthWindow.topRow(forMonthContaining: target, calendar: calendar)
    }

    /// The top row to move the grid to after the user selects `date` while it reads as
    /// `displayMonth`, or `nil` when the day is already in the month on screen.
    static func topRowFollowingSelection(
        of date: Date,
        displayMonth: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard !calendar.isDate(date, equalTo: displayMonth, toGranularity: .month) else { return nil }
        return CadenceCalendarMonthWindow.topRow(forMonthContaining: date, calendar: calendar)
    }
}
