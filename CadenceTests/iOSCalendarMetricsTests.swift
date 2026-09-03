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

    /// **T-596: the fourth figure of the same pair, and the one that had drifted furthest.**
    ///
    /// `theTodayTimelineReadsItsHourFiguresFromHere` above pins the three T-588 settled — the hour,
    /// the label size, the label's inset. The ladder's *lines* were the ones left: Today drew a 1pt
    /// rule at 0.55/0.25 where the Calendar grid drew a 0.5pt one at 0.46/0.20, on the identical
    /// `% 3` cadence, with the identical 0.9/0.45 on the labels beside them. The cadence was copied
    /// and the weights were not, which is what a `% 3` written twice buys.
    ///
    /// Also here because it is the same file and the same shape: one 7pt radius spelled two ways,
    /// `Theme.radiusControl - 3` on the "Creating here" marker and a bare `cornerRadius: 7` on the
    /// slot chip twelve views down. T-616 named that 7pt step `Theme.radiusControlCompact` and
    /// swept both spellings onto it — the token, not `radiusControl - 3`, is now the one this file
    /// should read at both sites (`CadenceRadiusControlCompactSweepTests` owns the app-wide sweep;
    /// this assertion is scoped to the one file this suite already had open).
    @Test func theTodayTimelineDrawsTheSameHourLadder() throws {
        let panel = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodaySchedulePanel.swift")
        )

        // Non-vacuity: the right file, and the row that draws the ladder.
        #expect(panel.contains("private struct iOSScheduleHourRow: View"))

        #expect(panel.contains("iOSCalendarHairlineMetrics.hourMajorOpacity"))
        #expect(panel.contains("iOSCalendarHairlineMetrics.hourMinorOpacity"))
        #expect(panel.contains("iOSCalendarHairlineMetrics.width"))
        #expect(panel.contains("iOSCalendarTimelineMetrics.hourLabelOpacity"))
        #expect(panel.contains("iOSCalendarTimelineMetrics.hourLabelMutedOpacity"))

        // The cadence is read at both places that counted to three, rather than spelled twice.
        #expect(
            CadenceSourceScan.matchCount(
                "iOSCalendarTimelineMetrics\\.hourEmphasisInterval",
                in: panel
            ) == 2
        )
        #expect(CadenceSourceScan.matchCount("% 3 == 0", in: panel) == 0)
        #expect(!panel.contains("0.55 : 0.25"))
        #expect(!panel.contains("0.9 : 0.45"))

        // One 7pt radius, one spelling — the file's only hardcoded radius is gone, and the old
        // `radiusControl - 3` derivation is gone with it: both sites now read the named token.
        #expect(CadenceSourceScan.matchCount("cornerRadius: 7", in: panel) == 0)
        #expect(CadenceSourceScan.matchCount("Theme\\.radiusControl - 3", in: panel) == 0)
        #expect(
            CadenceSourceScan.matchCount("Theme\\.radiusControlCompact", in: panel) == 2
        )
    }

    // MARK: - The hairlines (T-595)

    /// **The sharpest instance the ticket found: one month cell, two weights.** Its right edge drew
    /// `0.30` and its bottom edge `0.42` — the same rule, around the same cell, differing by a third
    /// — while the timed grid's day header four hundred lines away set both of its own edges to one
    /// number. A cell has one edge weight now, and the timed canvas's column rule is that same
    /// weight, because ruling one day off from the next is one job in both presentations.
    @Test func aDayIsRuledOffFromTheNextAtOneWeight() throws {
        #expect(iOSCalendarHairlineMetrics.dayEdgeOpacity == 0.42)
        #expect(iOSCalendarHairlineMetrics.width == 0.5)

        let month = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthViews.swift")
        )
        let timeline = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )

        // Non-vacuity: the right files, past the comment stripper, still holding the views whose
        // edges this is about.
        #expect(month.contains("private struct iOSCalendarMonthDayCell: View"))
        #expect(timeline.contains("private struct iOSCalendarTimelineColumnGridLines: View"))

        // Counted, not merely present: the cell has *two* edges, and a fix that converted one of
        // them and left the other is exactly the state this ticket found.
        #expect(
            CadenceSourceScan.matchCount(
                "iOSCalendarHairlineMetrics\\.dayEdgeOpacity",
                in: month
            ) == 2
        )
        #expect(
            CadenceSourceScan.matchCount(
                "iOSCalendarHairlineMetrics\\.dayEdgeOpacity",
                in: timeline
            ) == 1
        )
        #expect(!month.contains("borderSubtle.opacity(0.30)"))
        #expect(!month.contains("borderSubtle.opacity(0.42)"))
        #expect(!timeline.contains("borderSubtle.opacity(0.34)"))
    }

    /// The two lines that close the chrome the canvas scrolls under — the day-header band's bottom
    /// and the hour rail's trailing side — **meet at the top-left corner of the canvas**, so one of
    /// them being lighter than the other showed up as a corner rather than as an inconsistency. The
    /// band drew 0.65 on both of its edges and the rail 0.75 on its one.
    @Test func thePinnedChromeClosesAtOneWeight() throws {
        #expect(iOSCalendarHairlineMetrics.pinnedEdgeOpacity == 0.65)
        #expect(
            iOSCalendarHairlineMetrics.pinnedEdgeOpacity > iOSCalendarHairlineMetrics.dayEdgeOpacity,
            "chrome closing the canvas reads heavier than a rule inside it"
        )

        let timeline = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        #expect(timeline.contains("private struct iOSCalendarTimeRail: View"))
        // Three: the band's trailing and bottom edges, and the rail's trailing edge.
        #expect(
            CadenceSourceScan.matchCount(
                "iOSCalendarHairlineMetrics\\.pinnedEdgeOpacity",
                in: timeline
            ) == 3
        )
        #expect(!timeline.contains("borderSubtle.opacity(0.75)"))
        #expect(!timeline.contains("borderSubtle.opacity(0.65)"))
    }

    /// The ladder is a cadence and the two weights it selects between, and those three figures only
    /// mean anything together — which is why the cadence lives beside the label figures rather than
    /// being re-spelled `% 3` wherever a line is drawn. Today's timeline spells the identical
    /// cadence; that is how it came to spell a *different* pair of weights (T-596).
    @Test func theHourLadderIsOneCadenceAndTwoWeights() throws {
        #expect(iOSCalendarTimelineMetrics.hourEmphasisInterval == 3)
        #expect(iOSCalendarHairlineMetrics.hourMajorOpacity == 0.46)
        #expect(iOSCalendarHairlineMetrics.hourMinorOpacity == 0.20)
        #expect(iOSCalendarHairlineMetrics.hourMajorOpacity > iOSCalendarHairlineMetrics.hourMinorOpacity)
        #expect(iOSCalendarTimelineMetrics.hourLabelOpacity > iOSCalendarTimelineMetrics.hourLabelMutedOpacity)

        let timeline = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        #expect(timeline.contains("private struct iOSCalendarTimelineColumnGridLines: View"))
        #expect(timeline.contains("iOSCalendarHairlineMetrics.hourMajorOpacity"))
        #expect(timeline.contains("iOSCalendarHairlineMetrics.hourMinorOpacity"))
        #expect(timeline.contains("iOSCalendarTimelineMetrics.hourLabelOpacity"))
        // The cadence is read at both of the places that count to three — the lines and the labels.
        #expect(
            CadenceSourceScan.matchCount(
                "iOSCalendarTimelineMetrics\\.hourEmphasisInterval",
                in: timeline
            ) == 2
        )
        #expect(CadenceSourceScan.matchCount("% 3 == 0", in: timeline) == 0)
    }

    /// The Board's lane separator is **not** in the calendar's hairline vocabulary, and that is the
    /// finding rather than an omission: it already agrees with the Mac's Board, at the same weight
    /// and the same full point. Pulling it onto this screen's grid rule would have broken the
    /// agreement it had in order to fix one it never had.
    @Test func theBoardLaneSeparatorAgreesWithTheMacsBoard() throws {
        #expect(iOSCalendarBoardMetrics.columnSeparatorOpacity == 0.28)
        #expect(iOSCalendarBoardMetrics.columnSeparatorWidth == 1)

        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift")
        )
        #expect(mac.contains("Rectangle()"), "non-vacuity: wrong file, or the stripper ate the code")
        #expect(
            mac.contains("Theme.borderSubtle.opacity(0.28)"),
            "the Mac's lane moved; re-decide the iOS figure against it rather than leaving this stale"
        )
    }

    // MARK: - The month grid's band (T-595)

    /// One row of weekday names, over one grid container, framed at **36** by `iOSCalendarMonthGrid`
    /// and **22** by `iOSCalendarMonthStack`. T-277 hoisted that label's *size* to
    /// `CadenceCalendarWeekdayHeaderMetrics` for exactly this reason and left the band it sits in
    /// behind.
    @Test func theWeekdayBandIsOneHeightInBothMonthContainers() throws {
        #expect(CadenceCalendarWeekdayHeaderMetrics.bandHeight == 22)
        // It is a band around a label, so it has to clear the label: 10pt lays out at about 12.
        #expect(
            CadenceCalendarWeekdayHeaderMetrics.bandHeight
                > CadenceCalendarWeekdayHeaderMetrics.labelSize * 1.2
        )

        for path in [
            "Cadence/iOS/iOSCalendarMonthViews.swift",
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift"
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("weekdayHeaderHeight"), "non-vacuity: \(path)")
            #expect(
                code.contains("CadenceCalendarWeekdayHeaderMetrics.bandHeight"),
                "\(path) still frames the weekday row itself"
            )
            #expect(!code.contains("weekdayHeaderHeight: CGFloat = 36"))
            #expect(!code.contains("weekdayHeaderHeight: CGFloat = 22"))
        }
    }

    /// The other two figures the month grids were typing out: the cell floor its own shared support
    /// file cites in prose, and a bottom padding that was a default *and* a private copy the caller
    /// handed straight back in.
    @Test func theMonthGridsOtherBareFiguresAreNamed() throws {
        #expect(iOSCalendarMonthMetrics.minimumCellHeight == 104)
        #expect(CadenceCalendarMonthAgendaSupport.gridBottomPadding == 8)

        let grid = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthViews.swift")
        )
        #expect(grid.contains("struct iOSCalendarMonthGrid: View"))
        #expect(grid.contains("iOSCalendarMonthMetrics.minimumCellHeight"))
        #expect(CadenceSourceScan.matchCount("max\\(\\s*104", in: grid) == 0)

        let stack = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthAgendaViews.swift")
        )
        #expect(stack.contains("struct iOSCalendarMonthStack"))
        #expect(stack.contains("CadenceCalendarMonthAgendaSupport.gridBottomPadding"))
        #expect(!stack.contains("gridBottomPadding: CGFloat = 8"))

        // And the arithmetic still honours it: padding the grid takes comes out of row height, so a
        // pane that can hold both readings still gets its 44pt touch target.
        let row = CadenceCalendarMonthAgendaSupport.gridRowHeight(
            availableHeight: 900,
            rowCount: CadenceCalendarMonthWindow.visibleRowCount,
            weekdayHeaderHeight: CadenceCalendarWeekdayHeaderMetrics.bandHeight
        )
        #expect(row >= 44)
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

    // MARK: - T-601(b): the two hour rails read one formatter

    /// **The calendar's hour rail hand-rolled the label that `TimeFormatters` already returns.**
    ///
    /// `iOSCalendarTimelineViews` carried a four-line `hourLabel(_:)` — `12 AM`, `n AM`, `12 PM`,
    /// `n - 12 PM` — while `iOSTodaySchedulePanel`, the *other* iOS hour rail and the one this
    /// suite already pins three shared figures against, read
    /// `TimeFormatters.timeString(from: hour * 60)`. Two rails, one screen apart, two answers to
    /// the same question.
    ///
    /// The strings are equal for every hour of the day and the equality is asserted rather than
    /// asserted-about: `timeString` only appends minutes when they are non-zero, and `hour * 60`
    /// never has any, so the shared function returns the retired spelling byte for byte.
    @Test func bothIOSHourRailsFormatTheirLabelsWithTheSharedTimeFormatter() throws {
        for hour in 0..<24 {
            let retired: String
            if hour == 0 { retired = "12 AM" }
            else if hour < 12 { retired = "\(hour) AM" }
            else if hour == 12 { retired = "12 PM" }
            else { retired = "\(hour - 12) PM" }

            #expect(
                TimeFormatters.timeString(from: hour * 60) == retired,
                "hour \(hour): \(TimeFormatters.timeString(from: hour * 60)) != \(retired)"
            )
        }
        // The edges the hand-rolled version existed to special-case.
        #expect(TimeFormatters.timeString(from: 0) == "12 AM")
        #expect(TimeFormatters.timeString(from: 12 * 60) == "12 PM")
        #expect(TimeFormatters.timeString(from: 23 * 60) == "11 PM")

        let timeline = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        // Non-vacuity: the read reached the rail this is about.
        #expect(timeline.contains("CadenceScheduleSupport.calendarHours"))

        #expect(
            CadenceSourceScan.matchCount(#"func hourLabel\("#, in: timeline) == 0,
            "iOSCalendarTimelineViews declares its own hour label again"
        )
        #expect(
            CadenceSourceScan.matchCount(#""12 [AP]M""#, in: timeline) == 0,
            "iOSCalendarTimelineViews still spells a clock hour"
        )
        #expect(timeline.contains("Text(TimeFormatters.timeString(from: hour * 60))"))

        let panel = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodaySchedulePanel.swift")
        )
        #expect(panel.contains("TimeFormatters.timeString(from: hour * 60)"))
    }

    // MARK: - T-601(c): one priority ramp

    /// **Today's schedule row re-implemented `Theme.priorityColor`, and changed one arm.**
    ///
    /// Three of four cases were the shared function's; `.none` returned `Theme.dim.opacity(0.76)`
    /// where the shared one returns `Theme.dim`. That is the only place in the app where an
    /// unprioritised task's completion circle was a fainter grey than an unprioritised task's
    /// completion circle everywhere else — the board card, the calendar chip and the block sheet
    /// all resolve the same control through `CadenceTaskCompletionGlyph`, which is
    /// `Theme.priorityColor`.
    ///
    /// **The 0.76 was checked before it was removed.** It arrives whole in `19fbf8b` (2026-06-12),
    /// a bulk refactor that says nothing about it, in a row where the tint also fed a
    /// `strokeBorder(rowTint.opacity(0.22))`; `fcc8300` (2026-08-04) deleted that border along with
    /// every hard card border in the app, and the value stayed because nothing in a de-bordering
    /// sweep was looking at it. No comment, no test and no sibling names it. That is drift.
    @Test func theTodayScheduleRowTintsFromTheSharedPriorityRamp() throws {
        // The shared ramp, including the arm that was forked. `Theme.dim` is already the muted
        // token; the retired value dimmed it a second time by an unnamed fraction.
        #expect(Theme.priorityColor(.none) == Theme.dim)
        #expect(Theme.priorityColor(.none) != Theme.dim.opacity(0.76))
        #expect(Theme.priorityColor(.high) == Theme.red)
        #expect(Theme.priorityColor(.medium) == Theme.amber)
        #expect(Theme.priorityColor(.low) == Theme.blue)

        // The same control elsewhere already resolved `.none` this way, which is what makes the
        // panel the outlier rather than the ninth opinion.
        #expect(
            CadenceTaskCompletionGlyph.resolve(status: .todo, priority: .none).tint
                == Theme.priorityColor(.none)
        )

        let panel = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodaySchedulePanel.swift")
        )
        // Non-vacuity: the row whose tint this is.
        #expect(panel.contains("iOSTaskCompletionCircle(isDone: false, tint: rowTint)"))

        #expect(
            panel.contains("Theme.priorityColor(task.priority)"),
            "the schedule row does not read the shared priority ramp"
        )
        #expect(
            CadenceSourceScan.matchCount(#"Theme\.dim\.opacity\(0\.76\)"#, in: panel) == 0,
            "the schedule row still dims Theme.dim a second time"
        )
        #expect(
            CadenceSourceScan.matchCount(#"case \.medium:"#, in: panel) == 0,
            "the schedule row switches on priority again"
        )
    }

    // MARK: - One selection layer on the month grid (T-603)

    /// **Three layers at two radii, for one state.** `iOSCalendarMonthDayCell` marked the selected
    /// day with a square-cornered `Theme.blue.opacity(0.075)` wash across the whole cell, *plus* a
    /// `Theme.radiusControl` ring inset 4pt over the top of it, *plus* the solid accent circle
    /// behind the day number that `CadenceCalendarDayBadge.selected` already specifies. The repo's
    /// rule is one hover/selection layer at one radius; the badge is the layer that survives.
    ///
    /// It is also the convergent answer rather than a new one. `iOSCalendarMonthCompactDayCell`
    /// in the agenda grid beside it has always marked selection with the badge alone, so the two
    /// grids in the same feature stop disagreeing about what a tapped day looks like, and macOS's
    /// month grid — which has no per-day selection state at all — is not asked to change.
    ///
    /// **Today's wash stays and is a different fact.** `isToday` is not `isSelected`: macOS's
    /// `CalendarMonthDayEmphasis.cellWash` marks today's cell the same way, so removing it here
    /// would have converged one pair by breaking another.
    @Test func theMonthGridMarksASelectedDayWithItsBadgeAlone() throws {
        // The mapping the surviving layer comes from, and the fact that it genuinely distinguishes
        // the four states — a badge-only selection is only sufficient because the badge differs.
        #expect(CadenceCalendarDayBadge.style(isToday: false, isSelected: true).fill == .solid)
        #expect(CadenceCalendarDayBadge.style(isToday: false, isSelected: false).fill == .none)
        #expect(CadenceCalendarDayBadge.style(isToday: true, isSelected: false).fill == .wash)
        // Today *and* selected still says both, through the ring the badge owns.
        #expect(CadenceCalendarDayBadge.style(isToday: true, isSelected: true).showsTodayRing)
        #expect(!CadenceCalendarDayBadge.style(isToday: false, isSelected: true).showsTodayRing)

        let grid = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthViews.swift")
        )
        let agenda = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthAgendaViews.swift")
        )

        // Non-vacuity: the right files, past the comment stripper, still holding both cells and
        // still reading the shared badge — so a zero below cannot come from an empty read.
        #expect(grid.contains("private struct iOSCalendarMonthDayCell: View"))
        #expect(agenda.contains("private struct iOSCalendarMonthCompactDayCell: View"))
        for source in [grid, agenda] {
            #expect(source.contains("CadenceCalendarDayBadge.style(isToday: isToday, isSelected: isSelected)"))
        }

        // The two retired layers, by the shapes they were spelled in. The cell wash is keyed on
        // `isSelected` and the ring is the only `strokeBorder` a `RoundedRectangle` had in here.
        #expect(
            CadenceSourceScan.matchCount(#"if isSelected \{ return Theme\.blue"#, in: grid) == 0,
            "the month cell still washes the whole cell for the selected day"
        )
        #expect(
            CadenceSourceScan.matchCount(#"Theme\.blue\.opacity\(0\.075\)"#, in: grid) == 0,
            "the retired selection wash is still spelled in the month grid"
        )
        // Scoped to the cell rather than to the file: `iOSCalendarMiniChip` further down draws its
        // own plate at `Theme.radiusControl`, and that is a chip, not a second selection layer. The
        // cell itself should now contain no rounded rectangle at all — its shapes are the badge's
        // circle and two hairline `Rectangle`s.
        let cellStart = try #require(grid.range(of: "private struct iOSCalendarMonthDayCell: View"))
        let cellEnd = try #require(grid.range(of: "struct iOSCalendarMiniChip: View"))
        let cell = String(grid[cellStart.lowerBound..<cellEnd.lowerBound])
        #expect(cell.contains("CadenceCalendarDayBadge"), "non-vacuity: the cell window is the cell")
        #expect(
            CadenceSourceScan.matchCount(#"RoundedRectangle"#, in: cell) == 0,
            "the month cell still draws a rounded selection ring at a second radius"
        )
        #expect(
            CadenceSourceScan.matchCount(#"strokeBorder\(Theme\.blue\.opacity"#, in: cell) == 0,
            "the month cell still strokes a washed-accent selection border"
        )

        // The layer that survives, counted at both cells rather than merely present at one: the
        // whole point is that the two grids agree.
        for (name, source) in [("grid", grid), ("agenda", agenda)] {
            #expect(
                CadenceSourceScan.matchCount(#"CadenceCalendarDayBadge\.washOpacity"#, in: source) == 1,
                "the \(name) cell no longer draws the shared badge wash exactly once"
            )
        }

        // Today's wash is still here, and still the only thing left in `cellWash`.
        #expect(
            grid.contains("isToday ? Theme.blue.opacity(0.045) : nil"),
            "today's cell wash was removed along with the selection's"
        )
    }
}
