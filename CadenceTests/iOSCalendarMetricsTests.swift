import CoreGraphics
import Foundation
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

    // MARK: - The toolbar

    /// The toolbar's title block is a page header's leading run — back control, identity tile,
    /// title — and it had its own 34/15 tile, drawn at regular width only. Reading the shared
    /// metrics is what makes that unrepeatable; this pins the property that mattered, which is that
    /// the tile is a size the shared type states rather than a literal beside it.
    @Test func theToolbarTileIsThePageHeaderTile() {
        for isRegular in Self.widths {
            let page = CadencePageHeaderMetrics.metrics(role: .page, isRegularWidth: isRegular)

            #expect(page.iconSize == page.tileSize * 0.44)
            #expect(page.tileSize >= 32, "tile \(page.tileSize) at isRegular=\(isRegular)")
        }
    }

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
    @Test func theTitleFloorLeavesRoomForTheTileBesideIt() {
        for isRegular in Self.widths {
            let page = CadencePageHeaderMetrics.metrics(role: .page, isRegularWidth: isRegular)
            let chrome = page.tileSize + page.rowSpacing

            #expect(
                iOSCalendarToolbarMetrics.titleMinWidth - chrome > 120,
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
