import Foundation
import Testing
import SwiftUI
#if os(macOS)
import AppKit
import EventKit
#endif
@testable import Cadence

/// T-3161. Overlapping calendar **events** lay out the way Apple Calendar lays them out: events
/// that start close together split into equal columns, and an event that starts far enough after an
/// event it overlaps cascades — indented from the leading edge, running to the trailing edge, drawn
/// on top.
///
/// The acceptance test is the owner's reference screenshot, and it is in here literally: the two
/// clusters below are the times measured off that image, not invented fixtures.
@Suite
struct CadenceCalendarOverlapLayoutTests {

    // MARK: - Fixtures

    private static func event(_ start: Int, _ end: Int) -> CadenceCalendarOverlapLayout.Slot {
        CadenceCalendarOverlapLayout.Slot(startMin: start, endMin: end, mayCascade: true)
    }

    private static func task(_ start: Int, _ end: Int) -> CadenceCalendarOverlapLayout.Slot {
        CadenceCalendarOverlapLayout.Slot(startMin: start, endMin: end, mayCascade: false)
    }

    private static func minutes(_ hour: Int, _ minute: Int) -> Int { hour * 60 + minute }

    /// The threshold at the screenshot's zoom: a 42pt header over a 75pt hour.
    private static let screenshotGap = CadenceCalendarOverlapLayout.cascadeGapMinutes(
        headerHeight: CadenceCalendarOverlapLayout.macCalendarEventHeaderHeight,
        hourHeight: 75
    )

    /// The Mac Calendar page's reference zoom, the one the owner's screenshot was measured at.
    private static let macHourHeight: CGFloat = 75

    /// The Mac header as it was derived before T-3219 — ONE title line — kept only so the
    /// before/after measurement below states its "before" out of the same constants rather than
    /// out of a typed 29.
    private static var macOneLineHeaderHeight: CGFloat {
        CadenceCalendarOverlapLayout.headerHeight(
            verticalPadding: 3,
            rowSpacing: CadenceCalendarOverlapLayout.macEventLabelRowSpacing,
            titleFontSize: CadenceCalendarOverlapLayout.eventTitleFontSize,
            titleLineCount: 1,
            timeFontSize: CadenceCalendarOverlapLayout.eventTimeFontSize
        )
    }

