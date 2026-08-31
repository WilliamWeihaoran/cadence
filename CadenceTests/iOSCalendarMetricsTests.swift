import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// The calendar was the last big iPhone/iPad divergence in `Cadence/iOS/`: the timed grid, the
/// toolbar and the Board carried thirty-odd `horizontalSizeClass` branches between them, and most of
/// them were the same figure written twice — an 11pt weekday label against a 10pt one, a 36pt day
/// circle against a 32, a chip strip inset 7 against 5, a toolbar band padded *more* on the phone
/// than on the iPad.
///
/// `Cadence/iOS/` sits inside `#if os(iOS)` and is invisible to this macOS-built target, which is
/// why `iOSCalendarMetrics.swift` sits outside the platform guard: what is worth pinning is the
/// decisions, and a decision that only exists inside a view body can be quietly re-ramped. These
/// tests say which figures may vary with width and which may not.
///
/// **Deliberately not `@MainActor`** — every type under test is `nonisolated`, and the comparisons
/// run in the nonisolated closure swift-testing expands to, so dropping that marking would re-emit
/// the isolated-conformance error rather than pass quietly. Same reasoning as
/// `iOSTaskCollectionMetricsTests`.
struct iOSCalendarMetricsTests {
    private static let widths = [true, false]

    // MARK: - The page gutter: the one ramp the calendar keeps