    private static var macOneLineCascadeGap: Int {
        CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: macOneLineHeaderHeight, hourHeight: macHourHeight)
    }

    // MARK: - 1. The header the threshold is derived from

    /// The line heights the header is built out of are AppKit's, not a guess.
    ///
    /// This is the half that makes "read the real header height out of the block view" checkable:
    /// if a toolchain changes the system font's metrics, the cascade threshold moves, and it moves
    /// here first.
    @Test func theLineHeightTableMatchesWhatAppKitReports() {
        #if os(macOS)
        let layoutManager = NSLayoutManager()
        var checked = 0
        for size in stride(from: CGFloat(7), through: CGFloat(17), by: 1) {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            #expect(
                CadenceCalendarOverlapLayout.lineHeight(forSystemFontSize: size)
                    == layoutManager.defaultLineHeight(for: font),
                "the line-height table disagrees with AppKit at \(size)pt"
            )
            checked += 1
        }
        #expect(checked == 11, "non-vacuity: the sweep checked \(checked) sizes")
        #endif
    }

    /// 42pt on the Mac, 45pt on iOS, each the sum of its own block's padding, spacing and rows.
    @Test func theEventHeaderHeightsAreTheSumsOfTheRowsTheBlocksActuallyDraw() {
        // T-3219: 3pt padding + an 11pt time row + 2pt of spacing + TWO 13pt title rows (the Mac
        // block's own wrap limit). It was 29 — one title line — before.
        #expect(CadenceCalendarOverlapLayout.macEventTitleHeaderLineCount == 2)
        #expect(CadenceCalendarOverlapLayout.macCalendarEventHeaderHeight == CGFloat(42))
        // The Schedule panel pads one point more.
        #expect(CadenceCalendarOverlapLayout.macEventHeaderHeight(verticalPadding: 4) == CGFloat(43))
        #expect(Self.macOneLineHeaderHeight == CGFloat(29), "the one-line header the old threshold was derived from")
        // T-3193: 5pt padding + TWO 13pt title lines (the blocks' `.lineLimit(2)`) + 3pt of
        // spacing + an 11pt time row. It was 32 — one title line — before.
        #expect(CadenceCalendarOverlapLayout.iOSEventTitleLineLimit == 2)
        #expect(CadenceCalendarOverlapLayout.iOSEventHeaderHeight == CGFloat(45))
        #expect(Self.iosOneLineHeaderHeight == CGFloat(32), "the one-line header the old threshold was derived from")
    }

    /// The constants above are mirrored from two view files; this is what stops them drifting.
    @Test func theMirroredRowMetricsStillMatchTheTwoEventBlockBodies() throws {
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineEventBlock.swift")
        )
        #expect(mac.count > 2_000, "non-vacuity: read \(mac.count) characters of the Mac event block")
        #expect(mac.contains("VStack(alignment: .leading, spacing: 2)"))
        #expect(mac.contains("Text(timeRangeLabel)"))
        #expect(mac.contains(".font(.system(size: 9, weight: .semibold))"))
        #expect(mac.contains("Text(item.title)"))
        #expect(mac.contains(".font(.system(size: 11, weight: .semibold))"))

        let style = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineMetrics.swift")
        )
        #expect(style.count > 2_000, "non-vacuity: read \(style.count) characters of the metrics file")
        #expect(style.contains("verticalPadding: 3"), "TimelineBlockStyle.calendar no longer pads 3pt")

        let phone = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        #expect(phone.count > 20_000, "non-vacuity: read \(phone.count) characters of the iOS grid")
        #expect(phone.contains("VStack(alignment: .leading, spacing: 3)"))
        // T-1364 made this padding type-aware. The 5 is still the figure the mirrored
        // constants above are solved for -- it is what the block pads at the sizes
        // `iOSEventHeaderHeight` describes -- so the whole conditional is pinned rather
        // than the bare literal, which would also match the 2pt branch.
        #expect(phone.contains(".padding(.vertical, scaling == .enabled && dynamicTypeSize > .large ? 2 : 5)"))

        // T-3193: the title's line limit, read off the title row of EACH iOS timed block — the
        // first `.lineLimit(` after the 11pt semibold title font — rather than anywhere in the file.
        // T-1364 moved that font onto `cadenceFont(.metadata, base: 11,…)` and lifted the row
        // into each block's own `titleLabel`; the base size is still 11 and the first limit
        // after it is still the title's, so the anchor moved and the rule did not.
        for declaration in ["private struct iOSCalendarEventBlock: View", "struct iOSTimelineTaskBlock: View"] {
            let body = try #require(
                CadenceSourceScan.declarationBody(declaration, in: phone),
                "\(declaration) was not found in the iOS grid"
            )
            let titleFont = try #require(
                body.range(of: ".cadenceFont(.metadata, base: 11, weight: .semibold)"),
                "\(declaration) no longer draws an 11pt semibold title"
            )
            let limit = try #require(
                body.range(of: ".lineLimit(", range: titleFont.upperBound..<body.endIndex),
                "\(declaration)'s title has no line limit"
            )
            // T-3323: the limit is now the block's `titleLineLimit`, which is the shared title-fit
            // rule with the threshold's own line count as its wrap limit — 1 or that, never more.
            let argument = body[limit.upperBound...].prefix { $0 != ")" }
            #expect(argument == "titleLineLimit", "\(declaration)'s title is limited by \(argument), not the title-fit rule")
            #expect(
                body.contains("wrapLimit: CadenceCalendarOverlapLayout.iOSEventTitleLineLimit"),
                "\(declaration)'s title wraps to a line count the cascade threshold does not assume"
            )
        }
    }

    // MARK: - 2. The threshold

    /// Minutes of header, not a tuned constant — and it follows the zoom, because what is being
    /// protected is text whose height in points does not change when an hour does.
    @Test func theThresholdIsTheHeaderHeightDividedByPointsPerMinuteAndFollowsTheZoom() {
        // T-3219: 42pt / (75/60 pt per minute) = 33.6 → 34. It was 29pt / 1.25 = 24 while the
        // threshold was derived from one title line and the block drew two.
        #expect(Self.screenshotGap == 34)
        #expect(Self.macOneLineCascadeGap == 24, "the before figure the measurement below compares against")
        // Zoom out (a shorter hour) and the same text costs more minutes.
        #expect(CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: 29, hourHeight: 50) == 35)
        // Zoom in and it costs fewer.
        #expect(CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: 29, hourHeight: 150) == 12)
        // Rounded up: a gap that clears the header by a fraction of a point does not clear it.
        #expect(CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: 29, hourHeight: 60) == 29)
        // A canvas that has not been laid out is not a zoom level; nothing may cascade there.
        #expect(CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: 29, hourHeight: 0) == Int.max)
    }

    /// The owner's stated acceptance band: the derived threshold must separate the screenshot's
    /// 15-minute gap from its 45-minute one.
    @Test func theDerivedThresholdFallsBetweenTheScreenshotsFifteenAndFortyFiveMinuteGaps() {
        #expect(Self.screenshotGap > 15)
        #expect(Self.screenshotGap <= 45)
    }

    // MARK: - T-3219: the Mac threshold clears the title the Mac block actually draws

    /// **The behaviour this ticket is about, measured: before 24 minutes → after 34.**
    ///
    /// `TimelineEventBlock`'s title wraps to `TimelineEventBlockRows.titleLineLimit` lines, so a
    /// wrapped title draws a 42pt header. The page protected 29pt, which is 24 minutes at the
    /// reference 75pt hour — so an event cascading 24–33 minutes after one whose title wrapped was
    /// drawn over that block's TIME ROW. Every gap in that band must now split instead.
    ///
    /// A count and a relation, never a duration: of the 60 one-minute gaps an overlapping pair can
    /// have here, 37 cascaded before (24…60) and 27 do now (34…60) — the band is exactly the ten
    /// the fix removes, and nothing outside it moved.
    @Test func theLostBandNoLongerCascadesOverAHeaderItDoesNotClear() {
        #expect(Self.macOneLineCascadeGap == 24, "non-vacuity: the before figure is not 24")
        #expect(Self.screenshotGap == 34, "non-vacuity: the after figure is not 34")

        var cascadedBefore = 0
        var cascadedAfter = 0
        var bandChecked = 0
        for gap in 1...60 {
            let slots = [Self.event(540, 540 + 180), Self.event(540 + gap, 540 + gap + 120)]
            let before = CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: Self.macOneLineCascadeGap)
            let after = CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: Self.screenshotGap)
            if before[1].cascadeDepth > 0 { cascadedBefore += 1 }
            if after[1].cascadeDepth > 0 { cascadedAfter += 1 }
            if (24...33).contains(gap) {
                #expect(before[1].cascadeDepth > 0, "non-vacuity: a \(gap)-minute gap did not cascade before either")
                #expect(
                    after[1].cascadeDepth == 0,
                    "a \(gap)-minute gap still lays a block over a wrapped title's time row"
                )
                #expect(after[1].totalColumns == 2, "the \(gap)-minute pair must split into equal halves instead")
                bandChecked += 1
            }
            // Outside the band nothing moved.
            if gap < 24 || gap >= 34 {
                #expect(
                    (before[1].cascadeDepth > 0) == (after[1].cascadeDepth > 0),
                    "a \(gap)-minute gap changed behaviour outside the band the fix removes"
                )
            }
        }
        #expect(bandChecked == 10, "non-vacuity: the sweep checked \(bandChecked) gaps in the band")
        #expect(cascadedBefore == 37)
        #expect(cascadedAfter == 27)
        #expect(cascadedBefore - cascadedAfter == 10, "the fix removed exactly the 24–33 minute cascades")
    }

    #if os(macOS)
    /// The line count the threshold assumes IS the Mac block's own wrap limit, not a second copy
    /// of it. `TimelineEventBlockRows` is `#if os(macOS)` and the layout is Shared, so the two
    /// cannot be one declaration; this is what stops them drifting apart again.
    @Test func theMacThresholdsLineCountIsTheBlocksOwnWrapLimit() {
        #expect(
            CadenceCalendarOverlapLayout.macEventTitleHeaderLineCount == TimelineEventBlockRows.titleLineLimit,
            "the threshold protects \(CadenceCalendarOverlapLayout.macEventTitleHeaderLineCount) title lines while the block wraps to \(TimelineEventBlockRows.titleLineLimit)"
        )
        // And the shared title-fit rule can only ever return 1 or that limit, so the header the
        // threshold is derived from is the worst case rather than an average.
        let wide = TimelineEventBlockRows.titleLineLimit(for: "Design review", availableWidth: 400)
        let narrow = TimelineEventBlockRows.titleLineLimit(for: "Supercalifragilistic", availableWidth: 12)
        #expect(wide == TimelineEventBlockRows.titleLineLimit)
        #expect(narrow == 1)
    }

    /// The Calendar page itself — through the layout call its canvas makes, with the style's own
    /// padding — splits a 30-minute pair and cascades the screenshot's 45-minute one.
    @Test func theMacCalendarPageSplitsAThirtyMinutePairAndStillCascadesTheScreenshotsFortyFive() throws {
        let gap = CadenceCalendarOverlapLayout.cascadeGapMinutes(
            headerHeight: CadenceCalendarOverlapLayout.macEventHeaderHeight(
                verticalPadding: TimelineBlockStyle.calendar.verticalPadding
            ),
            hourHeight: Self.macHourHeight
        )
        #expect(gap == 34, "non-vacuity: the Calendar page's own derivation is \(gap) minutes")

        let thirty = TimelineMetricsSupport.computeUnifiedLayouts(
            tasks: [],
            events: [
                try Self.t3166Item(hour: 9, minute: 0, durationMinutes: 180),
                try Self.t3166Item(hour: 9, minute: 30, durationMinutes: 120),
            ],
            cascadeGapMinutes: gap
        )
        #expect(thirty.events.map(\.cascadeDepth) == [0, 0], "a 30-minute pair still cascades on the Calendar page")
        #expect(thirty.events.map(\.totalColumns) == [2, 2])

        let fortyFive = TimelineMetricsSupport.computeUnifiedLayouts(
            tasks: [],
            events: [
                try Self.t3166Item(hour: 9, minute: 0, durationMinutes: 180),
                try Self.t3166Item(hour: 9, minute: 45, durationMinutes: 120),
            ],
            cascadeGapMinutes: gap
        )
        #expect(fortyFive.events.map(\.cascadeDepth) == [0, 1], "the owner's 45-minute cascade stopped cascading")
        #expect(fortyFive.events.map(\.totalColumns) == [1, 1])
    }

    /// The canvas derives its gap from the block's header at its own style's padding, rather than
    /// from a constant — so the Schedule panel's extra point still costs its extra minute and a
    /// zoom still moves the threshold.
    @Test func theDayCanvasDerivesItsGapFromTheBlockHeaderAtItsOwnPadding() throws {
        let canvas = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineDayCanvas.swift")
        )
        #expect(canvas.count > 2_000, "non-vacuity: read \(canvas.count) characters of the day canvas")
        #expect(canvas.contains("CadenceCalendarOverlapLayout.cascadeGapMinutes("))
        #expect(canvas.contains("headerHeight: CadenceCalendarOverlapLayout.macEventHeaderHeight("))
        #expect(canvas.contains("verticalPadding: style.verticalPadding"))
        #expect(canvas.contains("hourHeight: metrics.hourHeight"))
        #expect(
            !canvas.contains("macCalendarEventHeaderHeight"),
            "the canvas hard-wires the Calendar page's header instead of reading its own style's"
        )
        // One point of padding is one minute of threshold, which is the whole reason the canvas
        // passes its style rather than the constant.
        #expect(
            CadenceCalendarOverlapLayout.cascadeGapMinutes(
                headerHeight: CadenceCalendarOverlapLayout.macEventHeaderHeight(verticalPadding: 4),
                hourHeight: Self.macHourHeight
            ) == 35
        )
    }
    #endif

    // MARK: - 3. The owner's screenshot, by its literal times

    /// THREE events — 2:15–6:15, 3:00–5:45, 4:00–6:00 — cascade. Gaps of 45 and 60 minutes.
    @Test func theScreenshotsThreeEventClusterCascades() {
        let slots = [
            Self.event(Self.minutes(2, 15), Self.minutes(6, 15)),
            Self.event(Self.minutes(3, 0), Self.minutes(5, 45)),
            Self.event(Self.minutes(4, 0), Self.minutes(6, 0))
        ]
        let placed = CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: Self.screenshotGap)

        // One column: every block runs to the trailing edge, exactly as the screenshot shows.
        #expect(placed.map(\.totalColumns) == [1, 1, 1])
        #expect(placed.map(\.column) == [0, 0, 0])
        // And each later start is laid one step deeper over the one before it.
        #expect(placed.map(\.cascadeDepth) == [0, 1, 2])
    }

    /// TWO events — 7:00–10:55 and 7:15–10:00 — split into equal halves. Gap of 15 minutes.
    @Test func theScreenshotsTwoEventClusterSplitsIntoEqualHalves() {
        let slots = [
            Self.event(Self.minutes(7, 0), Self.minutes(10, 55)),
            Self.event(Self.minutes(7, 15), Self.minutes(10, 0))
        ]
        let placed = CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: Self.screenshotGap)

        #expect(placed.map(\.column) == [0, 1])
        #expect(placed.map(\.totalColumns) == [2, 2])
        #expect(placed.map(\.cascadeDepth) == [0, 0], "a 15-minute gap must not cascade")
    }

    /// The indent rule against the edges measured off that screenshot: a column about 345pt wide,
    /// left edges at roughly 0%, ~23% and ~36%.
    @Test func theCascadeIndentLandsOnTheScreenshotsMeasuredLeftEdges() {
        let column: CGFloat = 345
        let first = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: column, depth: 1)
        let second = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: column, depth: 2)

        // 20% of the column, against a rough measurement of ~23%.
        #expect(abs(first / column - 0.20) < 0.001)
        // 36% of the column — the owner's second measurement, exactly.
        #expect(abs(second / column - 0.36) < 0.001)
        // Depth 0 is the old behaviour, untouched.
        #expect(CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: column, depth: 0) == 0)
        // The steps shrink, which is what a rule fitted to ~79pt then ~45pt has to do.
        #expect(second - first < first)
        // And the decay never runs the block out of width.
        let deep = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: column, depth: 12)
        #expect(deep < column)
        #expect(column - deep >= CadenceCalendarOverlapLayout.minimumCascadedWidth)
    }

    // MARK: - 4. Degenerate cases

    @Test func identicalStartTimesNeverCascadeAndAlwaysTakeSeparateColumns() {
        let slots = [Self.event(540, 600), Self.event(540, 660), Self.event(540, 570)]
        let placed = CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: 24)

        #expect(placed.map(\.column) == [0, 1, 2])
        #expect(placed.map(\.cascadeDepth) == [0, 0, 0])
        #expect(placed.map(\.totalColumns) == [3, 3, 3])
    }

    @Test func anEventWhollyContainedInAnotherCascadesWhenItStartsLateEnough() {
        // 9:00–13:00 contains 11:00–12:00; the inner one starts 120 minutes later.
        let placed = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 780), Self.event(660, 720)],
            cascadeGapMinutes: 24
        )
        #expect(placed.map(\.column) == [0, 0])
        #expect(placed.map(\.cascadeDepth) == [0, 1])
        #expect(placed.map(\.totalColumns) == [1, 1])

        // The same containment with a 10-minute gap has to split instead.
        let tight = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 780), Self.event(550, 720)],
            cascadeGapMinutes: 24
        )
        #expect(tight.map(\.column) == [0, 1])
        #expect(tight.map(\.cascadeDepth) == [0, 0])
    }

    /// A overlaps B and B overlaps C, but A does not overlap C.
    @Test func aChainWhereTheEndsDoNotOverlapDoesNotStackCDeeperThanItOverlaps() {
        // A 9:00–10:00, B 9:40–11:00, C 10:30–12:00. A∩C is empty.
        let placed = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 600), Self.event(580, 660), Self.event(630, 720)],
            cascadeGapMinutes: 24
        )
        // B clears A by 40 minutes and stacks on it; C clears B by 50 and stacks on B.
        #expect(placed.map(\.column) == [0, 0, 0])
        #expect(placed.map(\.cascadeDepth) == [0, 1, 2])
        // A sees only B, C sees only B — but the column count is per block, and all are column 0.
        #expect(placed.map(\.totalColumns) == [1, 1, 1])
    }

    @Test func zeroAndFiveMinuteDurationsAreLaidOutWithoutOverlappingAnything() {
        // A zero-length slot has no area, so under half-open overlap it collides with nothing.
        let zero = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 540), Self.event(540, 600)],
            cascadeGapMinutes: 24
        )
        #expect(zero.map(\.column) == [0, 0])
        #expect(zero.map(\.totalColumns) == [1, 1])
        #expect(zero.map(\.cascadeDepth) == [0, 0])

        // Five minutes is the real floor, and a 5-minute event inside a long one still cascades.
        let short = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 720), Self.event(600, 605)],
            cascadeGapMinutes: 24
        )
        #expect(short.map(\.column) == [0, 0])
        #expect(short.map(\.cascadeDepth) == [0, 1])

        // Back-to-back blocks do not overlap at all.
        let abutting = CadenceCalendarOverlapLayout.solve(
            slots: [Self.event(540, 545), Self.event(545, 550)],
            cascadeGapMinutes: 1
        )
        #expect(abutting.map(\.totalColumns) == [1, 1])
        #expect(abutting.map(\.cascadeDepth) == [0, 0])
    }

    @Test func anEmptyDayAndASingleEventAreUnchanged() {
        #expect(CadenceCalendarOverlapLayout.solve(slots: [], cascadeGapMinutes: 24).isEmpty)
        #expect(
            CadenceCalendarOverlapLayout.solve(slots: [Self.event(540, 600)], cascadeGapMinutes: 24)
                == [CadenceCalendarOverlapPlacement.single]
        )
    }

    // MARK: - 5. Tasks and bundles keep equal columns

    /// The owner ruled on events. A task never cascades, and an event never cascades over a task —
    /// so a task always keeps a column of its own and stays visible.
    @Test func tasksNeitherCascadeNorAreCascadedOver() {
        // Two tasks 120 minutes apart: far past any threshold, still two columns.
        let tasks = CadenceCalendarOverlapLayout.solve(
            slots: [Self.task(540, 780), Self.task(660, 720)],
            cascadeGapMinutes: 24
        )
        #expect(tasks.map(\.column) == [0, 1])
        #expect(tasks.map(\.cascadeDepth) == [0, 0])

        // A task first, then an event that clears it by two hours: the event takes its own column.
        let mixed = CadenceCalendarOverlapLayout.solve(
            slots: [Self.task(540, 780), Self.event(660, 720)],
            cascadeGapMinutes: 24
        )
        #expect(mixed.map(\.column) == [0, 1])
        #expect(mixed.map(\.cascadeDepth) == [0, 0])
    }

    /// The mixed cluster the ticket asked to be reasoned about: a task holds a column, and the two
    /// events cascade inside the one that is left.
    @Test func eventsCascadeWithinTheirOwnColumnWhileATaskKeepsItsOwn() {
        let placed = CadenceCalendarOverlapLayout.solve(
            slots: [
                Self.event(540, 780),   // 9:00–13:00
                Self.task(555, 600),    // 9:15–10:00 — too close to the event to be stacked on
                Self.event(660, 720)    // 11:00–12:00 — clears the first event by two hours
            ],
            cascadeGapMinutes: 24
        )
        #expect(placed.map(\.column) == [0, 1, 0])
        #expect(placed.map(\.cascadeDepth) == [0, 0, 1])
        #expect(placed[0].totalColumns == 2, "the first event must still reserve width for the task")
    }

    // MARK: - 6. The geometry the solver feeds

    #if os(macOS)
    /// A cascaded block keeps its column's trailing edge, so the stack reads as a stack.
    @Test func aCascadedFrameIsIndentedAndStillEndsAtItsColumnsTrailingEdge() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 75)
        func frame(depth: Int, columns: Int = 1, column: Int = 0) -> TimelineBlockFrame {
            computeTimelineBlockFrame(
                startMinute: 540,
                durationMinutes: 60,
                column: column,
                totalColumns: columns,
                cascadeDepth: depth,
                totalWidth: 400,
                metrics: metrics,
                style: .calendar
            )
        }

        let base = frame(depth: 0)
        let first = frame(depth: 1)
        let second = frame(depth: 2)

        #expect(first.x > base.x)
        #expect(second.x > first.x)
        // All three end on the same trailing edge.
        #expect(abs((base.x + base.width) - (first.x + first.width)) < 0.001)
        #expect(abs((base.x + base.width) - (second.x + second.width)) < 0.001)
        // And the indent is the shared rule's, not a second copy of it.
        #expect(
            abs(first.x - base.x
                - CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: base.width, depth: 1)) < 0.001
        )

        // In a two-column cluster the cascade stays inside its own column — it does not run over
        // the column beside it, which is where a task would be.
        let rightColumn = frame(depth: 0, columns: 2, column: 1)
        let cascadedLeft = frame(depth: 1, columns: 2, column: 0)
        #expect(cascadedLeft.x + cascadedLeft.width <= rightColumn.x + 0.001)
    }

    /// Depth 0 is byte-for-byte the frame this function produced before T-3161.
    @Test func depthZeroFramesAreUnchangedByTheCascade() {
        let metrics = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: 60)
        let style = TimelineBlockStyle.calendar
        for columns in 1...4 {
            for column in 0..<columns {
                let frame = computeTimelineBlockFrame(
                    startMinute: 600,
                    durationMinutes: 45,
                    column: column,
                    totalColumns: columns,
                    cascadeDepth: 0,
                    totalWidth: 500,
                    metrics: metrics,
                    style: style
                )
                let available = (500 - style.leadingInset - style.trailingInset) * style.blockWidthFraction
                let columnWidth = available / CGFloat(columns)
                #expect(abs(frame.width - (columnWidth - style.columnSpacing)) < 0.001)
                #expect(abs(frame.x - (style.leadingInset + CGFloat(column) * columnWidth)) < 0.001)
            }
        }
    }

    /// Draw order is start order, which is what makes the later block the one on top and the one
    /// that answers a click where the cascade covers its predecessor.
    @Test func eventLayoutsComeBackInStartOrderSoTheLaterBlockIsDrawnOnTop() throws {
        let calendar = Calendar.current
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        func item(hour: Int, minute: Int, durationMinutes: Int) throws -> CalendarEventItem {
            let event = EKEvent(eventStore: EKEventStore())
            event.title = "\(hour):\(minute)"
            let start = try #require(calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: day))
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
            return CalendarEventItem(event: event)
        }

        // The screenshot's three-event cluster, handed over in the wrong order on purpose.
        let middle = try item(hour: 3, minute: 0, durationMinutes: 165)
        let late = try item(hour: 4, minute: 0, durationMinutes: 120)
        let early = try item(hour: 2, minute: 15, durationMinutes: 240)

        let result = TimelineMetricsSupport.computeUnifiedLayouts(
            tasks: [],
            events: [middle, late, early],
            cascadeGapMinutes: 24
        )
        #expect(result.events.map(\.item.startMin) == [135, 180, 240])
        #expect(result.events.map(\.cascadeDepth) == [0, 1, 2])
        #expect(result.events.map(\.totalColumns) == [1, 1, 1])
    }

    // MARK: - T-3166: a covered block drops its calendar-name row rather than stubbing it

    private static func t3166Item(hour: Int, minute: Int, durationMinutes: Int) throws -> CalendarEventItem {
        let calendar = Calendar.current
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "\(hour):\(minute)"
        let start = try #require(calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: day))
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return CalendarEventItem(event: event)
    }

    /// Each event learns where the earliest block cascaded over it starts; a split cluster, whose
    /// blocks sit side by side, covers nothing.
    @Test func eachEventKnowsWhereTheBlockInFrontOfItStarts() throws {
        let cascade = TimelineMetricsSupport.computeUnifiedLayouts(
            tasks: [],
            events: [
                try Self.t3166Item(hour: 2, minute: 15, durationMinutes: 240),
                try Self.t3166Item(hour: 3, minute: 0, durationMinutes: 165),
                try Self.t3166Item(hour: 4, minute: 0, durationMinutes: 120),
            ],
            cascadeGapMinutes: 24
        )
        #expect(cascade.events.map(\.cascadeDepth) == [0, 1, 2], "non-vacuity: the cluster no longer cascades")
        #expect(cascade.events.map(\.coveredFromMinute) == [180, 240, nil])

        let split = TimelineMetricsSupport.computeUnifiedLayouts(
            tasks: [],
            events: [
                try Self.t3166Item(hour: 7, minute: 0, durationMinutes: 235),
                try Self.t3166Item(hour: 7, minute: 15, durationMinutes: 165),
            ],
            cascadeGapMinutes: 24
        )
        #expect(split.events.map(\.totalColumns) == [2, 2], "non-vacuity: the cluster no longer splits")
        #expect(split.events.map(\.coveredFromMinute) == [nil, nil])
    }

    /// The row is drawn on a covered block only when even a two-line title leaves all of it above
    /// the block in front. At the reference 75pt hour that is a 44-minute start gap.
    @Test func aCoveredBlockDrawsItsCalendarRowOnlyWhenAllOfItClearsTheCover() {
        // 3 padding + 11 time + 2 + 2 x 13 title + 2 + 11 calendar row.
        #expect(TimelineEventBlockRows.calendarRowWorstCaseBottom(verticalPadding: 3) == CGFloat(55))

        func shows(gapMinutes: Int?) -> Bool {
            TimelineEventBlockRows.showsCalendarRow(
                frameHeight: 300,
                hasCalendarTitle: true,
                uncoveredHeight: TimelineEventBlockRows.uncoveredHeight(
                    startMinute: 135,
                    coveredFromMinute: gapMinutes.map { 135 + $0 },
                    hourHeight: 75
                ),
                verticalPadding: 3
            )
        }
        #expect(shows(gapMinutes: nil), "an uncovered block lost its calendar row")
        #expect(shows(gapMinutes: 45), "the owner's 45-minute cascade leaves room for the row")
        // The boundary: 44 minutes is exactly 55pt uncovered, 43 is 53.75pt.
        #expect(shows(gapMinutes: 44), "a row that exactly clears the cover was dropped")
        #expect(!shows(gapMinutes: 43), "a row that overruns the cover by a point was kept")
        #expect(!shows(gapMinutes: 34), "the row ran under the block in front at the threshold gap")
        // 45pt clears a ONE-line title's row (42pt) but not a wrapped one's: the case T-3166 saw.
        #expect(!shows(gapMinutes: 36), "the row was kept on the assumption the title does not wrap")
        // The block's own height floor still applies.
        #expect(!TimelineEventBlockRows.showsCalendarRow(
            frameHeight: 53, hasCalendarTitle: true, uncoveredHeight: nil, verticalPadding: 3
        ))
    }

    /// The view draws the calendar row through that rule and with those constants.
    @Test func theMacEventBlockGatesItsCalendarRowOnTheCoveredRule() throws {
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineEventBlock.swift")
        )
        #expect(mac.count > 2_000, "non-vacuity: read \(mac.count) characters of the Mac event block")
        #expect(mac.contains("if TimelineEventBlockRows.showsCalendarRow("))
        #expect(mac.contains("coveredFromMinute: layout.coveredFromMinute"))
        #expect(mac.contains(".lineLimit(\n                            TimelineEventBlockRows.titleLineLimit(\n                                for: item.title,"))
        #expect(mac.contains(".font(.system(size: TimelineEventBlockRows.calendarRowFontSize))"))
        #expect(!mac.contains("frame.height >= 54"), "a second, ungated copy of the row's height floor")
    }

    // MARK: - T-3315: a title word too wide for its column truncates, never breaks mid-word

    /// A title whose widest word overruns the line gets one tail-truncated line; one whose every
    /// word fits keeps the two-line wrap. The boundary is the widest word's own measured width, so
    /// the assertion is a relation to AppKit's metrics rather than a pinned point figure.
    @Test func aTitleWordWiderThanItsLineTruncatesInsteadOfBreakingMidWord() {
        let front = TimelineEventBlockRows.widestTitleWordWidth("Front event A")
        #expect(front > 0, "non-vacuity: the title's words measured as nothing")
        let perWord = ["Front", "event", "A"].map { TimelineEventBlockRows.widestTitleWordWidth($0) }
        #expect(front == perWord.max(), "the title was not measured word by word")
        #expect(TimelineEventBlockRows.titleLineLimit(for: "Front event A", availableWidth: front - 1) == 1,
                "a word one point too wide for its line was left to break between characters")
        #expect(TimelineEventBlockRows.titleLineLimit(for: "Front event A", availableWidth: front) == TimelineEventBlockRows.titleLineLimit,
                "a title whose every word fits lost its second line")
        #expect(TimelineEventBlockRows.titleLineLimit(for: "", availableWidth: 0) == TimelineEventBlockRows.titleLineLimit)

        // The captured geometry: T-3315's cascaded front block at the launcher's default window.
        let narrow = TimelineEventBlockRows.titleWidth(blockWidth: 55, horizontalPadding: 6, isRecurring: false)
        #expect(TimelineEventBlockRows.titleLineLimit(for: "Front event A", availableWidth: narrow) == 1)
    }

    /// The title's width is the block less everything else on the title row, and a series member's
    /// recurrence glyph takes its share.
    @Test func theTitleIsMeasuredAgainstTheWidthLeftBesideItsGlyphs() throws {
        let plain = TimelineEventBlockRows.titleWidth(blockWidth: 120, horizontalPadding: 6, isRecurring: false)
        let recurring = TimelineEventBlockRows.titleWidth(blockWidth: 120, horizontalPadding: 6, isRecurring: true)
        #expect(TimelineEventBlockRows.titleIconWidth > 0)
        #expect(TimelineEventBlockRows.recurrenceGlyphWidth > 0)
        #expect(120 - plain == CadenceCalendarEventStyle.railWidth + 12 + TimelineEventBlockRows.titleIconWidth + TimelineEventBlockRows.titleRowSpacing)
        #expect(plain - recurring == TimelineEventBlockRows.titleRowSpacing + TimelineEventBlockRows.recurrenceGlyphWidth)
        #expect(TimelineEventBlockRows.titleWidth(blockWidth: 0, horizontalPadding: 6, isRecurring: true) == 0)

        // The mirrored glyphs and spacing are the ones the title row draws.
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineEventBlock.swift")
        )
        #expect(mac.count > 2_000, "non-vacuity: read \(mac.count) characters of the Mac event block")
        #expect(TimelineEventBlockRows.titleIconSymbolName == "calendar")
        #expect(TimelineEventBlockRows.recurrenceGlyphSymbolName == "repeat")
        // String literals are blanked by `codeOnly`, so the glyph names are read off the raw file.
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineEventBlock.swift")
        #expect(raw.contains("HStack(alignment: .firstTextBaseline, spacing: 4) {\n                    Image(systemName: \"calendar\")\n                        .font(.system(size: 9, weight: .semibold))"))
        #expect(raw.contains("Image(systemName: \"repeat\")\n                            .font(.system(size: 8, weight: .bold))"))
        #expect(TimelineEventBlockRows.titleRowSpacing == 4)
        #expect(TimelineEventBlockRows.titleIconFontSize == 9)
        #expect(TimelineEventBlockRows.recurrenceGlyphFontSize == 8)
        #expect(mac.contains("horizontalPadding: style.horizontalPadding,\n                                    isRecurring: item.isRecurringSeriesMember"))
    }

    // MARK: - T-3323: the iOS timed blocks share the Mac's title-fit rule

    /// One implementation, both platforms: the Mac names are views of the Shared rule, and the
    /// rule's boundary is the widest word's own measured width at whatever size the title draws.
    @Test func theTitleFitRuleIsSharedAndTruncatesAWordWiderThanItsLine() {
        let title = "Front event A"
        #expect(TimelineEventBlockRows.widestTitleWordWidth(title)
                == CadenceCalendarBlockTitleFit.widestWordWidth(title, fontSize: CadenceCalendarOverlapLayout.eventTitleFontSize))
        // The Dynamic Type sizes an iOS title draws at, through the same scale the block reads.
        for size in [DynamicTypeSize.large, .xxxLarge] {
            let font = CadenceTypeScale.size(.metadata, base: CadenceCalendarBlockTitleFit.iOSTitleBaseSize, at: size, scaling: .enabled)
            let widest = CadenceCalendarBlockTitleFit.widestWordWidth(title, fontSize: font)
            #expect(widest > 0, "non-vacuity: the title's words measured as nothing at \(font)pt")
            #expect(CadenceCalendarBlockTitleFit.titleLineLimit(for: title, fontSize: font, availableWidth: widest - 1, wrapLimit: 2) == 1,
                    "a word one point too wide for its line was left to break between characters at \(font)pt")
            #expect(CadenceCalendarBlockTitleFit.titleLineLimit(for: title, fontSize: font, availableWidth: widest, wrapLimit: 2) == 2,
                    "a title whose every word fits lost its second line at \(font)pt")
        }
        #expect(CadenceTypeScale.size(.metadata, base: 11, at: .xxxLarge, scaling: .enabled) > 11,
                "non-vacuity: the larger text size did not grow the title")
        #expect(CadenceCalendarBlockTitleFit.titleLineLimit(for: "", fontSize: 11, availableWidth: 0, wrapLimit: 2) == 2)
    }

    /// The width each iOS block leaves its title, and the glyph and padding literals it is
    /// mirrored from.
    @Test func theIOSTitleIsMeasuredAgainstTheWidthLeftBesideItsGlyph() throws {
        let fit = CadenceCalendarBlockTitleFit.self
        let glyph = fit.symbolWidth(fit.iOSEventGlyphSymbolName, pointSize: fit.iOSEventGlyphBaseSize)
        #expect(glyph > 0)
        #expect(100 - fit.iOSEventTitleWidth(blockWidth: 100, glyphWidth: glyph)
                == CadenceCalendarEventStyle.railWidth + 14 + glyph + 6)
        #expect(100 - fit.iOSTaskTitleWidth(blockWidth: 100, circleFrameWidth: 11, hasClearTimeControl: false) == CGFloat(14 + 11 + 6))
        #expect(fit.iOSTaskTitleWidth(blockWidth: 100, circleFrameWidth: 11, hasClearTimeControl: false)
                - fit.iOSTaskTitleWidth(blockWidth: 100, circleFrameWidth: 11, hasClearTimeControl: true) == CGFloat(26))
        #expect(fit.iOSEventTitleWidth(blockWidth: 0, glyphWidth: glyph) == 0)
        #expect(fit.iOSTaskTitleWidth(blockWidth: 0, circleFrameWidth: 11, hasClearTimeControl: true) == 0)

        // A cascaded block 60pt wide — the narrow case an iPad week column or a cascade produces —
        // cannot hold "Front" beside its glyph, so both blocks give it one truncated line.
        let event = fit.iOSEventTitleWidth(blockWidth: 60, glyphWidth: glyph)
        let task = fit.iOSTaskTitleWidth(blockWidth: 60, circleFrameWidth: 11, hasClearTimeControl: false)
        #expect(fit.titleLineLimit(for: "Front event A", fontSize: 11, availableWidth: event, wrapLimit: 2) == 1)
        #expect(fit.titleLineLimit(for: "Front event A", fontSize: 11, availableWidth: task, wrapLimit: 2) == 1)
        // A full-width phone day column keeps the wrap.
        #expect(fit.titleLineLimit(for: "Lunch with Sam", fontSize: 11, availableWidth: fit.iOSEventTitleWidth(blockWidth: 300, glyphWidth: glyph), wrapLimit: 2) == 2)

        let phone = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        #expect(phone.count > 20_000, "non-vacuity: read \(phone.count) characters of the iOS grid")
        #expect(fit.iOSHorizontalPadding == 7)
        #expect(fit.iOSLeadingGlyphSpacing == 6)
        #expect(fit.iOSEventGlyphBaseSize == 10)
        #expect(fit.iOSTaskCircleFrameBaseSize == 11)
        #expect(fit.iOSClearTimeTrailingInset == 26)
        #expect(fit.iOSEventGlyphSymbolName == "calendar")
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        #expect(raw.contains("HStack(alignment: .top, spacing: 6) {\n                Image(systemName: \"calendar\")\n                    .cadenceFont(.metadata, base: 10, weight: .semibold)"))
        #expect(phone.contains(".frame(width: CadenceTypeScale.size(.metadata, base: 11, at: dynamicTypeSize, scaling: scaling), height:"))
        #expect(phone.contains(".padding(.trailing, onClearTime == nil ? 0 : 26)"))
        #expect(CadenceSourceScan.matchCount(#"\.padding\(\.horizontal, 7\)"#, in: phone) >= 2)
        for declaration in ["private struct iOSCalendarEventBlock: View", "struct iOSTimelineTaskBlock: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: phone), "\(declaration) was not found")
            #expect(body.contains(".lineLimit(titleLineLimit)\n                            .truncationMode(.tail)")
                    || body.contains(".lineLimit(titleLineLimit)\n                        .truncationMode(.tail)"),
                    "\(declaration)'s two-line title is not tail-truncated by the title-fit rule")
            #expect(body.contains("availableWidth: CadenceCalendarBlockTitleFit.iOS"), "\(declaration) does not measure its own title row")
        }
        #expect(phone.contains("hasClearTimeControl: onClearTime != nil"),
                "the task block measures its title as if the trailing control were never there")
        #expect(phone.contains("endMin: range.end, blockWidth: slot.width, onOpen:"), "the event block is not handed its column width")
        #expect(phone.contains("endMin: range.end,\n                    blockWidth: slot.width,"), "the task block is not handed its column width")
    }

    #endif

    // MARK: - T-3165: the iOS day column lays tasks and events out together

    private typealias IOSLayout = iOSCalendarTimelineBlockLayout

    /// The iPad week column at its narrowest preferred width, which is where a split costs most.
    private static let iosColumnWidth: CGFloat = CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: true)
    private static let iosHourHeight: CGFloat = iOSCalendarTimelineMetrics.hourHeight

    /// Lays `blocks` out exactly as the day column does and returns each one's x range.
    private static func iosRanges(
        _ blocks: [IOSLayout.Block<String>],
        isCompactWidth: Bool = false,
        columnWidth: CGFloat? = nil
    ) -> [String: (placement: CadenceCalendarOverlapPlacement, minX: CGFloat, maxX: CGFloat)] {
        let width = columnWidth ?? iosColumnWidth
        let placements = IOSLayout.placements(
            for: blocks,
            hourHeight: iosHourHeight,
            headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight,
            isCompactWidth: isCompactWidth
        )
        var ranges: [String: (placement: CadenceCalendarOverlapPlacement, minX: CGFloat, maxX: CGFloat)] = [:]
        for block in blocks {
            let placement = placements[block.key] ?? .single
            let frame = IOSLayout.horizontalFrame(for: placement, kind: block.kind, columnWidth: width)
            ranges[block.key] = (placement, frame.x, frame.x + frame.width)
        }
        return ranges
    }

    /// The start gap a compact cascade needs at the grid's resting zoom, read the way the layout
    /// reads it rather than typed.
    private static var iosCascadeGap: Int {
        CadenceCalendarOverlapLayout.cascadeGapMinutes(
            headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight,
            hourHeight: iosHourHeight
        )
    }

    /// The iOS header as it was derived before T-3193 — ONE title line — kept only so the
    /// before/after measurement below states its "before" out of the same constants.
    private static var iosOneLineHeaderHeight: CGFloat {
        CadenceCalendarOverlapLayout.headerHeight(
            verticalPadding: CadenceCalendarOverlapLayout.iOSEventVerticalPadding,
            rowSpacing: CadenceCalendarOverlapLayout.iOSEventLabelRowSpacing,
            titleFontSize: CadenceCalendarOverlapLayout.eventTitleFontSize,
            titleLineCount: 1,
            timeFontSize: CadenceCalendarOverlapLayout.eventTimeFontSize
        )
    }

    private static var iosOneLineCascadeGap: Int {
        CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: iosOneLineHeaderHeight, hourHeight: iosHourHeight)
    }

    /// **T-3193: 47 minutes at rest, derived, not typed.** `ceil(45 / (58 / 60)) = 47`, against the
    /// 34 a one-line header gave. Still zoom-aware: at the 3x pinch the same header costs a third.
    @Test func theIOSThresholdAtRestClearsATwoLineTitleAndIsFortySevenMinutes() {
        #expect(Self.iosHourHeight == CGFloat(58), "non-vacuity: the resting hour this arithmetic assumes moved")
        #expect(Self.iosCascadeGap == 47)
        #expect(Self.iosOneLineCascadeGap == 34, "the before figure the measurement compares against")
        #expect(
            CadenceCalendarOverlapLayout.cascadeGapMinutes(
                headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight,
                hourHeight: Self.iosHourHeight * 3
            ) == 16
        )
    }

    /// One authored workweek — standups, 1:1s, lunches, reviews, focus blocks and errands, every
    /// time on the quarter-hour grid a calendar actually schedules on. **Authored, not the owner's
    /// data** (no agent may read a real calendar); its 20 overlapping pairs start 0 (x5), 15,
    /// 30 (x5), 45 (x5), 60 (x3) and 75 minutes apart, so the reader can weigh it.
    private static let measuredWeek: [[(String, IOSLayout.Kind, Int, Int)]] = [
        [("standup", .event, 540, 555), ("triage", .task, 540, 570), ("design review", .event, 600, 660),
         ("prep slides", .task, 630, 690), ("lunch with sam", .event, 750, 810), ("expenses", .task, 780, 810),
         ("1:1 priya", .event, 840, 870), ("planning", .event, 840, 930), ("write spec", .task, 900, 1020),
         ("team sync", .event, 960, 1005)],
        [("standup", .event, 540, 555), ("code review", .task, 540, 600), ("customer call", .event, 585, 630),
         ("interview", .event, 660, 720), ("lunch", .event, 720, 780), ("recruiter", .task, 735, 765),
         ("architecture", .event, 780, 870), ("vendor demo", .event, 825, 870), ("refactor", .task, 900, 1020),
         ("coffee chat", .event, 960, 990)],
        [("standup", .event, 540, 555), ("all-hands", .event, 600, 660), ("blog post", .task, 600, 690),
         ("lunch and learn", .event, 720, 780), ("sprint planning", .event, 810, 900), ("roadmap", .task, 855, 900),
         ("1:1 manager", .event, 930, 960)],
        [("standup", .event, 540, 555), ("triage", .task, 540, 570), ("workshop", .event, 600, 720),
         ("critique", .event, 645, 690), ("follow-up", .task, 675, 720), ("lunch", .event, 750, 810),
         ("doctor", .event, 900, 960), ("groceries", .task, 930, 990)],
        [("standup", .event, 540, 555), ("prep demo", .task, 630, 675), ("demo day", .event, 660, 750),
         ("retro", .event, 840, 900), ("weekly review", .task, 885, 930), ("happy hour", .event, 1020, 1110)],
    ]

    /// How many blocks of `measuredWeek` are drawn cascaded (depth >= 1) at one start-gap threshold.
    private static func cascadedBlockCount(gap: Int, isCompactWidth: Bool) -> Int {
        measuredWeek.reduce(0) { total, day in
            let slots = day.map {
                CadenceCalendarOverlapLayout.Slot(startMin: $0.2, endMin: $0.3, mayCascade: $0.1.mayCascade(isCompactWidth: isCompactWidth))
            }
            return total + CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: gap)
                .filter { $0.cascadeDepth > 0 }.count
        }
    }

    /// **T-3193's measurement: how often the cascade fires before (34 min) and after (47 min).**
    ///
    /// Two fixtures, both pinned so the ledger's numbers are the test's numbers:
    /// - `measuredWeek` (41 blocks): compact 6 -> 3 cascaded, regular (events only) 2 -> 0.
    /// - Every overlapping pair of durations {30, 45, 60, 90, 120} min at start gaps on the
    ///   quarter-hour grid 15...120 (90 pairs): 45 -> 30 cascade. On that grid the only gap in the
    ///   34–46 band is 45, so "after" loses exactly the 45-minute pairs and nothing else.
    @Test func theCascadeFiresLessOftenAtFortySevenMinutesAndByHowMuch() throws {
        let before = Self.iosOneLineCascadeGap
        let after = Self.iosCascadeGap
        #expect(before == 34 && after == 47, "non-vacuity: the two thresholds being compared moved")

        let blockCount = Self.measuredWeek.reduce(0) { $0 + $1.count }
        #expect(blockCount == 41)
        #expect(Self.cascadedBlockCount(gap: before, isCompactWidth: true) == 6)
        #expect(Self.cascadedBlockCount(gap: after, isCompactWidth: true) == 3)
        #expect(Self.cascadedBlockCount(gap: before, isCompactWidth: false) == 2)
        #expect(Self.cascadedBlockCount(gap: after, isCompactWidth: false) == 0)

        // The production path agrees with the "after" count: `placements` is what the column draws.
        var productionCascaded = 0
        for (dayIndex, day) in Self.measuredWeek.enumerated() {
            let blocks = day.enumerated().map { index, entry in
                IOSLayout.Block(key: "\(dayIndex)-\(index)-\(entry.0)", kind: entry.1, startMin: entry.2, endMin: entry.3)
            }
            let placements = IOSLayout.placements(for: blocks, hourHeight: Self.iosHourHeight, headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight, isCompactWidth: true)
            productionCascaded += placements.values.filter { $0.cascadeDepth > 0 }.count
        }
        #expect(productionCascaded == 3, "the day column's own solver call cascades \(productionCascaded) of the week's blocks")

        var pairs = 0
        var firedBefore = 0
        var firedAfter = 0
        let durations = [30, 45, 60, 90, 120]
        for first in durations {
            for second in durations {
                for gap in stride(from: 15, through: 120, by: 15) where gap < first {
                    let slots = [
                        CadenceCalendarOverlapLayout.Slot(startMin: 0, endMin: first, mayCascade: true),
                        CadenceCalendarOverlapLayout.Slot(startMin: gap, endMin: gap + second, mayCascade: true),
                    ]
                    pairs += 1
                    if CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: before)[1].cascadeDepth > 0 { firedBefore += 1 }
                    if CadenceCalendarOverlapLayout.solve(slots: slots, cascadeGapMinutes: after)[1].cascadeDepth > 0 { firedAfter += 1 }
                }
            }
        }
        #expect(pairs == 90)
        #expect(firedBefore == 45)
        #expect(firedAfter == 30)
    }

    /// A phone's Week column, measured rather than assumed: `CadenceCalendarWeekGridLayout` puts
    /// `compactWeekDayCount` columns across a 393pt iPhone less its 48pt hour rail.
    private static var iosCompactColumnWidth: CGFloat {
        CadenceCalendarWeekGridLayout.dayColumnWidth(
            availableWidth: 393 - CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: false),
            dayCount: CadenceCalendarWeekGridLayout.compactWeekDayCount,
            isRegularWidth: false
        )
    }

    private static func disjoint(_ lhs: (minX: CGFloat, maxX: CGFloat), _ rhs: (minX: CGFloat, maxX: CGFloat)) -> Bool {
        lhs.maxX <= rhs.minX || rhs.maxX <= lhs.minX
    }

    /// The ticket's first fixture pair, by its literal times: "Prep slides" (task, 12:45-1:30) was
    /// painted full width across "Lunch with Sam" (event, 12:30-1:30). They must take two columns
    /// whose x ranges do not overlap, both inside the day column.
    @Test func theIOSDayColumnPutsAnOverlappingTaskBesideTheEventInsteadOfOverIt() throws {
        let ranges = Self.iosRanges([
            .init(key: "lunch", kind: .event, startMin: Self.minutes(12, 30), endMin: Self.minutes(13, 30)),
            .init(key: "prep", kind: .task, startMin: Self.minutes(12, 45), endMin: Self.minutes(13, 30)),
        ])
        let lunch = try #require(ranges["lunch"])
        let prep = try #require(ranges["prep"])
        #expect(lunch.placement.column != prep.placement.column, "the task and the event share a column")
        #expect(lunch.placement.totalColumns == 2 && prep.placement.totalColumns == 2)
        #expect(Self.disjoint((lunch.minX, lunch.maxX), (prep.minX, prep.maxX)), "the task block is drawn over the event block")
        for block in [lunch, prep] {
            #expect(block.minX >= 0 && block.maxX <= Self.iosColumnWidth, "a block runs outside its day column")
            #expect(block.maxX > block.minX, "a block was squeezed to nothing")
        }
    }

    // `theIOSDayColumnPutsAnEventBesideTheBundleItOverlaps` was declared here: T-3165's second
    // fixture pair, a 6 PM event over a Block that sliced "Post office" in half. [[T-3170]] deleted
    // the Block from every iOS surface, so a day column draws two kinds and the pair has no second
    // member. `theIOSDayColumnPutsAnOverlappingTaskBesideTheEventInsteadOfOverIt` above is the same
    // claim on the pair that still exists, and it is the ticket's *first* fixture.

    /// A start gap that is plenty for one event to cascade over another is still not licence for
    /// an event to lay itself over a task — on iOS exactly as on the Mac. The two-event control
    /// proves the gap really is a cascading one, so the task half is not passing by accident.
    @Test func anIOSEventStartingWellAfterATaskStillTakesAColumnBesideIt() throws {
        let gap = CadenceCalendarOverlapLayout.cascadeGapMinutes(
            headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight,
            hourHeight: Self.iosHourHeight
        )
        let start = Self.minutes(9, 0)
        let late = start + gap + 15

        let control = Self.iosRanges([
            .init(key: "first", kind: .event, startMin: start, endMin: start + 180),
            .init(key: "second", kind: .event, startMin: late, endMin: late + 60),
        ])
        #expect(try #require(control["second"]).placement.cascadeDepth == 1, "non-vacuity: this gap no longer cascades two events")

        // One kind here since [[T-3170]]; the loop stays because the claim is "a non-event kind
        // does not cascade at regular width", not "a task does not".
        for kind in [IOSLayout.Kind.task] {
            let ranges = Self.iosRanges([
                .init(key: "work", kind: kind, startMin: start, endMin: start + 180),
                .init(key: "event", kind: .event, startMin: late, endMin: late + 60),
            ])
            let work = try #require(ranges["work"])
            let event = try #require(ranges["event"])
            #expect(event.placement.cascadeDepth == 0, "an event cascaded over a \(kind)")
            #expect(Self.disjoint((work.minX, work.maxX), (event.minX, event.maxX)), "an event is drawn over a \(kind)")
        }
    }

    /// Every kind at one hour takes a column each, in draw order, and none of them covers another
    /// — the property macOS's `computeUnifiedLayouts` already had.
    ///
    /// **It was three kinds and three columns**; [[T-3170]] took the Block, so it is two and two.
    /// The shape is what matters and it is unchanged: `n` blocks at one hour take `n` disjoint
    /// columns, each `totalColumns == n`.
    @Test func everyIOSBlockKindAtOneHourTakesADisjointColumn() throws {
        let ranges = Self.iosRanges([
            .init(key: "event", kind: .event, startMin: Self.minutes(14, 0), endMin: Self.minutes(15, 0)),
            .init(key: "task", kind: .task, startMin: Self.minutes(14, 0), endMin: Self.minutes(15, 0)),
        ])
        let keys = ["event", "task"]
        let placed = try keys.map { try #require(ranges[$0]) }
        #expect(Set(placed.map(\.placement.column)).count == 2, "two overlapping blocks share columns")
        #expect(placed.allSatisfy { $0.placement.totalColumns == 2 })
        for (index, lhs) in placed.enumerated() {
            for rhs in placed[(index + 1)...] {
                #expect(Self.disjoint((lhs.minX, lhs.maxX), (rhs.minX, rhs.maxX)), "two of the three blocks overlap")
            }
        }
    }

    /// Blocks that do not overlap keep the whole of their strip, so a day with no overlaps draws
    /// what it drew before T-3165 — a task as wide as a lone event.
    ///
    /// **The third assertion was the Block's wider strip** — `inset` 7 against the other two kinds'
    /// 9, the one figure the kind enum carried. [[T-3170]] deleted the Block, so `Kind.inset` is a
    /// single 9 and the remaining claim is that the two kinds are drawn at the *same* width, which
    /// is asserted here rather than left implied by one literal.
    @Test func iOSBlocksThatDoNotOverlapEachKeepTheirWholeStrip() throws {
        let ranges = Self.iosRanges([
            .init(key: "task", kind: .task, startMin: Self.minutes(8, 0), endMin: Self.minutes(9, 0)),
            .init(key: "event", kind: .event, startMin: Self.minutes(9, 0), endMin: Self.minutes(10, 0)),
        ])
        let task = try #require(ranges["task"])
        let event = try #require(ranges["event"])
        for block in [task, event] {
            #expect(block.placement == .single, "a block that overlaps nothing was split")
        }
        #expect(task.minX == event.minX && task.maxX == event.maxX, "a lone task and a lone event are drawn at different widths")
        #expect(IOSLayout.Kind.task.inset == IOSLayout.Kind.event.inset, "the two surviving kinds inset differently")
    }

    /// **The view really feeds every kind in.** `Cadence/iOS/` is invisible to this target, so the
    /// arithmetic above is only half the claim; the other half is that the day column hands every
    /// task and event to one `placements` call and draws each block at the frame it gets back,
    /// rather than at a hand-written full width. It was three kinds until [[T-3170]].
    @Test func theIOSDayColumnSolvesEveryTimedBlockInOnePassAndDrawsEachAtItsSolvedFrame() throws {
        let path = "Cadence/iOS/iOSCalendarTimelineViews.swift"
        let raw = try CadenceSourceScan.sourceFile(path)
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.count == raw.count && code != raw, "non-vacuity: the comment stripper did not run over \(path)")
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: code),
            "iOSCalendarTimelineDayColumn was not found in \(path)"
        )
        #expect(column.count > 4_000, "non-vacuity: the day column read as \(column.count) characters")

        #expect(
            CadenceSourceScan.matchCount(#"iOSCalendarTimelineBlockLayout\.placements\(for:"#, in: column) == 1,
            "the day column does not solve its blocks in exactly one pass"
        )
        // T-3265: the header handed in is the type-aware one, from the column's own environment.
        #expect(
            CadenceSourceScan.matchCount(
                #"iOSCalendarTypographyMetrics\.eventHeaderHeight\(at: dynamicTypeSize, scaling: scaling\)"#,
                in: column
            ) == 1,
            "the day column does not derive its cascade header at the reader's text size"
        )
        #expect(
            CadenceSourceScan.matchCount(#"iOSEventHeaderHeight"#, in: column) == 0,
            "the day column hands the solver the default-size header"
        )
        for kind in ["task", "event"] {
            #expect(
                CadenceSourceScan.matchCount(#"key: \.\#(kind)\("#, in: column) == 1,
                "the day column does not hand its \(kind) blocks to the solver"
            )
            #expect(
                CadenceSourceScan.matchCount(#"horizontalFrame\(placements\[\.\#(kind)\("#, in: column) == 1,
                "the day column does not draw its \(kind) blocks at their solved frame"
            )
        }
        // The full-width spelling the tasks were drawn at before T-3165.
        #expect(
            CadenceSourceScan.matchCount(#"\.frame\(width: colWidth - [0-9]+, height:"#, in: column) == 0,
            "a timed block is still drawn at a hand-written full column width"
        )
    }

    // MARK: - T-3265: the cascade header scales with the hour it is divided into

    /// **At the default size, and with scaling off, the type-aware header IS the static one.**
    /// Nothing about the resting threshold (47 minutes) moves.
    @Test func theTypeAwareIOSHeaderIsTheStaticHeaderWhereTextDoesNotGrow() {
        let rest = iOSCalendarTypographyMetrics.eventHeaderHeight(at: .large, scaling: .enabled)
        #expect(rest == CadenceCalendarOverlapLayout.iOSEventHeaderHeight)
        var checked = 0
        for size in DynamicTypeSize.allCases {
            #expect(
                iOSCalendarTypographyMetrics.eventHeaderHeight(at: size, scaling: .fixed)
                    == CadenceCalendarOverlapLayout.iOSEventHeaderHeight,
                "scaling off still moved the header at \(size)"
            )
            checked += 1
        }
        #expect(checked == DynamicTypeSize.allCases.count && checked > 5, "non-vacuity: swept \(checked) sizes")
    }

    /// **Above the default size the header grows by the block's own text growth, less the padding
    /// the block gives back** — two title lines and one time row of `lineGain`, minus the 5 → 2pt
    /// padding drop — and it never shrinks as the size climbs.
    @Test func theTypeAwareIOSHeaderGrowsWithTheBlocksOwnRowsAboveTheDefaultSize() {
        let larger = DynamicTypeSize.allCases.filter { $0 > .large }
        #expect(larger.count > 3, "non-vacuity: only \(larger.count) sizes above .large")
        var previous = iOSCalendarTypographyMetrics.eventHeaderHeight(at: .large, scaling: .enabled)
        var grewPastStatic = 0
        for size in larger {
            let header = iOSCalendarTypographyMetrics.eventHeaderHeight(at: size, scaling: .enabled)
            let rowGrowth = 2 * iOSCalendarTypographyMetrics.lineGain(CadenceCalendarOverlapLayout.eventTitleFontSize, at: size, scaling: .enabled)
                + iOSCalendarTypographyMetrics.lineGain(CadenceCalendarOverlapLayout.eventTimeFontSize, at: size, scaling: .enabled)
            let paddingDrop = CadenceCalendarOverlapLayout.iOSEventVerticalPadding - 2
            #expect(
                abs(header - (CadenceCalendarOverlapLayout.iOSEventHeaderHeight + rowGrowth - paddingDrop)) < 0.001,
                "the header at \(size) is not the static header plus the rows' growth less the padding drop"
            )
            #expect(header >= previous, "the header shrank stepping up to \(size)")
            if header > CadenceCalendarOverlapLayout.iOSEventHeaderHeight { grewPastStatic += 1 }
            previous = header
        }
        #expect(grewPastStatic > 0, "non-vacuity: no larger size grew the header past the static one")
    }

    /// **The production solver cascades at the type-aware threshold, not the mixed one.** At every
    /// larger size where the two thresholds disagree, a pair started exactly the type-aware gap
    /// apart cascades and a pair one minute closer does not.
    @Test func theIOSCascadeUsesTheTypeAwareThresholdAtLargerSizes() {
        var disagreeing = 0
        for size in DynamicTypeSize.allCases where size > .large {
            let hour = iOSCalendarTypographyMetrics.hourHeight(at: size, scaling: .enabled)
            let header = iOSCalendarTypographyMetrics.eventHeaderHeight(at: size, scaling: .enabled)
            let consistent = CadenceCalendarOverlapLayout.cascadeGapMinutes(headerHeight: header, hourHeight: hour)
            let mixed = CadenceCalendarOverlapLayout.cascadeGapMinutes(
                headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight, hourHeight: hour
            )
            guard consistent != mixed else { continue }
            disagreeing += 1
            func cascades(gap: Int) -> Bool {
                let blocks = [
                    IOSLayout.Block(key: "a", kind: .event, startMin: 600, endMin: 900),
                    IOSLayout.Block(key: "b", kind: .event, startMin: 600 + gap, endMin: 900)
                ]
                let placed = IOSLayout.placements(for: blocks, hourHeight: hour, headerHeight: header, isCompactWidth: true)
                return (placed["b"]?.cascadeDepth ?? 0) > 0
            }
            #expect(cascades(gap: consistent), "at \(size) a pair \(consistent) minutes apart did not cascade")
            #expect(!cascades(gap: consistent - 1), "at \(size) a pair \(consistent - 1) minutes apart cascaded")
        }
        #expect(disagreeing > 0, "non-vacuity: the static and type-aware thresholds agree at every larger size")
    }

    // MARK: - T-3184: a compact column cascades every kind, and never buries what it cascades over

    /// **The ruling.** On a compact width a task that starts a header's worth of minutes after an
    /// event it overlaps is laid *over* it — one column, depth 1 — instead of splitting the column
    /// in two. The same pair at regular width still splits, which is the control that says the
    /// fixture really is a cascading one and not merely a non-overlapping one.
    @Test func aCompactIOSColumnCascadesATaskOverTheEventItStartsAfter() throws {
        let start = Self.minutes(12, 30)
        let later = start + Self.iosCascadeGap
        let blocks: [IOSLayout.Block<String>] = [
            .init(key: "lunch", kind: .event, startMin: start, endMin: start + 120),
            .init(key: "prep", kind: .task, startMin: later, endMin: later + 60),
        ]

        let compact = Self.iosRanges(blocks, isCompactWidth: true, columnWidth: Self.iosCompactColumnWidth)
        let lunch = try #require(compact["lunch"])
        let prep = try #require(compact["prep"])
        #expect(lunch.placement.cascadeDepth == 0 && prep.placement.cascadeDepth == 1)
        #expect(lunch.placement.totalColumns == 1 && prep.placement.totalColumns == 1, "the compact pair still split into columns")
        #expect(prep.minX > lunch.minX, "the cascaded task did not indent past the event it is laid over")
        #expect(abs(prep.maxX - lunch.maxX) < 0.001, "a cascaded block must run to its column's trailing edge")

        let regular = Self.iosRanges(blocks, isCompactWidth: false)
        let wideLunch = try #require(regular["lunch"])
        let widePrep = try #require(regular["prep"])
        #expect(widePrep.placement.cascadeDepth == 0, "a regular width cascaded a task over an event")
        #expect(wideLunch.placement.totalColumns == 2 && widePrep.placement.totalColumns == 2)
        #expect(Self.disjoint((wideLunch.minX, wideLunch.maxX), (widePrep.minX, widePrep.maxX)))
    }

    // `aCompactIOSColumnCascadesBundlesOnTheSameRuleAsTasks` was declared here.
    //
    // It walked all four orderings of a Block against an event and a Block against a task, to pin
    // that T-3184 wired Blocks exactly as tasks are — the kind reaching the solver as one `Bool`
    // and nothing in the cascade knowing what a `TaskBundle` was. [[T-3170]] deleted the Block, so
    // there is no third kind to be wired like a second.
    //
    // The claim it protected survives as `theCompactCascadePutsTheLaterStartInFrontWhicheverKindItIs`
    // below, which walks both orderings of the two kinds that are left and is the same statement:
    // the clock decides, the kind does not.

    /// **The precedence is the clock, not the kind.** Handed the same pair in both orders and with
    /// the kinds swapped, the block in front is always the later-starting one.
    @Test func theCompactCascadePutsTheLaterStartInFrontWhicheverKindItIs() throws {
        let early = Self.minutes(8, 0)
        let late = early + Self.iosCascadeGap + 20

        for (earlyKind, lateKind) in [(IOSLayout.Kind.task, IOSLayout.Kind.event), (.event, .task)] {
            let ranges = Self.iosRanges(
                [
                    .init(key: "late", kind: lateKind, startMin: late, endMin: late + 90),
                    .init(key: "early", kind: earlyKind, startMin: early, endMin: early + 240),
                ],
                isCompactWidth: true,
                columnWidth: Self.iosCompactColumnWidth
            )
            #expect(try #require(ranges["early"]).placement.cascadeDepth == 0, "the earlier block was put in front")
            #expect(try #require(ranges["late"]).placement.cascadeDepth == 1, "the later block was not put in front")
        }
    }

    /// A start gap under the threshold still splits at compact width, exactly as it does at regular
    /// width and on the Mac — the ticket's own 12:30/12:45 pair among them. Cascading a 15-minute
    /// gap would paint the front block's body straight across the title row of the one behind,
    /// which is the thing T-3165 removed; the threshold is what stops the ruling becoming that bug.
    @Test func aCompactColumnStillSplitsAPairTooCloseToStackSafely() throws {
        let start = Self.minutes(12, 30)
        let ranges = Self.iosRanges(
            [
                .init(key: "lunch", kind: .event, startMin: start, endMin: start + 60),
                .init(key: "prep", kind: .task, startMin: start + 15, endMin: start + 60),
            ],
            isCompactWidth: true,
            columnWidth: Self.iosCompactColumnWidth
        )
        #expect(Self.iosCascadeGap > 15, "non-vacuity: a 15-minute gap already clears the threshold")
        let lunch = try #require(ranges["lunch"])
        let prep = try #require(ranges["prep"])
        #expect(prep.placement.cascadeDepth == 0)
        #expect(lunch.placement.totalColumns == 2 && prep.placement.totalColumns == 2)
        #expect(Self.disjoint((lunch.minX, lunch.maxX), (prep.minX, prep.maxX)))
    }

    /// **The negative, as pure arithmetic: a cascaded block can never cover the one behind it.**
    ///
    /// This is the property that separates T-3184 from T-3165's bug, so it is swept rather than
    /// sampled — every slot width from a degenerate 1pt up past the widest column any surface
    /// draws, at every depth a stack can reach. The indent must stay strictly inside the slot at
    /// both ends: above 0, so the block behind keeps a leading edge, and below `slotWidth`, so the
    /// block in front is not squeezed out of existence.
    ///
    /// The old clamp failed the first half outright — at `slotWidth <= minimumCascadedWidth` it
    /// returned 0 and the front block covered the whole slot.
    @Test func noCascadedBlockEverCoversTheOneBehindIt() {
        var narrowSlotsSeen = 0
        for tenths in 1...4000 {
            let slotWidth = CGFloat(tenths) / 10
            if slotWidth <= CadenceCalendarOverlapLayout.minimumCascadedWidth { narrowSlotsSeen += 1 }
            for depth in 1...12 {
                let indent = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: slotWidth, depth: depth)
                #expect(indent > 0, "a depth-\(depth) cascade covered a \(slotWidth)pt slot edge to edge")
                #expect(indent < slotWidth, "a depth-\(depth) cascade squeezed a \(slotWidth)pt slot to nothing")
            }
        }
        #expect(narrowSlotsSeen > 0, "non-vacuity: the sweep never reached a slot narrower than the squeeze ceiling")
    }

    /// The sliver the block behind keeps is **the width of its leading marker**, not a round
    /// number: a 3pt rail and the 1pt `strokeBorder` both block bodies draw outside it. Pinned
    /// against `railWidth` so the two cannot drift apart.
    @Test func theCascadeLeavesTheWholeLeadingMarkerOfTheBlockBehindShowing() {
        #expect(
            CadenceCalendarOverlapLayout.minimumVisibleLeadingEdge == CadenceCalendarEventStyle.railWidth + 1,
            "the uncovered sliver no longer matches the rail plus its rim"
        )
        // Wide slots are untouched: the decay already clears the floor, so T-3161's measured edges
        // and macOS's behaviour are exactly what they were.
        for slotWidth in [CGFloat(345), 154, 94, 40, 32] {
            let indent = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: slotWidth, depth: 1)
            #expect(indent >= CadenceCalendarOverlapLayout.minimumVisibleLeadingEdge)
        }
        // And a slot too narrow to pay for the whole marker still splits the difference rather
        // than giving the whole slot to either block.
        let pinched = CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: 6, depth: 1)
        #expect(pinched == 3, "a pinched slot no longer halves itself")
    }

    /// **Draw order is the clock's, across every kind.** The column draws events, then tasks, so
    /// without this a task was painted over every event whatever the solver said — and a task that
    /// cascades under that z order is T-3165's full-width overpaint again. It was three `ForEach`es
    /// until [[T-3170]], the first of them the Block's.
    @Test func theIOSColumnPaintsTheLaterStartingBlockOnTopWhateverKindItIs() throws {
        let blocks: [IOSLayout.Block<String>] = [
            .init(key: "late", kind: .event, startMin: Self.minutes(13, 0), endMin: Self.minutes(14, 0)),
            .init(key: "event", kind: .event, startMin: Self.minutes(9, 0), endMin: Self.minutes(10, 0)),
            .init(key: "task", kind: .task, startMin: Self.minutes(11, 0), endMin: Self.minutes(12, 0)),
        ]
        let z = IOSLayout.zIndexes(for: blocks)
        let event = try #require(z["event"])
        let task = try #require(z["task"])
        let late = try #require(z["late"])
        #expect(event < task && task < late, "the column does not paint in start order")
        for value in [event, task, late] {
            #expect(value >= 1 && value < IOSLayout.overlayZIndex, "a block was given a z outside the band reserved for blocks")
        }
    }

    /// A tie at one start minute falls back to the order the column built its blocks in, so a
    /// redraw cannot swap which of two blocks is on top — the same stability rule `solve` keeps.
    @Test func blocksStartingInTheSameMinuteKeepTheOrderTheyWereHandedIn() throws {
        let blocks: [IOSLayout.Block<String>] = [
            .init(key: "first", kind: .task, startMin: 540, endMin: 600),
            .init(key: "second", kind: .event, startMin: 540, endMin: 600),
        ]
        let z = IOSLayout.zIndexes(for: blocks)
        let first = try #require(z["first"])
        let second = try #require(z["second"])
        #expect(first < second)
        let empty: [IOSLayout.Block<String>] = []
        #expect(IOSLayout.zIndexes(for: empty).isEmpty)
    }

    /// **The view really asks the width question and really paints in the answer's order.**
    /// `Cadence/iOS/` is invisible to this target, so the arithmetic above is only half the claim.
    @Test func theIOSDayColumnTakesItsCompactRulingFromTheSizeClassAndZOrdersEveryBlock() throws {
        let path = "Cadence/iOS/iOSCalendarTimelineViews.swift"
        let raw = try CadenceSourceScan.sourceFile(path)
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.count == raw.count && code != raw, "non-vacuity: the comment stripper did not run over \(path)")
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: code),
            "iOSCalendarTimelineDayColumn was not found in \(path)"
        )
        #expect(column.count > 4_000, "non-vacuity: the day column read as \(column.count) characters")

        #expect(
            CadenceSourceScan.matchCount(#"isCompactWidth: isCompactWidth"#, in: column) == 1,
            "the day column does not pass its width ruling to the solver"
        )
        #expect(
            // [[T-1475]]: a task block lifted for a move or resize is raised to the overlay index
            // while it is held, and reads the solver's order the rest of the time.
            CadenceSourceScan.matchCount(#"\.zIndex\((isLifted \? iOSCalendarTimelineBlockLayout\.overlayZIndex : \()?solved\.zIndexes\[key\]"#, in: column) == 2,
            "the day column does not z-order both of its block kinds"
        )
        #expect(
            // Three since [[T-8142]]: the hovering task's plate rides with them.
            CadenceSourceScan.matchCount(#"\.zIndex\(iOSCalendarTimelineBlockLayout\.overlayZIndex\)"#, in: column) == 3,
            "the draft layer, the hover plate and the now-line are no longer held above the blocks"
        )
        // The size class is resolved once by the grid and handed down, not re-read per column.
        #expect(
            CadenceSourceScan.matchCount(#"horizontalSizeClass"#, in: column) == 0,
            "the day column reads the size class itself instead of taking the grid's answer"
        )
        let grid = try #require(
            CadenceSourceScan.declarationBody("struct iOSCalendarTimelineGrid: View", in: code),
            "iOSCalendarTimelineGrid was not found in \(path)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"isCompactWidth: !isRegularWidth"#, in: grid) == 1,
            "the grid does not derive the column's compact ruling from the size class"
        )
    }
}