    /// The calendar had two gutters — 18/16 on the toolbar and 20/14 on the Board — for one screen,
    /// so its top row and the columns under it did not share a left edge at either width. There is
    /// one now, and it is not the calendar's: it is the page gutter `iOSPageHeader` already uses,
    /// which is what All Tasks, Inbox and Today are inset by.
    @Test func theCalendarIsInsetByThePageGutterAndNotAGutterOfItsOwn() {
        for isRegular in Self.widths {
            let page = CadencePageHeaderMetrics.metrics(role: .page, isRegularWidth: isRegular)

            #expect(
                iOSCalendarPageMetrics.horizontalPadding(isRegularWidth: isRegular)
                    == page.horizontalPadding,
                "calendar gutter at isRegular=\(isRegular)"
            )
            #expect(
                iOSCalendarBoardMetrics.horizontalPadding(isRegularWidth: isRegular)
                    == iOSCalendarPageMetrics.horizontalPadding(isRegularWidth: isRegular),
                "board gutter at isRegular=\(isRegular)"
            )
        }
    }

    /// And it is a real ramp — the point of keeping it is that a wider pane genuinely takes a wider
    /// margin, not that the figure was left alone.
    @Test func thePageGutterIsWiderOnAWiderHost() {
        #expect(
            iOSCalendarPageMetrics.horizontalPadding(isRegularWidth: true)
                > iOSCalendarPageMetrics.horizontalPadding(isRegularWidth: false)
        )
    }

    // MARK: - The timed grid

    /// Today's timeline (`iOSSchedulePanel`) and the Calendar's day columns draw the same
    /// `iOSTimelineTaskBlock`. The grid's hour was `regular ? 64 : 58` against Today's flat 58, so
    /// the same scheduled task occupied a different number of points on the two timed surfaces of a
    /// single iPad. This is the number that made them agree; `iOSSchedulePanel.rowHeight` is the
    /// other half and cannot be read from here.
    @Test func anHourIsOneHeightOnEveryTimedSurface() {
        #expect(iOSCalendarTimelineMetrics.hourHeight == 58)
    }

    /// A day column is at least `preferredDayColumnWidth` — 104pt — at *both* widths, which is what
    /// makes the day header's ramps unforced: nothing in the band was ever competing for room. If
    /// that floor ever drops below the circle plus its column insets, the band's figures need
    /// revisiting rather than silently overflowing.
    @Test func aDayColumnHasRoomForItsHeaderAtBothWidths() {
        for isRegular in Self.widths {
            let column = CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: isRegular)
            let needed = iOSCalendarTimelineMetrics.dayCircleSize
                + iOSCalendarTimelineMetrics.previewInset * 2

            #expect(column > needed, "column \(column) at isRegular=\(isRegular)")
        }
    }

    /// The band the day headers fill, the rail reserves, and the initial scroll placement clears.
    ///
    /// It was a hand-set `112 : 101` against content needing 105 at its own numbers, so the phone's
    /// header overflowed its reserved height on every column and the chip strip never got the 42pt
    /// it asks for. Derived, that cannot recur — this is the arithmetic, restated, so a part cannot
    /// grow without the band following it.
    @Test func theDayHeaderBandIsTallEnoughForWhatIsInIt() {
        typealias Grid = iOSCalendarTimelineMetrics

        #expect(
            Grid.dayHeaderHeight
                == Grid.dateBlockHeight + Grid.previewMinHeight + Grid.previewInset
        )
        #expect(
            Grid.dateBlockHeight
                >= Grid.weekdayLineHeight + Grid.dayLabelSpacing + Grid.dayCircleSize
        )
    }

    /// **T-588: the read that `hourHeight`'s doc used to only claim.**
    ///
    /// Today's timeline (`iOSSchedulePanel`, in `iOSTodaySchedulePanel.swift`) is inside
    /// `#if os(iOS)` and cannot be referenced from this macOS-built target, so
    /// `anHourIsOneHeightOnEveryTimedSurface` above can only pin *this* file's 58 and says so in
    /// its own doc — "`iOSSchedulePanel.rowHeight` is the other half and cannot be read from
    /// here". That is precisely how the other half came to be a second hand-typed literal, with
    /// three figures duplicated and one of them (the trailing inset, 9 against 8) already drifted.
    ///
    /// A reference cannot be pinned by a value comparison the target cannot compile, so this pins
    /// the *text*: the panel names this type for all three, and holds no bare literal that a
    /// fourth copy would have to be spelled as. Comments are blanked first — `strippingComments`
    /// and not `codeOnly`, because `codeOnly` blanks string literals too and half of what is being
    /// searched for here is prose-adjacent.
    @Test func theTodayTimelineReadsItsHourFiguresFromHere() throws {
        let panel = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodaySchedulePanel.swift")
        )

        // Non-vacuity: the read reached the right file, and the comment stripper left the code.
        #expect(panel.contains("struct iOSSchedulePanel: View"))
        #expect(panel.contains("private var rowHeight: CGFloat"))

        #expect(panel.contains("iOSCalendarTimelineMetrics.hourHeight"))
        #expect(panel.contains("iOSCalendarTimelineMetrics.hourLabelSize"))
        #expect(panel.contains("iOSCalendarTimelineMetrics.hourLabelTrailingInset"))

        // The three literals the references replaced. `58` is the hour, `11`/`10` the label size
        // and `9`/`7` the inset; the row's own `rowHeight > 50` ramp is what carried the dead
        // halves, and it is gone with them.
        #expect(!panel.contains("rowHeight > 50"))
        #expect(!panel.contains("rowHeight: CGFloat { 58 }"))
        // Positive and counted rather than only negative: a needle that has stopped matching reads
        // as "no offenders" against every `!contains` above, which is the hollow half of a scan.
        #expect(
            CadenceSourceScan.matchCount(
                "rowHeight: CGFloat \\{ iOSCalendarTimelineMetrics\\.hourHeight \\}",
                in: panel
            ) == 1
        )
    }

    /// The hour rail's width still ramps — it is in `CadenceCalendarWeekGridLayout`, where it is
    /// about how much of the pane the chrome takes from the columns. The label inside it does not,
    /// so the narrow rail is the one that has to hold it: `12 AM` at 11pt measures roughly 31pt.
    @Test func theHourLabelFitsTheNarrowRail() {
        let approximateLabelWidth: CGFloat = 31
        let narrowRail = CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: false)

        #expect(
            approximateLabelWidth + iOSCalendarTimelineMetrics.hourLabelTrailingInset < narrowRail
        )
    }

    // MARK: - The month grid's carried days

    /// **T-568: one dimming layer, at the value the other platform measured.**
    ///
    /// The full-size iOS month cell dimmed a day carried in from a neighbouring month three times
    /// over — `0.58` on the numeral, `0.18 → 0.08` on the badge behind it, and `.opacity(0.52)` on
    /// the whole cell — and SwiftUI multiplies, so the 12pt number landed at **0.30**. macOS had
    /// already stated one token for this and written the floor down beside it: 0.35 gives 1.45:1,
    /// at which a 12pt numeral no longer resolves.
    ///
    /// Both halves are pinned here because either alone can go quietly green. The value assertions
    /// cannot see a *fourth* multiplied layer added to a view body; the source assertions cannot
    /// see the token being retuned to 0.30. `Cadence/iOS/` is inside `#if os(iOS)` and invisible to
    /// this target, which is why the second half has to read text at all.
    @Test func aCarriedMonthDayIsDimmedOnceAtTheMeasuredToken() throws {
        // The token, and the floor its own doc measures. Not `>= 0.35`: 0.35 *is* the value that
        // stops resolving.
        #expect(CadenceCalendarDayBadge.outOfMonthLabelOpacity == 0.50)
        #expect(CadenceCalendarDayBadge.outOfMonthLabelOpacity > 0.35)

        // macOS reads it rather than holding a second copy — the token moved out of
        // `CalendarMonthDayEmphasis` so that iOS could compile it at all.
        #expect(
            CalendarMonthDayEmphasis.outOfMonth.dateLabelColor
                == Theme.dim.opacity(CadenceCalendarDayBadge.outOfMonthLabelOpacity)
        )
        // And macOS's separation is still the plate, which is the shape iOS was moved onto.
        #expect(
            CalendarMonthDayEmphasis.outOfMonth.cellBackground
                != CalendarMonthDayEmphasis.inMonth.cellBackground
        )

        let grid = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthViews.swift")
        )

        // Non-vacuity: the right file, past the comment stripper, with the term the negatives below
        // are looking for still present in it.
        #expect(grid.contains("private struct iOSCalendarMonthDayCell: View"))
        #expect(grid.contains("isCurrentMonth"))

        #expect(grid.contains("Theme.dim.opacity(CadenceCalendarDayBadge.outOfMonthLabelOpacity)"))
        // The plate, not a fade, is what carries "not this month" — a cell-wide opacity also takes
        // the today ring and the event chips down with the numeral.
        #expect(grid.contains("isCurrentMonth ? Theme.surface : Theme.bg"))
        #expect(CadenceSourceScan.matchCount("\\.opacity\\(isCurrentMonth", in: grid) == 0)
        #expect(!grid.contains("isCurrentMonth ? 0.18 : 0.08"))
    }

    // MARK: - The toolbar

    /// The band's vertical padding used to ramp the wrong way: 12 on the phone against 10 on the
    /// iPad, so the device with less vertical room spent more of it on chrome, above a day-header
    /// band already over 100pt tall.
    @Test func theToolbarBandDoesNotVaryByWidth() {
        #expect(iOSCalendarToolbarMetrics.verticalPadding == 10)
        #expect(iOSCalendarToolbarMetrics.titleMinWidth == 208)
    }

    /// The single-row layout is reachable at compact width now — an iPhone in landscape has room for
    /// it — so the title floor has to be the one with a reason on it rather than the phone's old
    /// 116, which was a floor for a title that always had a row to itself.
    ///
    /// This used to measure the floor against `CadencePageHeaderMetrics.tileSize`, the identity
    /// tile the toolbar drew beside the title. Page headers no longer draw one on either platform
    /// (the user asked for them dropped everywhere), and `tileSize` went with the tile — so what is
    /// left beside the title is the row's own spacing, and the floor has to clear that.
    @Test func theTitleFloorLeavesRoomForWhatSitsBesideIt() {
        for isRegular in Self.widths {
            let page = CadencePageHeaderMetrics.metrics(role: .page, isRegularWidth: isRegular)

            #expect(
                iOSCalendarToolbarMetrics.titleMinWidth - page.rowSpacing > 120,
                "title floor at isRegular=\(isRegular)"
            )
        }
    }

    // MARK: - The Board

    /// The compact board's column spacing is the figure `compactColumnWidth` subtracts, so the two
    /// have to be the same number. The view held it privately and the test for the sizing arithmetic
    /// held its own literal.
    @Test func theCompactBoardColumnLeavesTheNextDayPeeking() {
        let containerWidth: CGFloat = 393
        let inset = iOSCalendarBoardMetrics.horizontalPadding(isRegularWidth: false)
        let width = CalendarBoardPlannerSupport.compactColumnWidth(
            containerWidth: containerWidth,
            leadingInset: inset,
            columnSpacing: iOSCalendarBoardMetrics.columnSpacing
        )

        let peek = containerWidth - inset - width - iOSCalendarBoardMetrics.columnSpacing
        #expect(peek > 0)
        #expect(peek / containerWidth > 0.14)
    }
}
